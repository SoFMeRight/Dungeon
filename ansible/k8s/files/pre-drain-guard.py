#!/usr/bin/env python3
"""Pre-drain guard for the node-convergence rolls (crio-converge / kubelet-converge).

Runs on a control-plane host (the one holding admin.conf), delegated there by ansible,
with the target node's kubernetes name as the sole argument. Two jobs, in order:

  1. Move CNPG primaries off the node. CNPG gives every cluster a <cluster>-primary
     PodDisruptionBudget that is ALWAYS disruptionsAllowed=0 — it guards the primary
     ROLE, not the node, so a drain only wedges on it while the primary still lives
     here. For each CNPG primary on the node, promote a ready replica on another node
     (patching status.targetPrimary is the same trigger `kubectl cnpg promote` uses)
     and wait for the cluster to settle. If no ready off-node replica can take the
     role, exit non-zero rather than drain a lone primary into an outage.

  2. Audit the remaining zero-disruption PDBs — non-CNPG only, since the CNPG primary
     budgets are handled above — and fail by name, so a genuinely unsatisfiable budget
     surfaces as a named cause instead of a full-timeout drain stall.

Prints "switched over ..." per promotion (the ansible task keys `changed` on it).
Exit 0 = node is safe to drain; exit non-zero = a primary could not be moved, or a
real PDB would wedge the drain.
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf"]


def k(*args):
    return subprocess.check_output(KUBECTL + list(args))


def ready_off_node(pod, node):
    """A pod that is Ready and NOT on the node being drained — a valid failover target."""
    if pod["spec"].get("nodeName") == node:
        return False
    statuses = pod["status"].get("containerStatuses", [])
    return bool(statuses) and all(cs.get("ready") for cs in statuses)


def wait_primary_off(ns, cluster, node, attempts=60, delay=5):
    """Poll until the primary is off the node AND every OTHER instance is Ready.

    The instance still on this node is about to be drained and rescheduled, so its
    readiness is irrelevant — requiring full cluster health here would wedge on the
    very pod we're about to evict (e.g. a demoted old primary that is slow to rejoin,
    or one that is itself the reason we're draining). What must hold before the drain
    is that the SURVIVING (off-node) instances are healthy, so quorum is preserved.
    """
    for _ in range(attempts):
        current = json.loads(
            k("get", "cluster", "-n", ns, cluster, "-o", "json")).get("status", {}).get("currentPrimary", "")
        pods = json.loads(k("get", "pods", "-n", ns,
            "-l", f"cnpg.io/cluster={cluster}", "-o", "json"))["items"]
        cur_pod = next((p for p in pods if p["metadata"]["name"] == current), None)
        primary_off = cur_pod is not None and cur_pod["spec"].get("nodeName") != node
        off_node = [p for p in pods if p["spec"].get("nodeName") != node]
        survivors_ready = bool(off_node) and all(
            bool(p["status"].get("containerStatuses"))
            and all(cs.get("ready") for cs in p["status"]["containerStatuses"])
            for p in off_node
        )
        if primary_off and survivors_ready:
            print(f"  {ns}/{cluster}: primary now {current}, off {node}; surviving instances ready")
            return True
        time.sleep(delay)
    return False


def switch_primaries_off(node):
    primaries = json.loads(k(
        "get", "pods", "-A",
        "-l", "cnpg.io/instanceRole=primary",
        "--field-selector", f"spec.nodeName={node}",
        "-o", "json",
    ))["items"]
    for pod in primaries:
        ns = pod["metadata"]["namespace"]
        cluster = pod["metadata"]["labels"]["cnpg.io/cluster"]
        replicas = json.loads(k(
            "get", "pods", "-n", ns,
            "-l", f"cnpg.io/cluster={cluster},cnpg.io/instanceRole=replica",
            "-o", "json",
        ))["items"]
        target = next((r["metadata"]["name"] for r in replicas if ready_off_node(r, node)), None)
        if target is None:
            sys.exit(f"{ns}/{cluster}: no ready off-node replica to receive the primary role")
        print(f"switched over {ns}/{cluster}: {pod['metadata']['name']} -> {target}")
        k("patch", "cluster", "-n", ns, cluster, "--subresource", "status",
          "--type", "merge", "-p", json.dumps({"status": {"targetPrimary": target}}))
        if not wait_primary_off(ns, cluster, node):
            sys.exit(f"{ns}/{cluster}: switchover did not settle in time")


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
        # CNPG primary PDBs are always 0 by design and handled by the switchover
        # step above — not a genuine wedge.
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
    switch_primaries_off(node)
    audit_pdbs(node)


if __name__ == "__main__":
    main()
