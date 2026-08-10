#!/usr/bin/env python3
"""Pre-drain guard for the node-convergence rolls (crio-converge / kubelet-converge).

Runs on a control-plane host (holds admin.conf), delegated there by ansible, with the
target node's kubernetes name as the sole argument. It runs AFTER the node is cordoned
and BEFORE it is drained.

The guard does NOT move CNPG primaries itself. An external status.targetPrimary patch
races CNPG's own reconciliation and strands the demoted old primary; and for
unsupervised clusters CNPG moves the primary on its own DURING the drain (the drain's
eviction of the primary is held by the <cluster>-primary PDB until CNPG promotes a
replica, then the eviction proceeds and CNPG rejoins the demoted instance). So the
guard only makes the drain safe to start:

  1. Wait until every CNPG cluster with an instance on this node is fully healthy
     (readyInstances == instances) — so CNPG has a promotion target and losing this
     node's instance to the drain keeps the cluster above quorum.

  2. Fail fast on any genuine (non-CNPG) zero-disruption PDB, so an unsatisfiable
     budget surfaces as a named cause instead of a full-timeout drain stall. CNPG's
     own primary/replica budgets are excluded — CNPG resolves those during the drain.

Exit 0 = safe to drain; exit non-zero = a cluster is not healthy enough, or a real PDB
would wedge the drain (either way the caller fail-opens and leaves the node schedulable).
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf"]


def k(*args):
    return subprocess.check_output(KUBECTL + list(args))


def clusters_on_node(node):
    """CNPG clusters (namespace, name) that have at least one instance pod on the node."""
    pods = json.loads(k(
        "get", "pods", "-A", "-l", "cnpg.io/cluster",
        "--field-selector", f"spec.nodeName={node}", "-o", "json",
    ))["items"]
    return sorted({(p["metadata"]["namespace"], p["metadata"]["labels"]["cnpg.io/cluster"]) for p in pods})


def wait_clusters_ready(node, attempts=30, delay=10):
    """Wait until every CNPG cluster with an instance on this node is fully healthy
    (readyInstances == instances).

    We do NOT wait for the primary to move off the node here. For unsupervised CNPG
    clusters the primary is switched over by CNPG DURING the drain — the drain's
    eviction of the primary is held by the <cluster>-primary PDB until CNPG promotes a
    replica, then the eviction proceeds and CNPG rejoins the demoted instance. Waiting
    for primary-off before the drain is a deadlock (the switchover needs the drain).
    All this guard must guarantee is that every affected cluster is at full health, so
    CNPG has a promotion target and losing this node's instance keeps quorum."""
    targets = clusters_on_node(node)
    if not targets:
        return
    pending = []
    for _ in range(attempts):
        pending = []
        for ns, cl in targets:
            status = json.loads(k("get", "cluster", "-n", ns, cl, "-o", "json")).get("status", {})
            if status.get("readyInstances") != status.get("instances"):
                pending.append(f"{ns}/{cl} (ready={status.get('readyInstances')}/{status.get('instances')})")
        if not pending:
            print(f"all CNPG clusters on {node} healthy")
            return
        time.sleep(delay)
    sys.exit("CNPG clusters not fully healthy before drain: " + "; ".join(pending))


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
        # CNPG primary/replica budgets are handled by the wait above — not a genuine wedge.
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
    wait_clusters_ready(node)
    audit_pdbs(node)


if __name__ == "__main__":
    main()
