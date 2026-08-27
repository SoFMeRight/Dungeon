#!/usr/bin/env python3
"""Discover RBD PVCs still on the standalone ceph-csi Helm driver (rbd.csi.ceph.com) and classify
each for zero-copy re-adoption onto the Rook operator driver (gorons-bracelet.rbd.csi.ceph.com).

Emits a JSON list on stdout; rbd-rook-migration.yml consumes it. This does READ-ONLY kubectl gets.

A volume is ELIGIBLE (skip_reason == "") only in the low-risk cases:
  - bound, ReadWriteOnce, PV driver == rbd.csi.ceph.com, and
  - either UNUSED (bound but no pod mounts it — the safest, no scaling), or
  - mounted by exactly ONE Deployment (scaled down/up around the swap = a brief blip).

StatefulSet volumes are the "sts" tier (migrated as a unit via include_sts, scale-to-0 -> swap ->
scale-up): both volumeClaimTemplate PVCs (matched by name) and standalone PVCs mounted by a running
StatefulSet (matched by the live pod's owner).

Everything else is reported with a skip_reason and left for a deliberate/manual pass:
  RWX/multi-mount, multiple consumers, DaemonSet/Job/bare-pod owners, CNPG (own procedure),
  or a Released/Available PV.
"""
import json
import re
import subprocess
import sys

OLD_DRIVER = "rbd.csi.ceph.com"
PROVISIONER_ID_KEY = "storage.kubernetes.io/csiProvisionerIdentity"


def kget(*args):
    r = subprocess.run(["kubectl", "get", *args, "-o", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(1)
    return json.loads(r.stdout)


def main():
    pvs = kget("pv")["items"]
    pods = kget("pods", "-A")["items"]
    pvcs = {(p["metadata"]["namespace"], p["metadata"]["name"]): p
            for p in kget("pvc", "-A")["items"]}
    rss = {(r["metadata"]["namespace"], r["metadata"]["name"]): r
           for r in kget("rs", "-A")["items"]}

    # StatefulSet volumeClaimTemplate PVC-name matchers, per namespace. STS PVCs are named
    # "<template>-<sts>-<ordinal>" and DON'T carry an ownerRef, so they must be matched by name —
    # a currently-scaled-down STS still owns its PVCs (no pod mounts them = would look "unused").
    sts_patterns = {}
    for s in kget("statefulset", "-A")["items"]:
        ns, name = s["metadata"]["namespace"], s["metadata"]["name"]
        for vct in (s["spec"].get("volumeClaimTemplates") or []):
            pat = re.compile(r"^%s-%s-\d+$" % (re.escape(vct["metadata"]["name"]), re.escape(name)))
            sts_patterns.setdefault(ns, []).append((pat, name))

    def sts_of(ns, pvc):
        for pat, sname in sts_patterns.get(ns, []):
            if pat.match(pvc):
                return sname
        return None

    def cnpg_of(ns, pvc):
        labels = (pvcs.get((ns, pvc), {}).get("metadata", {}) or {}).get("labels", {}) or {}
        return labels.get("cnpg.io/cluster")

    # (namespace, claimName) -> [pods mounting it]
    by_claim = {}
    for p in pods:
        ns = p["metadata"]["namespace"]
        for v in (p["spec"].get("volumes") or []):
            claim = (v.get("persistentVolumeClaim") or {}).get("claimName")
            if claim:
                by_claim.setdefault((ns, claim), []).append(p)

    def owner_of(pod):
        """Resolve a pod to its top controller: (kind, name). Pod->ReplicaSet->Deployment."""
        ns = pod["metadata"]["namespace"]
        for o in (pod["metadata"].get("ownerReferences") or []):
            if o["kind"] == "ReplicaSet":
                rs = rss.get((ns, o["name"]))
                if rs:
                    for oo in (rs["metadata"].get("ownerReferences") or []):
                        if oo["kind"] == "Deployment":
                            return ("Deployment", oo["name"])
                return ("ReplicaSet", o["name"])
            return (o["kind"], o["name"])
        return ("Pod", pod["metadata"]["name"])

    out = []
    for pv in pvs:
        csi = pv["spec"].get("csi") or {}
        if csi.get("driver") != OLD_DRIVER:
            continue
        phase = pv.get("status", {}).get("phase")
        cref = pv["spec"].get("claimRef") or {}
        ns, pvc = cref.get("namespace"), cref.get("name")
        attrs = {k: v for k, v in (csi.get("volumeAttributes") or {}).items()
                 if k != PROVISIONER_ID_KEY}
        rec = {
            "key": ("%s/%s" % (ns, pvc)) if (ns and pvc) else pv["metadata"]["name"],
            "pv": pv["metadata"]["name"],
            "namespace": ns,
            "pvc": pvc,
            "capacity": pv["spec"]["capacity"]["storage"],
            "accessModes": pv["spec"]["accessModes"],
            "reclaimPolicy": pv["spec"]["persistentVolumeReclaimPolicy"],
            "storageClassName": pv["spec"].get("storageClassName", ""),
            "volumeHandle": csi.get("volumeHandle"),
            "volumeAttributes": attrs,
            "fsType": csi.get("fsType", "ext4"),
            "owner_kind": "",
            "owner_name": "",
            "replicas": 0,
            "sts_group": "",           # "ns/sts" for tier == sts (used to migrate a StatefulSet as a unit)
            "skip_reason": "",
            # tier: "auto"  = mounted by one running Deployment, RWO — swept by default (safe blip)
            #       "review"= bound + unused + standalone-looking — migrate only if explicitly named
            #       "skip"  = StatefulSet/CNPG/RWX/orphaned/ordinal — never auto (needs special care)
            "tier": "skip",
        }
        if phase != "Bound" or not ns or not pvc:
            rec["skip_reason"] = "PV not Bound (phase=%s) — orphaned/Released, nothing to migrate" % phase
            out.append(rec)
            continue
        if (ns, pvc) not in pvcs:
            rec["skip_reason"] = "stale claimRef — PVC %s/%s no longer exists (leftover Released PV)" % (ns, pvc)
            out.append(rec)
            continue
        if "ReadWriteMany" in rec["accessModes"]:
            rec["skip_reason"] = "RWX (multi-mount) — migrate manually"
            out.append(rec)
            continue

        # Static, git-defined PV (staticVolume=true): its PV name is pinned in a git PVC's
        # spec.volumeName (immutable). The imperative "-rook" rename this tool does for dynamic
        # volumes drifts the live PVC from that immutable git spec and WEDGES the flux
        # Kustomization. Static volumes must be migrated by editing the git PV's csi.driver in
        # place (same name/volumeHandle) so flux reconciles it — never swept here.
        if rec["volumeAttributes"].get("staticVolume") == "true":
            rec["skip_reason"] = ("static/git-managed PV (staticVolume=true) — migrate by editing the "
                                  "git PV driver in place; the imperative -rook rename breaks flux")
            out.append(rec)
            continue

        # Stateful ownership by identity (name/label), BEFORE consumer inspection — a scaled-down
        # STS or a stopped CNPG pod must never be misread as "unused/eligible".
        cnpg = cnpg_of(ns, pvc)
        sts = sts_of(ns, pvc)
        if cnpg:
            rec["owner_kind"], rec["owner_name"] = "Cluster", cnpg
            rec["skip_reason"] = "CNPG-managed (cluster=%s) — migrate via CNPG, not here" % cnpg
            out.append(rec)
            continue
        if sts:
            rec["owner_kind"], rec["owner_name"] = "StatefulSet", sts
            rec["sts_group"] = "%s/%s" % (ns, sts)
            rec["tier"] = "sts"        # migrated as a group: scale STS to 0 -> swap all its PVCs -> scale up
            out.append(rec)
            continue

        owners = sorted(set(owner_of(p) for p in by_claim.get((ns, pvc), [])))
        if len(owners) > 1:
            rec["skip_reason"] = "multiple consumers %s — migrate manually" % owners
        elif len(owners) == 1 and owners[0][0] == "Deployment":
            rec["owner_kind"], rec["owner_name"] = owners[0]
            dep = kget("deploy", "-n", ns, rec["owner_name"])
            rec["replicas"] = dep["spec"].get("replicas", 1)
            rec["tier"] = "auto"                # live single-Deployment RWO — the unambiguous case
        elif len(owners) == 1 and owners[0][0] == "StatefulSet":
            # Standalone PVC (NOT a volumeClaimTemplate) mounted by exactly one running StatefulSet.
            # Fold it into that STS's group so the sts path migrates it in the SAME scale-to-0 blip
            # as the STS's template PVCs, instead of stranding it. Detected via the live pod's owner,
            # so this fires only while the STS is running; a scaled-down STS's standalone PVC keeps
            # the conservative "unused + ordinal name" skip below.
            rec["owner_kind"], rec["owner_name"] = owners[0]
            rec["sts_group"] = "%s/%s" % (ns, rec["owner_name"])
            rec["tier"] = "sts"                 # migrated with its StatefulSet (needs include_sts)
        elif len(owners) == 1:
            rec["owner_kind"], rec["owner_name"] = owners[0]
            rec["skip_reason"] = "%s-owned — migrate manually" % owners[0][0]
        else:
            # Nothing mounts it. An ordinal-suffixed name is the StatefulSet signature — a
            # scaled-down or not-yet-reconciled STS whose live object we couldn't match. Never sweep.
            rec["owner_kind"] = "None"
            if re.search(r"-\d+$", pvc):
                rec["skip_reason"] = "unused + ordinal name (likely a scaled-down/absent StatefulSet) — verify + use the STS procedure"
            else:
                rec["tier"] = "review"          # bound + unused + standalone-looking — human vets first
        out.append(rec)

    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
