#!/usr/bin/env python3
"""Discover the PVs still on one ceph-csi driver and plan their re-adoption onto another. READ-ONLY.

  ceph-csi-discover.py <repo_dir> <old_driver>=<new_driver> [<old_driver>=<new_driver> ...]

All the driver pairs are planned in one pass, so a workload that mounts volumes on several of the
old drivers (an RBD and a CephFS one) stops once, not once per driver.

Re-adoption is zero-copy: each PV and its PVC are recreated under the SAME names on the new driver
with the same volumeHandle, so the RBD image or CephFS subvolume never moves. ceph-csi-migrate.yml
consumes the JSON list this prints.

A workload can only release a volume by stopping, and volumes shared between workloads (CephFS RWX)
tie those workloads together. So volumes are planned in quiesce groups: the connected sets of
volumes and the Deployments/StatefulSets that mount them, within a namespace. A group is migrated as
a unit: every workload in it scales to 0, every volume is swapped, every workload scales back up.

Tiers (per volume; every volume in a group shares its group's tier):
  group    - Deployments/StatefulSets only, or nothing at all (an orphan is a group of one).
  operator - a workload in the group is owned by an operator CR (Redis, MariaDB, Vault). The operator
             would undo a scale-down, so the group needs that operator's own procedure.
  cnpg     - a CNPG instance volume; rbd-rook-migrate-cnpg.yml reclones it through CNPG.
  manual   - mounted by a bare Pod, a Job or a DaemonSet.
  released - the PV is not Bound, or its PVC no longer exists.

Only Pending/Running pods count as mounting a volume: a finished Job's pod holds no mount.

Flux managers are listed with their whole chain, root first: a HelmRelease is applied by a
Kustomization, and every Kustomization (flux-system's own included) by flux-system. Each level
reverts a kubectl change to the level below on its next reconcile, so suspending a group's workloads
means suspending everything above them, top-down, and resuming bottom-up.
"""
import json
import os
import re
import subprocess
import sys

import yaml

PROVISIONER_ID_KEY = "storage.kubernetes.io/csiProvisionerIdentity"
FLUX_KS = ("kustomize.toolkit.fluxcd.io/name", "kustomize.toolkit.fluxcd.io/namespace")
FLUX_HR = ("helm.toolkit.fluxcd.io/name", "helm.toolkit.fluxcd.io/namespace")
# PVC annotations the binder and provisioner own; everything else on the PVC is carried over.
PVC_ANNOTATION_DROP = re.compile(
    r"^(pv\.kubernetes\.io/|volume\.beta\.kubernetes\.io/|volume\.kubernetes\.io/"
    r"|kubectl\.kubernetes\.io/last-applied-configuration$)")


def kget(*args):
    r = subprocess.run(["kubectl", "get", *args, "-o", "json"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(1)
    return json.loads(r.stdout)["items"]


def managers(obj):
    """The Flux objects that reconcile obj, as 'Kind/namespace/name' (Kustomization, HelmRelease)."""
    lab = obj["metadata"].get("labels") or {}
    out = []
    for kind, (n, ns) in (("Kustomization", FLUX_KS), ("HelmRelease", FLUX_HR)):
        if lab.get(n) and lab.get(ns):
            out.append("%s/%s/%s" % (kind, lab[ns], lab[n]))
    return out


def chain(mgrs, parent_of):
    """mgrs plus every Flux object above them, root first (flux-system, Kustomization, HelmRelease)."""
    depth = {}

    def walk(m, d):
        if depth.get(m, -1) >= d or d > 10:
            return
        depth[m] = d
        p = parent_of.get(m)
        if p and p != m:
            walk(p, d + 1)

    for m in mgrs:
        walk(m, 0)
    return sorted(depth, key=lambda m: (-depth[m], m))


def git_pv_files(repo_dir):
    """PV name -> repo-relative file declaring it (live overlays and bases; never the graveyard)."""
    found = {}
    root = os.path.join(repo_dir, "fluxcd")
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != "zz-graveyard"]
        for f in files:
            if not f.endswith((".yaml", ".yml")) or f.endswith(".enc.yaml"):
                continue
            path = os.path.join(dirpath, f)
            try:
                docs = list(yaml.safe_load_all(open(path)))
            except Exception:
                continue
            for d in docs:
                if isinstance(d, dict) and d.get("kind") == "PersistentVolume":
                    name = (d.get("metadata") or {}).get("name")
                    if name:
                        found.setdefault(name, []).append(os.path.relpath(path, repo_dir))
    return found


def main():
    repo_dir = sys.argv[1]
    pairs = dict(a.split("=", 1) for a in sys.argv[2:])
    pvs = kget("pv")
    pvcs = {(p["metadata"]["namespace"], p["metadata"]["name"]): p for p in kget("pvc", "-A")}
    pods = [p for p in kget("pods", "-A") if p.get("status", {}).get("phase") in ("Pending", "Running")]
    rss = {(r["metadata"]["namespace"], r["metadata"]["name"]): r for r in kget("rs", "-A")}
    deps = {(d["metadata"]["namespace"], d["metadata"]["name"]): d for d in kget("deploy", "-A")}
    stss = {(s["metadata"]["namespace"], s["metadata"]["name"]): s for s in kget("sts", "-A")}
    git_files = git_pv_files(repo_dir)
    parent_of = {}
    for kind, res in (("Kustomization", "kustomizations.kustomize.toolkit.fluxcd.io"),
                      ("HelmRelease", "helmreleases.helm.toolkit.fluxcd.io")):
        for o in kget(res, "-A"):
            up = managers(o)
            if up:
                parent_of["%s/%s/%s" % (kind, o["metadata"]["namespace"], o["metadata"]["name"])] = up[0]

    # StatefulSet PVCs carry no ownerRef and a scaled-down StatefulSet has no pods, so its template
    # PVCs ("<template>-<sts>-<ordinal>") are matched by name: they must never look like orphans.
    sts_patterns = {}
    for (ns, name), s in stss.items():
        for vct in (s["spec"].get("volumeClaimTemplates") or []):
            pat = re.compile(r"^%s-%s-\d+$" % (re.escape(vct["metadata"]["name"]), re.escape(name)))
            sts_patterns.setdefault(ns, []).append((pat, name))

    def owner_of(pod):
        """Top controller of a pod: 'Deployment/x', 'StatefulSet/x', 'Job/x', 'DaemonSet/x', 'Pod/x'."""
        ns = pod["metadata"]["namespace"]
        for o in (pod["metadata"].get("ownerReferences") or []):
            if o["kind"] == "ReplicaSet":
                for oo in (rss.get((ns, o["name"]), {}).get("metadata", {}).get("ownerReferences") or []):
                    if oo["kind"] == "Deployment":
                        return "Deployment/" + oo["name"]
                return "ReplicaSet/" + o["name"]
            return "%s/%s" % (o["kind"], o["name"])
        return "Pod/" + pod["metadata"]["name"]

    by_claim = {}
    for p in pods:
        ns = p["metadata"]["namespace"]
        for v in (p["spec"].get("volumes") or []):
            claim = (v.get("persistentVolumeClaim") or {}).get("claimName")
            if claim:
                by_claim.setdefault((ns, claim), set()).add(owner_of(p))

    def workload(ns, ref):
        kind, name = ref.split("/", 1)
        return (deps if kind == "Deployment" else stss).get((ns, name))

    recs = []
    for pv in pvs:
        csi = pv["spec"].get("csi") or {}
        old_driver = csi.get("driver")
        if old_driver not in pairs:
            continue
        name = pv["metadata"]["name"]
        cref = pv["spec"].get("claimRef") or {}
        ns, claim = cref.get("namespace"), cref.get("name")
        attrs = {k: v for k, v in (csi.get("volumeAttributes") or {}).items() if k != PROVISIONER_ID_KEY}
        pvc = pvcs.get((ns, claim)) if ns and claim else None
        rec = {
            "key": "%s/%s" % (ns, claim) if ns and claim else name,
            "pv": name,
            "namespace": ns,
            "pvc": claim,
            "oldDriver": old_driver,
            "newDriver": pairs[old_driver],
            "type": "cephfs" if ".cephfs." in old_driver else "rbd",
            "capacity": pv["spec"]["capacity"]["storage"],
            "accessModes": pv["spec"]["accessModes"],
            "volumeMode": pv["spec"].get("volumeMode", "Filesystem"),
            "mountOptions": pv["spec"].get("mountOptions") or [],
            "reclaimPolicy": pv["spec"]["persistentVolumeReclaimPolicy"],
            "storageClassName": pv["spec"].get("storageClassName", ""),
            "volumeHandle": csi.get("volumeHandle"),
            "volumeAttributes": attrs,
            "fsType": csi.get("fsType", ""),
            # ref -> secret name; the namespace is swapped to the new driver's on the new PV
            "secretRefs": {k: v["name"] for k, v in csi.items() if k.endswith("SecretRef")},
            "pvLabels": pv["metadata"].get("labels") or {},
            "pvAnnotations": pv["metadata"].get("annotations") or {},
            "static": attrs.get("staticVolume") == "true",
            "gitFile": "",
            "pvManagers": chain(managers(pv), parent_of),
            "pvcManagers": [],
            "pvcRequest": "",
            "pvcStorageClassName": None,
            "pvcLabels": {},
            "pvcAnnotations": {},
            "workloads": [],
            "group": "",
            "operator": "",
            "tier": "",
            "reason": "",
        }
        if rec["static"]:
            files = git_files.get(name, [])
            rec["gitFile"] = files[0] if len(files) == 1 else ""
            if len(files) != 1:
                rec["reason"] = "static PV declared in %d git files %s" % (len(files), files)
        if pv.get("status", {}).get("phase") != "Bound" or pvc is None:
            rec["tier"], rec["reason"] = "released", "PV %s, PVC %s" % (
                pv.get("status", {}).get("phase"), "gone" if ns and claim else "unset")
            recs.append(rec)
            continue
        rec["pvcManagers"] = chain(managers(pvc), parent_of)
        rec["pvcRequest"] = pvc["spec"]["resources"]["requests"]["storage"]
        rec["pvcStorageClassName"] = pvc["spec"].get("storageClassName")
        rec["pvcLabels"] = pvc["metadata"].get("labels") or {}
        rec["pvcAnnotations"] = {k: v for k, v in (pvc["metadata"].get("annotations") or {}).items()
                                 if not PVC_ANNOTATION_DROP.match(k)}
        if rec["pvcLabels"].get("cnpg.io/cluster"):
            rec["tier"], rec["reason"] = "cnpg", "CNPG cluster " + rec["pvcLabels"]["cnpg.io/cluster"]
            recs.append(rec)
            continue
        refs = set(by_claim.get((ns, claim), set()))
        refs |= {"StatefulSet/" + s for pat, s in sts_patterns.get(ns, []) if pat.match(claim)}
        rec["workloads"] = sorted(refs)
        odd = [r for r in refs if r.split("/")[0] not in ("Deployment", "StatefulSet")]
        if odd:
            rec["tier"], rec["reason"] = "manual", "mounted by %s" % ", ".join(sorted(odd))
        recs.append(rec)

    # Quiesce groups: union volumes that share a workload, per namespace.
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    live = [r for r in recs if not r["tier"]]
    for r in live:
        for w in r["workloads"]:
            parent[find("v:" + r["key"])] = find("w:%s/%s" % (r["namespace"], w))
        find("v:" + r["key"])
    groups = {}
    for r in live:
        groups.setdefault(find("v:" + r["key"]), []).append(r)

    for members in groups.values():
        ns = members[0]["namespace"]
        refs = sorted({w for r in members for w in r["workloads"]})
        gkey = "%s/%s" % (ns, "+".join(w.split("/", 1)[1] for w in refs) if refs else members[0]["pvc"])
        info, ops = [], []
        for ref in refs:
            obj = workload(ns, ref)
            if obj is None:
                ops.append("%s (not found)" % ref)
                continue
            ctl = [o for o in (obj["metadata"].get("ownerReferences") or []) if o.get("controller")]
            if ctl:
                ops.append("%s/%s owns %s" % (ctl[0]["kind"], ctl[0]["name"], ref))
            info.append({"ref": ref, "replicas": obj["spec"].get("replicas", 1), "managers": managers(obj)})
        g_mgrs = chain([m for w in info for m in w["managers"]]
                       + [m for r in members for m in r["pvManagers"] + r["pvcManagers"]], parent_of)
        for r in members:
            r["group"] = gkey
            r["workloadInfo"] = info
            r["groupManagers"] = g_mgrs   # root first: suspend in this order, resume in reverse
            if ops:
                r["tier"], r["operator"] = "operator", "; ".join(ops)
            elif r["static"] and not r["gitFile"]:
                r["tier"] = "manual"
            else:
                r["tier"] = "group"
        # One bad member holds the whole group back: its workloads stop together or not at all.
        if any(r["tier"] == "manual" for r in members):
            why = "; ".join(sorted({r["reason"] for r in members if r["reason"]}))
            for r in members:
                r["tier"], r["reason"] = "manual", why

    print(json.dumps(recs, indent=1))


if __name__ == "__main__":
    main()
