#!/usr/bin/env python3
"""Pre-drain guard: move CNPG primaries off the node so the drain can proceed.

Runs on a control-plane host (holds admin.conf), delegated there by ansible, with the
target node's kubernetes name and the drain's per-pod grace period as arguments, AFTER
the node is cordoned and BEFORE it is drained.

CNPG does NOT switch a primary off a cordoned or draining node on its own — verified:
a primary blocks the drain on its always-zero <cluster>-primary PDB for the full
timeout. So the roll must move it. For each CNPG primary on the node, patch
status.targetPrimary to a ready off-node replica (the switchover trigger that
`kubectl cnpg promote` uses) and wait only until the primary ROLE is off the node, so
the drain can evict the node's now-replica instance. A cluster with enablePDB: false has
opted out of that protection (single instance, brief disruption accepted): its primary
is left for the drain to evict, and it restarts on another node.

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
               pod is unhealthy or mid-rollout right now. This usually clears on its
               own in seconds: report it, give it a bounded head start, then evict the
               pods those budgets cover FIRST, with drain's own retrying --timeout.
               Only once they are out does the caller drain the rest of the node; if
               they can't be evicted within that timeout the guard fails BEFORE anything
               else on the node was evicted.

Conflating the two is what wedges a roll: one 30s liveness flap on an unrelated pod used
to abort the node, and because the caller fail-opens, the node silently kept its old
version while the roll moved on. Handing a closed budget to the whole-node drain instead
churned the node: a budget held shut by a crash-looping peer (osticket-mariadb-1) let the
drain evict every other pod on dungeon-chest-002, then time out and uncordon it anyway.

Exit 0 = safe to drain; exit non-zero = no promotion target, switchover didn't take, a
structurally un-evictable PDB covers this node, or the pods a closed budget covers could
not be evicted in time (the caller fail-opens and leaves the node schedulable).
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


def lease_holder(ns, cluster):
    try:
        return json.loads(k("get", "lease", "-n", ns, cluster, "-o", "json"))["spec"].get("holderIdentity", "")
    except subprocess.CalledProcessError:
        return ""


def switchover_primaries_off(node, attempts=60, delay=5):
    primaries = json.loads(k(
        "get", "pods", "-A", "-l", "cnpg.io/instanceRole=primary",
        "--field-selector", f"spec.nodeName={node}", "-o", "json",
    ))["items"]
    moving = []
    for pod in primaries:
        ns = pod["metadata"]["namespace"]
        cluster = pod["metadata"]["labels"]["cnpg.io/cluster"]
        spec = json.loads(k("get", "cluster", "-n", ns, cluster, "-o", "json")).get("spec", {})
        if spec.get("enablePDB") is False:
            # The cluster opted out of disruption protection: CNPG keeps no PDB for it, so
            # the drain evicts its primary with a clean shutdown and it restarts elsewhere.
            print(f"{ns}/{cluster}: enablePDB false, no switchover; the drain restarts it")
            continue
        replicas = json.loads(k(
            "get", "pods", "-n", ns,
            "-l", f"cnpg.io/cluster={cluster},cnpg.io/instanceRole=replica", "-o", "json",
        ))["items"]
        # The switchover target promotes only once it holds the primary Lease. A demoted
        # instance can keep its lease loop running and take the Lease when the primary
        # misses a renewal (CNPG #11720); the target then waits on it forever and the
        # cluster has no primary (gitlab-postgresql, 2026-11-14, five hours). Refuse here.
        holder = lease_holder(ns, cluster)
        if holder != pod["metadata"]["name"]:
            sys.exit(f"{ns}/{cluster}: primary Lease held by {holder or 'nobody'}, not the primary "
                     f"{pod['metadata']['name']}; a switchover would leave it without a primary")
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

    Returns (structural, transient, selectors): human-readable blocker descriptions, and
    the label selector of each transient budget, for evicting its pods ahead of the drain.
    """
    pods = json.loads(k(
        "get", "pods", "-A",
        "--field-selector", f"spec.nodeName={node},status.phase=Running",
        "-o", "json",
    ))["items"]
    pdbs = json.loads(k("get", "pdb", "-A", "-o", "json"))["items"]
    structural, transient, selectors = [], [], []
    for pdb in pdbs:
        status = pdb.get("status", {})
        if status.get("disruptionsAllowed", 1) != 0:
            continue
        # CNPG primary/replica budgets are handled by the switchover above and the
        # post-drain reconcile — not a genuine wedge.
        if "cnpg.io/cluster" in pdb["metadata"].get("labels", {}):
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
        expected = status.get("expectedPods", 0)
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
            selectors.append(",".join(f"{key}={val}" for key, val in sorted(selector.items())))
    return structural, transient, selectors


def wait_for_budgets(node, grace_period, attempts=36, delay=5):
    """Fail on a structural blocker; wait out a transient one, then evict its pods first."""
    structural, transient, selectors = scan_budgets(node)
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
        structural, transient, selectors = scan_budgets(node)
        if structural:
            sys.exit("drain cannot succeed — un-evictable PDB on this node:\n"
                     + "\n".join(f"  {b}" for b in structural))
        if not transient:
            print("PDB budgets recovered")
            return
    # Not yet a failure: the budget still gets drain's full retrying --timeout to open.
    # But only the pods it covers are evicted now, so a budget that never opens fails the
    # node before the rest of it was emptied, instead of after.
    print("WARNING: PDB budgets still closed after waiting; evicting the pods they cover "
          "first — drain retries refused evictions within its own timeout:")
    for blocker in transient:
        print(f"  {blocker}")
    for selector in selectors:
        try:
            subprocess.run(
                ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf", "drain", node,
                 f"--pod-selector={selector}", "--ignore-daemonsets", "--delete-emptydir-data",
                 f"--grace-period={grace_period}", "--timeout=600s"],
                check=True, timeout=660,
            )
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            sys.exit(f"pods under the closed budget ({selector}) could not be evicted in time "
                     f"— nothing else on {node} was evicted")
    print("PDB-blocked pods evicted")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: pre-drain-guard.py <node-name> <grace-period-seconds>")
    node, grace_period = sys.argv[1], sys.argv[2]
    switchover_primaries_off(node)
    wait_for_budgets(node, grace_period)


if __name__ == "__main__":
    main()
