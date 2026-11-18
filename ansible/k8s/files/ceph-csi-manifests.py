#!/usr/bin/env python3
"""Print the PV and PVC that re-adopt one volume onto its new ceph-csi driver (a kubectl List).

  ceph-csi-manifests.py <record.json> <new_secret_namespace> [pvc]

record.json is one ceph-csi-discover.py record. Both objects keep their names (and the PVC its labels, annotations and owner: a CNPG
claim stays its Cluster's), so StatefulSets, git
PVCs (spec.volumeName is immutable) and everything else that names them carry on unchanged. The PV
keeps the volumeHandle and volumeAttributes, which is what makes this zero-copy: the RBD image or
CephFS subvolume is found by them, not by the driver name. Each secret ref keeps its secret's name
and moves to the new driver's namespace (the csi-* secrets exist under the same names in both).

The PV is created first, pre-bound to the claim by its claimRef. The PVC names its volume
(spec.volumeName, pvcNamesVolume) when its original definition did (pvcVolumeNameDeclared: set by
git, a chart or a person, not by the binder), or when Flux doesn't manage the claim at all (a
StatefulSet's or CNPG's), where nothing can contest the field. Where it was declared it must: a claim that names its volume, against a PV
pre-bound to it, is bound without a capacity match, and some static PVs declare less capacity than
their claim requests. Without the name the binder would provision a new, empty volume for such a
claim instead. A claim Flux manages without naming its volume carries no volumeName, and the binder binds it to the PV that names it
and records volumeName under its own field manager, as the original binding did. Set by this script
there, volumeName would belong to the kubectl manager, which Flux claims as its own: Flux would then
try to clear it on a PVC whose git definition doesn't name its volume, and the bound PVC's immutable
spec fails the whole Kustomization. ceph-csi-swap.yml checks that the claim bound to this PV.

`ceph-csi-manifests.py <record.json> <ns> pvc` prints only the PVC: the rollback recreates the old
PV from escrow and the claim from here, so it never carries the binder's annotations (a claim marked
bind-completed with no volumeName is Lost and never binds).

The PV is created Retain; ceph-csi-swap.yml restores the original policy once the claim is bound.
"""
import json
import sys

rec = json.load(open(sys.argv[1]))
secret_ns = sys.argv[2]

ann = dict(rec["pvAnnotations"])
ann.pop("pv.kubernetes.io/bound-by-controller", None)
ann.pop("kubectl.kubernetes.io/last-applied-configuration", None)
if "pv.kubernetes.io/provisioned-by" in ann:
    ann["pv.kubernetes.io/provisioned-by"] = rec["newDriver"]
if "volume.kubernetes.io/provisioner-deletion-secret-namespace" in ann:
    ann["volume.kubernetes.io/provisioner-deletion-secret-namespace"] = secret_ns

csi = {
    "driver": rec["newDriver"],
    "volumeHandle": rec["volumeHandle"],
    "volumeAttributes": rec["volumeAttributes"],
}
if rec["fsType"]:
    csi["fsType"] = rec["fsType"]
for ref, name in rec["secretRefs"].items():
    csi[ref] = {"name": name, "namespace": secret_ns}

pv = {
    "apiVersion": "v1",
    "kind": "PersistentVolume",
    "metadata": {"name": rec["pv"], "labels": rec["pvLabels"], "annotations": ann},
    "spec": {
        "capacity": {"storage": rec["capacity"]},
        "accessModes": rec["accessModes"],
        "volumeMode": rec["volumeMode"],
        "persistentVolumeReclaimPolicy": "Retain",
        "storageClassName": rec["storageClassName"],
        "claimRef": {"apiVersion": "v1", "kind": "PersistentVolumeClaim",
                     "namespace": rec["namespace"], "name": rec["pvc"]},
        "csi": csi,
    },
}

pvc = {
    "apiVersion": "v1",
    "kind": "PersistentVolumeClaim",
    "metadata": {"name": rec["pvc"], "namespace": rec["namespace"],
                 "labels": rec["pvcLabels"], "annotations": rec["pvcAnnotations"]},
    "spec": {
        "accessModes": rec["accessModes"],
        "volumeMode": rec["volumeMode"],
        "resources": {"requests": {"storage": rec["pvcRequest"]}},
    },
}

if rec.get("pvcNamesVolume", rec.get("pvcVolumeNameDeclared")):
    pvc["spec"]["volumeName"] = rec["pv"]
if rec.get("pvcOwnerReferences"):
    pvc["metadata"]["ownerReferences"] = rec["pvcOwnerReferences"]
# The PVC's own class, unset when it was: an unset class would be defaulted at admission.
if rec["pvcStorageClassName"] is not None:
    pvc["spec"]["storageClassName"] = rec["pvcStorageClassName"]
if rec["mountOptions"]:
    pv["spec"]["mountOptions"] = rec["mountOptions"]

if sys.argv[3:] == ["pvc"]:
    json.dump(pvc, sys.stdout)
else:
    json.dump({"apiVersion": "v1", "kind": "List", "items": [pv, pvc]}, sys.stdout)
