#!/usr/bin/env python3
"""Live state for ONE CNPG cluster: argv = <namespace> <cluster>. READ-ONLY, JSON to stdout:
  {instances, ready, phase, healthy, primary, streaming, old_instances, old_replicas, primary_on_old}
- old_instances : instance data PVCs still on rbd.csi.ceph.com
- old_replicas  : those minus the current primary (safe to reclone now)
- streaming     : pg_stat_replication count reported by the primary (best-effort)
Used by tasks/cnpg-migrate-cluster.yml + cnpg-reclone-instance.yml for the health/quorum gates.
"""
import json
import subprocess
import sys

OLD_DRIVER = "rbd.csi.ceph.com"
ns, cluster = sys.argv[1], sys.argv[2]


def sh(args):
    return subprocess.run(args, capture_output=True, text=True)


c = json.loads(sh(["kubectl", "get", "cluster.postgresql.cnpg.io", cluster, "-n", ns, "-o", "json"]).stdout)
st = c.get("status", {}) or {}
instances = c["spec"].get("instances", 0)
ready = st.get("readyInstances", 0)
phase = st.get("phase", "")
primary = st.get("currentPrimary", "")
insts = st.get("instanceNames") or ["%s-%d" % (cluster, i) for i in range(1, instances + 1)]

pvs = {p["metadata"]["name"]: p for p in json.loads(sh(["kubectl", "get", "pv", "-o", "json"]).stdout)["items"]}


def driver_of(pvc_name):
    r = sh(["kubectl", "get", "pvc", pvc_name, "-n", ns, "-o", "json"])
    if r.returncode != 0:
        return None
    pvc = json.loads(r.stdout)
    pv = pvs.get(pvc["spec"].get("volumeName", ""))
    return (pv["spec"].get("csi") or {}).get("driver") if pv else None


old = [i for i in insts if driver_of(i) == OLD_DRIVER]

streaming = None
if primary:
    r = sh(["kubectl", "exec", "-n", ns, primary, "-c", "postgres", "--",
            "psql", "-tAc", "select count(*) from pg_stat_replication"])
    if r.returncode == 0:
        try:
            streaming = int(r.stdout.strip())
        except ValueError:
            streaming = None

print(json.dumps({
    "instances": instances,
    "ready": ready,
    "phase": phase,
    "healthy": (ready == instances) and ("healthy" in phase.lower()),
    "primary": primary,
    "streaming": streaming,
    "old_instances": old,
    "old_replicas": [i for i in old if i != primary],
    "primary_on_old": primary in old,
}))
