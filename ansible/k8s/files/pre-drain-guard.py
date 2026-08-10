#!/usr/bin/env python3
"""Pre-drain guard for the node-convergence rolls (crio-converge / kubelet-converge).

Runs on a control-plane host (holds admin.conf), delegated there by ansible, with the
target node's kubernetes name as the sole argument. It runs AFTER the node is cordoned.

Cordoning a node makes CNPG proactively switch any primary off it and rejoin the
demoted instance on its own — this is verified CNPG behaviour and it is reliable.
Critically, the guard does NOT switch over manually: an external status.targetPrimary
patch races CNPG's own reconciliation and strands the demoted old primary (it never
rejoins, the cluster sits at N-1, and the next node's drain wedges on the replica PDB).
Letting CNPG own the switchover AND the rejoin is what makes a rolling drain safe.

So the guard only waits and audits:

  1. For every CNPG cluster with an instance on this (already-cordoned) node, wait
     until the cluster is fully healthy (readyInstances == instances) AND its primary
     is OFF this node. That means CNPG has completed the cordon-triggered switchover
     and rejoined the demoted instance, so the drain will evict only healthy replicas
     and the cluster keeps quorum throughout.

  2. Fail fast on any genuine (non-CNPG) zero-disruption PDB, so an unsatisfiable
     budget surfaces as a named cause instead of a full-timeout drain stall. CNPG's
     own primary/replica budgets are excluded — step 1 already accounts for them.

Exit 0 = safe to drain; exit non-zero = CNPG didn't settle in time, or a real PDB
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


def node_of(ns, pod):
    try:
        return json.loads(k("get", "pod", "-n", ns, pod, "-o", "json"))["spec"].get("nodeName", "")
    except subprocess.CalledProcessError:
        return ""


def wait_clusters_ready(node, attempts=60, delay=10):
    """Wait until every CNPG cluster on the node is fully healthy with its primary
    off-node — i.e. CNPG's cordon-triggered switchover + rejoin has completed."""
    targets = clusters_on_node(node)
    if not targets:
        return
    pending = []
    for _ in range(attempts):
        pending = []
        for ns, cl in targets:
            status = json.loads(k("get", "cluster", "-n", ns, cl, "-o", "json")).get("status", {})
            ready, total = status.get("readyInstances"), status.get("instances")
            primary = status.get("currentPrimary", "")
            if ready != total or (primary and node_of(ns, primary) == node):
                pending.append(f"{ns}/{cl} (ready={ready}/{total}, primary={primary})")
        if not pending:
            print(f"all CNPG clusters on {node} healthy with primary off-node")
            return
        time.sleep(delay)
    sys.exit("CNPG did not settle before drain (switchover/rejoin incomplete): " + "; ".join(pending))


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
