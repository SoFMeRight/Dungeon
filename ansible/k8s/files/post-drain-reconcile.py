#!/usr/bin/env python3
"""Post-drain health gate: SURFACE any CNPG instance that stranded during the drain.

Runs on a control-plane host (holds admin.conf), delegated there by ansible, after the
node is drained and uncordoned.

CNPG does not reliably re-attach an instance after eviction or demotion in this cluster
— some strand shut-down with no standby.signal and never rejoin on their own. This step
DETECTS that and fails loud, naming the affected clusters/instances, so an operator
investigates and repairs them DELIBERATELY.

It does NOT repair anything. Database recovery is never automated here: an unsupervised
re-clone can lose data (a forced re-clone of the wrong lineage in a genuine split-brain
is unrecoverable), and hasteward is only ever run after a human has done the authority
analysis. So the roll's contract is: it makes the drain safe and converges the node, and
if a database strands it STOPS for a human rather than guessing.

Exit 0 = every CNPG cluster is at full health; exit non-zero = one or more clusters are
degraded after the drain and need manual investigation + repair (the caller fail-opens,
leaving the node schedulable).
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf"]
GRACE_SECONDS = 180  # let CNPG re-attach what it can before we call it stranded


def k(*args):
    return subprocess.check_output(KUBECTL + list(args))


def clusters():
    return json.loads(k("get", "cluster", "-A", "-o", "json"))["items"]


def is_healthy(status):
    return status.get("readyInstances") is not None and status.get("readyInstances") == status.get("instances")


def not_ready_instances(ns, cl):
    pods = json.loads(k(
        "get", "pods", "-n", ns,
        "-l", f"cnpg.io/cluster={cl},cnpg.io/podRole=instance", "-o", "json",
    ))["items"]
    return [p["metadata"]["name"] for p in pods
            if not (p["status"].get("containerStatuses")
                    and all(c.get("ready") for c in p["status"]["containerStatuses"]))]


def degraded_clusters():
    return [(c["metadata"]["namespace"], c["metadata"]["name"])
            for c in clusters() if not is_healthy(c.get("status", {}))]


def main():
    degraded = degraded_clusters()
    if not degraded:
        print("all CNPG clusters healthy after drain")
        return

    # A just-evicted replica is briefly not-ready while it reschedules and resumes
    # streaming; give CNPG a grace window before declaring anything stranded.
    print(f"degraded after drain: {', '.join(f'{ns}/{cl}' for ns, cl in degraded)}; "
          f"waiting {GRACE_SECONDS}s for CNPG to re-attach")
    time.sleep(GRACE_SECONDS)

    stranded = []
    for ns, cl in degraded_clusters():
        for inst in not_ready_instances(ns, cl):
            stranded.append(f"{ns}/{cl}: {inst}")

    if stranded:
        detail = "\n".join(f"  {s}" for s in stranded)
        sys.exit(
            "CNPG instance(s) did not recover after the drain and need MANUAL "
            "investigation + repair (do NOT auto-force — see "
            "docs/k8s/cnpg-postgres-cluster-recovery-runbook.md):\n" + detail)

    print("all CNPG clusters healthy after grace")


if __name__ == "__main__":
    main()
