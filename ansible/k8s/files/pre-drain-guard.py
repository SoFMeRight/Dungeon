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

Then fail-fast on any genuine (non-CNPG) zero-disruption PDB.

Exit 0 = safe to drain; exit non-zero = no promotion target, switchover didn't take, or
a real PDB would wedge the drain (the caller fail-opens and leaves the node schedulable).
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf"]


def k(*args):
    return subprocess.check_output(KUBECTL + list(args))


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


def audit_pdbs(node):
    pods = json.loads(k(
        "get", "pods", "-A",
        "--field-selector", f"spec.nodeName={node},status.phase=Running",
        "-o", "json",
    ))["items"]
    pdbs = json.loads(k("get", "pdb", "-A", "-o", "json"))["items"]
    blockers = []
    for pdb in pdbs:
        if pdb.get("status", {}).get("disruptionsAllowed", 1) != 0:
            continue
        # CNPG primary/replica budgets are handled by the switchover above and the
        # post-drain reconcile — not a genuine wedge.
        if "cnpg.io/cluster" in pdb["metadata"].get("labels", {}):
            continue
        ns = pdb["metadata"]["namespace"]
        selector = pdb.get("spec", {}).get("selector", {}).get("matchLabels", {})
        if not selector:
            continue
        for pod in pods:
            if pod["metadata"]["namespace"] != ns:
                continue
            labels = pod["metadata"].get("labels", {})
            if all(labels.get(key) == val for key, val in selector.items()):
                blockers.append(f"{ns}/{pod['metadata']['name']} "
                                f"(pdb {pdb['metadata']['name']} allows 0 disruptions)")
    if blockers:
        sys.exit("drain would wedge on:\n" + "\n".join(f"  {b}" for b in blockers))


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: pre-drain-guard.py <node-name>")
    node = sys.argv[1]
    switchover_primaries_off(node)
    audit_pdbs(node)


if __name__ == "__main__":
    main()
