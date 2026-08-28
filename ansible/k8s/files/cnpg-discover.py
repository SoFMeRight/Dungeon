#!/usr/bin/env python3
"""Discover CNPG (cloudnative-pg) clusters and count how many of each cluster's instance data PVCs
are still on the standalone ceph-csi driver (rbd.csi.ceph.com). READ-ONLY.

Emits a JSON list; rbd-rook-migrate-cnpg.yml consumes it. Each record:
  key, namespace, name, instances, primary, healthy, old_count, old_instances (names of PVCs on old drv)
"""
import json
import subprocess
import sys

OLD_DRIVER = "rbd.csi.ceph.com"


def kget(*args):
    r = subprocess.run(["kubectl", "get", *args, "-o", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(1)
    return json.loads(r.stdout)


def main():
    clusters = kget("cluster.postgresql.cnpg.io", "-A")["items"]
    pvs = {p["metadata"]["name"]: p for p in kget("pv")["items"]}
    pvcs = {(p["metadata"]["namespace"], p["metadata"]["name"]): p for p in kget("pvc", "-A")["items"]}

    def pvc_driver(ns, name):
        pvc = pvcs.get((ns, name))
        if not pvc:
            return None
        pv = pvs.get(pvc["spec"].get("volumeName", ""))
        if not pv:
            return None
        return (pv["spec"].get("csi") or {}).get("driver")

    out = []
    for c in clusters:
        ns = c["metadata"]["namespace"]
        name = c["metadata"]["name"]
        st = c.get("status", {}) or {}
        instances = c["spec"].get("instances", 0)
        ready = st.get("readyInstances", 0)
        phase = st.get("phase", "")
        primary = st.get("currentPrimary", "")
        healthy = (ready == instances) and ("healthy" in phase.lower())
        # CNPG instance data PVC is named "<cluster>-<N>"; enumerate the instance names from status
        insts = st.get("instanceNames") or ["%s-%d" % (name, i) for i in range(1, instances + 1)]
        old = [i for i in insts if pvc_driver(ns, i) == OLD_DRIVER]
        out.append({
            "key": "%s/%s" % (ns, name),
            "namespace": ns,
            "name": name,
            "instances": instances,
            "primary": primary,
            "healthy": healthy,
            "phase": phase,
            "old_count": len(old),
            "old_instances": old,
        })
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
