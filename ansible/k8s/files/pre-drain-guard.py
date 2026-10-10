#!/usr/bin/env python3
"""Pre-drain guard: move CNPG primaries off the node so the drain can proceed.

Runs on a control-plane host (holds admin.conf), delegated there by ansible, with the
target node's kubernetes name as the sole argument, AFTER the node is cordoned and
BEFORE it is drained.

CNPG does NOT switch a primary off a cordoned or draining node on its own — verified:
a primary blocks the drain on its always-zero <cluster>-primary PDB for the full
timeout. So the roll must move it. For each CNPG primary on the node, patch
status.targetPrimary to a ready off-node replica (the switchover trigger that
`kubectl cnpg promote` uses) and wait only until the primary ROLE is off the node, so
the drain can evict the node's now-replica instance.

We deliberately do NOT wait for the demoted instance to rejoin: CNPG's rejoin after a
demote/eviction is unreliable in this cluster (an instance can strand shut-down with no
standby.signal). Any instance that strands is re-cloned AFTER the drain by
post-drain-reconcile (hasteward repair), which is the one reliable heal.

Then classify every zero-disruption PDB covering a pod on the node. A closed budget is
one of two completely different things and MUST NOT be conflated:

  structural - desiredHealthy >= expectedPods, so no eviction can ever be permitted
               (a single-replica workload with minAvailable: 1). Waiting is futile and
               the drain would burn its whole timeout; fail fast and name it.
  transient  - the budget is closed only because currentHealthy < expectedPods, i.e. a
               pod is unhealthy or mid-rollout right now. This clears on its own in
               seconds. `kubectl drain` already retries refused evictions for its full
               --timeout, so drain is the better waiter: report, give it a bounded head
               start, then hand over. NEVER fail on a transient.

Conflating the two is what wedges a roll: one 30s liveness flap on an unrelated pod used
to abort the node, and because the caller fail-opens, the node silently kept its old
version while the roll moved on.

Exit 0 = safe to drain; exit non-zero = no promotion target, switchover didn't take, or a
structurally un-evictable PDB covers this node (the caller fail-opens and leaves the node
schedulable).
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf", "--request-timeout=20s"]


def k(*args):
    # Bounded: a client --request-timeout AND a hard subprocess ceiling, so a wedged
    # API call fails fast (the caller fail-opens) instead of hanging the drain roll.
    return subprocess.check_output(KUBECTL + list(args), timeout=30)


def node_of(ns, pod):
    try:
        return json.loads(k("get", "pod", "-n", ns, pod, "-o", "json"))["spec"].get("nodeName", "")
    except subprocess.CalledProcessError:
        return ""


def ready_off_node(pod, node):
    if pod["spec"].get("nodeName") == node:
        return False
    statuses = pod["status"].get("containerStatuses", [])
    return bool(statuses) and all(cs.get("ready") for cs in statuses)


def switchover_primaries_off(node, attempts=60, delay=5):
    primaries = json.loads(k(
        "get", "pods", "-A", "-l", "cnpg.io/instanceRole=primary",
        "--field-selector", f"spec.nodeName={node}", "-o", "json",
    ))["items"]
    moving = []
    for pod in primaries:
        ns = pod["metadata"]["namespace"]
        cluster = pod["metadata"]["labels"]["cnpg.io/cluster"]
        replicas = json.loads(k(
            "get", "pods", "-n", ns,
            "-l", f"cnpg.io/cluster={cluster},cnpg.io/instanceRole=replica", "-o", "json",
        ))["items"]
        target = next((r["metadata"]["name"] for r in replicas if ready_off_node(r, node)), None)
        if target is None:
            sys.exit(f"{ns}/{cluster}: no ready off-node replica to promote — cannot drain safely")
        print(f"switching over {ns}/{cluster}: {pod['metadata']['name']} -> {target}")
        k("patch", "cluster", "-n", ns, cluster, "--subresource", "status",
          "--type", "merge", "-p", json.dumps({"status": {"targetPrimary": target}}))
        moving.append((ns, cluster))
    for _ in range(attempts):
        stuck = []
        for ns, cluster in moving:
            current = json.loads(k("get", "cluster", "-n", ns, cluster, "-o", "json")).get("status", {}).get("currentPrimary", "")
            if current and node_of(ns, current) == node:
                stuck.append(f"{ns}/{cluster}")
        if not stuck:
            if moving:
                print(f"all CNPG primaries moved off {node}")
            return
        time.sleep(delay)
    sys.exit("switchover did not move the primary off the node in time: " + "; ".join(stuck))


def scan_budgets(node):
    """Classify every zero-disruption PDB that covers a Running pod on `node`.

    Returns (structural, transient) lists of human-readable blocker descriptions.
    """
    pods = json.loads(k(
        "get", "pods", "-A",
        "--field-selector", f"spec.nodeName={node},status.phase=Running",
        "-o", "json",
    ))["items"]
    pdbs = json.loads(k("get", "pdb", "-A", "-o", "json"))["items"]
    structural, transient = [], []
    for pdb in pdbs:
        status = pdb.get("status", {})
        if status.get("disruptionsAllowed", 1) != 0:
            continue
        # CNPG primary/replica budgets are handled by the switchover above and the
        # post-drain reconcile — not a genuine wedge.
        if "cnpg.io/cluster" in pdb["metadata"].get("labels", {}):
            continue
        # expectedPods 0 means the selector matches nothing cluster-wide (a PDB left
        # behind by a removed app). It can never gate an eviction.
        expected = status.get("expectedPods", 0)
        if not expected:
            continue
        ns = pdb["metadata"]["namespace"]
        selector = pdb.get("spec", {}).get("selector", {}).get("matchLabels", {})
        if not selector:
            continue
        covered = [
            pod["metadata"]["name"] for pod in pods
            if pod["metadata"]["namespace"] == ns
            and all(pod["metadata"].get("labels", {}).get(key) == val
                    for key, val in selector.items())
        ]
        if not covered:
            continue
        desired = status.get("desiredHealthy", 0)
        healthy = status.get("currentHealthy", 0)
        where = f"{ns}/{pdb['metadata']['name']}"
        if desired >= expected:
            structural.append(
                f"{where}: minAvailable leaves no room (desiredHealthy {desired} of "
                f"{expected} pods) — covers {', '.join(covered)}"
            )
        else:
            transient.append(
                f"{where}: {healthy}/{expected} healthy, needs {desired} — "
                f"covers {', '.join(covered)}"
            )
    return structural, transient


def wait_for_budgets(node, attempts=36, delay=5):
    """Fail on a structural blocker; wait out a transient one, then hand over to drain."""
    structural, transient = scan_budgets(node)
    if structural:
        sys.exit("drain cannot succeed — un-evictable PDB on this node:\n"
                 + "\n".join(f"  {b}" for b in structural))
    if not transient:
        return
    print("PDB budget closed by unhealthy pods, waiting:")
    for blocker in transient:
        print(f"  {blocker}")
    for _ in range(attempts):
        time.sleep(delay)
        structural, transient = scan_budgets(node)
        if structural:
            sys.exit("drain cannot succeed — un-evictable PDB on this node:\n"
                     + "\n".join(f"  {b}" for b in structural))
        if not transient:
            print("PDB budgets recovered")
            return
    # Deliberately NOT a failure. kubectl drain retries refused evictions for its own
    # --timeout, so it gets the final say; aborting here would fail-open the node and
    # leave it on the old version, which is the worse outcome.
    print("WARNING: PDB budgets still closed after waiting; proceeding — "
          "drain will retry evictions within its own timeout:")
    for blocker in transient:
        print(f"  {blocker}")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: pre-drain-guard.py <node-name>")
    node = sys.argv[1]
    switchover_primaries_off(node)
    wait_for_budgets(node)


if __name__ == "__main__":
    main()
