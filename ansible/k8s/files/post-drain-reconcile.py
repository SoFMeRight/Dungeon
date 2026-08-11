#!/usr/bin/env python3
"""Post-drain reconcile: re-clone any CNPG instance that stranded during the drain.

Runs on a control-plane host (holds admin.conf), delegated there by ansible, after the
node is drained and uncordoned.

CNPG does not reliably re-attach an instance after eviction or demotion in this cluster
— some strand shut-down with no standby.signal and never rejoin on their own. This step
reconciles every CNPG cluster back to full health: after a short grace period (to let
CNPG re-attach what it can), any instance still not-ready is re-cloned by a hasteward
`repair` Job. hasteward clears the diverged pgdata and pg_basebackups a fresh replica
from the primary — the one operation that heals a stranded instance every time. It runs
as a first-class Kubernetes Job under the existing `hasteward` ServiceAccount +
ClusterRole (no docker-in-docker, no re-implementation of DB recovery in ansible).

Idempotent: a fully healthy fleet does nothing and returns immediately.

Exit 0 = every CNPG cluster is at full health; exit non-zero = a repair Job failed, or a
cluster has no primary to clone from (needs manual attention).
"""
import json
import subprocess
import sys
import time

KUBECTL = ["kubectl", "--kubeconfig", "/etc/kubernetes/admin.conf"]
# latest-dev carries the reseed conninfo fix; :latest (stable) does not yet.
HW_IMAGE = "docker.io/prplanit/hasteward:latest-dev"
HW_NS = "fairy-bottle"
GRACE_SECONDS = 120


def k(*args):
    return subprocess.check_output(KUBECTL + list(args))


def clusters():
    return json.loads(k("get", "cluster", "-A", "-o", "json"))["items"]


def cluster_status(ns, cl):
    return json.loads(k("get", "cluster", "-n", ns, cl, "-o", "json")).get("status", {})


def is_healthy(status):
    return status.get("readyInstances") is not None and status.get("readyInstances") == status.get("instances")


def not_ready_instances(ns, cl):
    pods = json.loads(k(
        "get", "pods", "-n", ns,
        "-l", f"cnpg.io/cluster={cl},cnpg.io/podRole=instance", "-o", "json",
    ))["items"]
    out = []
    for pod in pods:
        cs = pod["status"].get("containerStatuses", [])
        if not (bool(cs) and all(c.get("ready") for c in cs)):
            out.append(pod["metadata"]["name"])
    return out


def ordinal(instance_name):
    return instance_name.rsplit("-", 1)[-1]


def run_repair_job(ns, cl, inst_ordinal, donor_ordinal, attempts=120, delay=10):
    name = f"hw-repair-{cl}-{inst_ordinal}"[:63]
    subprocess.run(KUBECTL + ["-n", HW_NS, "delete", "job", name, "--ignore-not-found"],
                   check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    manifest = {
        "apiVersion": "batch/v1", "kind": "Job",
        "metadata": {"name": name, "namespace": HW_NS,
                     "labels": {"app.kubernetes.io/name": "hasteward",
                                "app.kubernetes.io/component": "reconcile"}},
        "spec": {"ttlSecondsAfterFinished": 600, "backoffLimit": 0,
                 "template": {"metadata": {"labels": {"app.kubernetes.io/name": "hasteward"}},
                              "spec": {"serviceAccountName": "hasteward", "restartPolicy": "Never",
                                       "containers": [{
                                           "name": "hasteward", "image": HW_IMAGE, "imagePullPolicy": "Always",
                                           "args": ["repair", "--donor", str(donor_ordinal)],
                                           "env": [
                                               {"name": "HASTEWARD_ENGINE", "value": "cnpg"},
                                               {"name": "HASTEWARD_CLUSTER", "value": cl},
                                               {"name": "HASTEWARD_NAMESPACE", "value": ns},
                                               {"name": "HASTEWARD_INSTANCE", "value": str(inst_ordinal)},
                                               {"name": "HASTEWARD_FORCE", "value": "true"},
                                               {"name": "HASTEWARD_NO_ESCROW", "value": "true"},
                                           ]}]}}}}
    subprocess.run(KUBECTL + ["apply", "-f", "-"], input=json.dumps(manifest).encode(),
                   check=True, stdout=subprocess.DEVNULL)
    print(f"  repair job {HW_NS}/{name}: {ns}/{cl} instance {inst_ordinal} <- donor {donor_ordinal}")
    for _ in range(attempts):
        st = json.loads(k("get", "job", "-n", HW_NS, name, "-o", "json")).get("status", {})
        if st.get("succeeded"):
            print(f"  ok {name}")
            return True
        if st.get("failed"):
            logs = subprocess.run(KUBECTL + ["-n", HW_NS, "logs", "job/" + name, "--tail=25"],
                                  capture_output=True, text=True).stdout
            print(f"  FAILED {name}:\n{logs}", file=sys.stderr)
            return False
        time.sleep(delay)
    print(f"  TIMEOUT {name}", file=sys.stderr)
    return False


def wait_healthy(ns, cl, attempts=30, delay=10):
    for _ in range(attempts):
        if is_healthy(cluster_status(ns, cl)):
            return True
        time.sleep(delay)
    return False


def main():
    degraded = [(c["metadata"]["namespace"], c["metadata"]["name"])
                for c in clusters() if not is_healthy(c.get("status", {}))]
    if not degraded:
        print("all CNPG clusters healthy — nothing to reconcile")
        return

    print(f"degraded after drain: {', '.join(f'{ns}/{cl}' for ns, cl in degraded)}; "
          f"grace {GRACE_SECONDS}s for CNPG to re-attach")
    time.sleep(GRACE_SECONDS)

    failures = []
    for ns, cl in degraded:
        status = cluster_status(ns, cl)
        if is_healthy(status):
            continue
        primary = status.get("currentPrimary", "")
        if not primary:
            failures.append(f"{ns}/{cl}: no current primary — cluster down, needs manual attention")
            continue
        donor = ordinal(primary)
        print(f"reconcile {ns}/{cl}: {status.get('readyInstances')}/{status.get('instances')}, donor {donor}")
        for inst in not_ready_instances(ns, cl):
            if ordinal(inst) == donor:
                continue  # never re-clone the primary
            if not run_repair_job(ns, cl, ordinal(inst), donor):
                failures.append(f"{ns}/{cl} instance {ordinal(inst)}")
        if not wait_healthy(ns, cl):
            failures.append(f"{ns}/{cl}: not healthy after reconcile")

    if failures:
        sys.exit("post-drain reconcile incomplete: " + "; ".join(failures))
    print("all CNPG clusters healthy after reconcile")


if __name__ == "__main__":
    main()
