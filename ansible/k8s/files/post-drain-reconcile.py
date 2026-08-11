#!/usr/bin/env python3
"""Post-drain health gate: SURFACE any CNPG instance that stranded during the drain.

Runs on a control-plane host (holds admin.conf), delegated there by ansible, after the
node is drained and uncordoned.

CNPG does not always re-attach an instance after eviction or demotion in this cluster —
some strand shut-down with no standby.signal and never rejoin on their own. This step
DETECTS that and fails loud, naming the affected clusters/instances, so an operator
investigates and repairs them DELIBERATELY.

It does NOT repair anything. Database recovery is never automated here: an unsupervised
re-clone can lose data (a forced re-clone of the wrong lineage in a genuine split-brain
is unrecoverable), and hasteward is only ever run after a human has done the authority
analysis. So the roll's contract is: it makes the drain safe and converges the node, and
if a database strands it STOPS for a human rather than guessing.

EVERY kubectl call is bounded — a client --request-timeout AND a hard subprocess timeout
— and the whole check is bounded by RECOVER_DEADLINE, polled at short intervals. A
healthy fleet returns in seconds; a just-evicted replica gets RECOVER_DEADLINE to
re-attach; a wedged or slow API can NEVER hang this gate (an earlier unbounded version
blocked on a single stuck kubectl call for ~51 min until the CI job's wall clock killed
it). If health cannot be read within the deadline it fails loud rather than blocking.

Exit 0 = every CNPG cluster reached full health within the deadline; exit non-zero = one
or more clusters are still degraded (named), or health could not be read at all (the
caller fail-opens, leaving the node schedulable).
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf", "--request-timeout=20s"]
CALL_TIMEOUT = 30        # hard subprocess ceiling on any single kubectl call
RECOVER_DEADLINE = 300   # total time a just-evicted replica gets to re-attach
POLL_INTERVAL = 10       # gap between health polls while still degraded


class KubectlError(Exception):
    pass


def k(*args):
    try:
        return subprocess.run(
            KUBECTL + list(args),
            check=True, capture_output=True, timeout=CALL_TIMEOUT,
        ).stdout
    except subprocess.TimeoutExpired:
        raise KubectlError(f"kubectl {' '.join(args)} timed out after {CALL_TIMEOUT}s")
    except subprocess.CalledProcessError as e:
        raise KubectlError(f"kubectl {' '.join(args)} failed: {e.stderr.decode(errors='replace').strip()}")


def is_healthy(status):
    return status.get("readyInstances") is not None and status.get("readyInstances") == status.get("instances")


def degraded_clusters():
    items = json.loads(k("get", "cluster", "-A", "-o", "json"))["items"]
    return [(c["metadata"]["namespace"], c["metadata"]["name"])
            for c in items if not is_healthy(c.get("status", {}))]


def not_ready_instances(ns, cl):
    pods = json.loads(k(
        "get", "pods", "-n", ns,
        "-l", f"cnpg.io/cluster={cl},cnpg.io/podRole=instance", "-o", "json",
    ))["items"]
    return [p["metadata"]["name"] for p in pods
            if not (p["status"].get("containerStatuses")
                    and all(c.get("ready") for c in p["status"]["containerStatuses"]))]


def main():
    deadline = time.monotonic() + RECOVER_DEADLINE
    degraded = []
    last_error = None

    # Poll until the fleet is healthy or the deadline passes. A healthy fleet returns on
    # the first read (seconds); a just-evicted replica gets RECOVER_DEADLINE to re-attach.
    # A kubectl timeout is treated as transient and retried within the deadline, never as
    # a reason to block.
    while True:
        try:
            degraded = degraded_clusters()
            last_error = None
            if not degraded:
                print("all CNPG clusters healthy after drain")
                return
        except KubectlError as e:
            last_error = str(e)
        if time.monotonic() >= deadline:
            break
        if last_error:
            print(f"health read failed ({last_error}); retrying")
        else:
            print("degraded: " + ", ".join(f"{ns}/{cl}" for ns, cl in degraded)
                  + "; waiting for CNPG to re-attach")
        time.sleep(POLL_INTERVAL)

    if last_error:
        sys.exit(f"could not verify CNPG health within {RECOVER_DEADLINE}s "
                 f"(last error: {last_error}) — investigate manually")

    stranded = []
    for ns, cl in degraded:
        try:
            for inst in not_ready_instances(ns, cl):
                stranded.append(f"{ns}/{cl}: {inst}")
        except KubectlError as e:
            stranded.append(f"{ns}/{cl}: (could not list instances: {e})")

    if stranded:
        detail = "\n".join(f"  {s}" for s in stranded)
        sys.exit(
            f"CNPG instance(s) did not recover within {RECOVER_DEADLINE}s of the drain "
            "and need MANUAL investigation + repair (do NOT auto-force — see "
            "docs/k8s/cnpg-postgres-cluster-recovery-runbook.md):\n" + detail)

    print("all CNPG clusters healthy after grace")


if __name__ == "__main__":
    main()
