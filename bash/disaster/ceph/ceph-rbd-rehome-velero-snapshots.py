#!/usr/bin/env python3
"""Re-home ACTIVE velero CSI VolumeSnapshots from the standalone ceph-csi driver
(rbd.csi.ceph.com) onto the Rook operator driver (gorons-bracelet.rbd.csi.ceph.com),
ZERO-COPY, preserving velero's catalog (the VS name + labels).

Per snapshot (validated on tingle-tuner/velero-data-kasm-0-4hgvv):
  1. read VS + its bound VSC; snapshotHandle = VSC.status.snapshotHandle
  2. escrow both objects (re-appliable) to ESCROW dir
  3. patch old VSC deletionPolicy -> Retain (so the rbd snap survives deletion)
  4. delete old VS + old VSC (force-clear finalizers; snapshotter bypass keeps the snap)
  5. recreate the VS as PRE-PROVISIONED (source.volumeSnapshotContentName=<vsc>),
     preserving velero labels/annotations  -> pending until its VSC exists
  6. recreate the VSC on the OPERATOR driver (source.snapshotHandle=<handle>,
     deletionPolicy=Delete so the HEALTHY operator snapshotter cleans it up on velero
     expiry), volumeSnapshotRef.uid = the new VS uid
  7. verify the VS binds readyToUse=true on the operator driver
On any failure: restore the old VS+VSC from escrow (rbd snap was Retain-preserved).

A dynamic VS can only bind a dynamic VSC, so the VS MUST be recreated as pre-provisioned
to adopt an existing snapshot — this is why the VS (not just the VSC) is recreated.

Usage: rehome-snapshots.py <apply|dryrun> [limit] [ns/vsname ...]
  no targets -> all ACTIVE velero snapshots (backup still exists) on the old driver
env: OLD_DRIVER, NEW_DRIVER, VSCLASS, ESCROW
"""
import json
import os
import subprocess
import sys
import time

OLD = os.environ.get("OLD_DRIVER", "rbd.csi.ceph.com")
NEW = os.environ.get("NEW_DRIVER", "gorons-bracelet.rbd.csi.ceph.com")
VSCLASS = os.environ.get("VSCLASS", "csi-rbdplugin-snapclass")
ESCROW = os.environ.get("ESCROW", "/home/kai/backups/_rbd-rook")
os.makedirs(ESCROW, exist_ok=True)


def k(*args, inp=None, check=True):
    r = subprocess.run(["kubectl", *args], input=inp, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError("kubectl %s: %s" % (" ".join(args), r.stderr.strip()))
    return r


def kjson(*args):
    return json.loads(k(*args).stdout)


def esc(ns, name):
    return ("%s_%s" % (ns, name)).replace("/", "_")


def targets_all():
    vs = kjson("get", "volumesnapshot", "-A", "-o", "json")["items"]
    live = {b["metadata"]["name"] for b in kjson("get", "backups.velero.io", "-A", "-o", "json").get("items", [])}
    out = []
    for v in vs:
        lbl = v["metadata"].get("labels") or {}
        bn = lbl.get("velero.io/backup-name")
        vscn = (v.get("status") or {}).get("boundVolumeSnapshotContentName")
        if not vscn:
            continue
        # only re-home ones still on the OLD driver
        try:
            c = kjson("get", "volumesnapshotcontent", vscn, "-o", "json")
        except RuntimeError:
            continue
        if c["spec"].get("driver") != OLD:
            continue
        if bn and bn in live:  # ACTIVE (backup exists)
            out.append("%s/%s" % (v["metadata"]["namespace"], v["metadata"]["name"]))
    return out


def rehome(ns, name, apply):
    v = kjson("get", "volumesnapshot", name, "-n", ns, "-o", "json")
    vscn = (v.get("status") or {}).get("boundVolumeSnapshotContentName")
    if not vscn:
        return "SKIP(no bound VSC)"
    c = kjson("get", "volumesnapshotcontent", vscn, "-o", "json")
    if c["spec"].get("driver") == NEW:
        return "SKIP(already operator)"
    handle = (c.get("status") or {}).get("snapshotHandle")
    if not handle:
        return "SKIP(no snapshotHandle)"
    if not apply:
        return "WOULD re-home  vsc=%s handle=...%s" % (vscn, handle[-12:])

    e = esc(ns, name)
    open("%s/rehome_%s.vs.json" % (ESCROW, e), "w").write(json.dumps(v))
    open("%s/rehome_%s.vsc.json" % (ESCROW, e), "w").write(json.dumps(c))
    m = v["metadata"]
    labels = m.get("labels", {})
    annos = {kk: vv for kk, vv in (m.get("annotations") or {}).items()
             if not kk.startswith("kubectl.kubernetes.io")}
    vsclass = v["spec"].get("volumeSnapshotClassName") or VSCLASS

    try:
        # 3. protect the rbd snap, 4. delete old VS + VSC (force finalizers)
        k("patch", "volumesnapshotcontent", vscn, "--type=merge",
          "-p", '{"spec":{"deletionPolicy":"Retain"}}', check=False)
        k("delete", "volumesnapshot", name, "-n", ns, "--wait=false", check=False)
        k("patch", "volumesnapshot", name, "-n", ns, "--type=merge",
          "-p", '{"metadata":{"finalizers":null}}', check=False)
        k("delete", "volumesnapshotcontent", vscn, "--wait=false", check=False)
        k("patch", "volumesnapshotcontent", vscn, "--type=merge",
          "-p", '{"metadata":{"finalizers":null}}', check=False)
        for _ in range(20):
            if k("get", "volumesnapshotcontent", vscn, check=False).returncode != 0:
                break
            time.sleep(1)

        # 5. recreate VS as pre-provisioned (pending until VSC exists)
        newvs = {"apiVersion": "snapshot.storage.k8s.io/v1", "kind": "VolumeSnapshot",
                 "metadata": {"name": name, "namespace": ns, "labels": labels, "annotations": annos},
                 "spec": {"source": {"volumeSnapshotContentName": vscn},
                          "volumeSnapshotClassName": vsclass}}
        k("apply", "-f", "-", inp=json.dumps(newvs))
        uid = ""
        for _ in range(15):
            uid = k("get", "volumesnapshot", name, "-n", ns,
                    "-o", "jsonpath={.metadata.uid}", check=False).stdout.strip()
            if uid:
                break
            time.sleep(1)

        # 6. recreate VSC on the operator driver, bound to the new VS
        newvsc = {"apiVersion": "snapshot.storage.k8s.io/v1", "kind": "VolumeSnapshotContent",
                  "metadata": {"name": vscn},
                  "spec": {"deletionPolicy": "Delete", "driver": NEW,
                           "source": {"snapshotHandle": handle},
                           "volumeSnapshotClassName": vsclass,
                           "volumeSnapshotRef": {"apiVersion": "snapshot.storage.k8s.io/v1",
                                                 "kind": "VolumeSnapshot", "name": name,
                                                 "namespace": ns, "uid": uid}}}
        k("apply", "-f", "-", inp=json.dumps(newvsc))

        # 7. verify bind
        for _ in range(20):
            r = k("get", "volumesnapshot", name, "-n", ns,
                  "-o", "jsonpath={.status.readyToUse}", check=False).stdout.strip()
            if r == "true":
                return "OK re-homed"
            time.sleep(3)
        return "FAIL(not ready) — left on operator (snap intact); check %s" % name
    except Exception as ex:
        # rollback: restore old VS + VSC from escrow
        k("apply", "-f", "%s/rehome_%s.vsc.json" % (ESCROW, e), check=False)
        k("apply", "-f", "%s/rehome_%s.vs.json" % (ESCROW, e), check=False)
        return "ROLLBACK(%s)" % str(ex)[:80]


def main():
    apply = sys.argv[1] == "apply" if len(sys.argv) > 1 else False
    limit = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 0
    explicit = [a for a in sys.argv[3:]] if len(sys.argv) > 3 else []
    tgts = explicit or targets_all()
    if limit:
        tgts = tgts[:limit]
    print("mode=%s targets=%d" % ("APPLY" if apply else "DRYRUN", len(tgts)))
    from collections import Counter
    res = Counter()
    for t in tgts:
        ns, name = t.split("/", 1)
        try:
            r = rehome(ns, name, apply)
        except Exception as ex:
            r = "ERROR(%s)" % str(ex)[:80]
        tag = r.split("(")[0].split(" ")[0]
        res[tag] += 1
        print("  %-55s %s" % (t, r))
    print("=== summary ===")
    for kk, n in res.most_common():
        print("  %-16s %d" % (kk, n))


if __name__ == "__main__":
    main()
