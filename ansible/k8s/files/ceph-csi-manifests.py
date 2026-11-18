#!/usr/bin/env python3
"""Print the PV and PVC that re-adopt one volume onto its new ceph-csi driver (a kubectl List).

  ceph-csi-manifests.py <record.json> <new_secret_namespace>

record.json is one ceph-csi-discover.py record. Both objects keep their names, so StatefulSets, git
PVCs (spec.volumeName is immutable) and everything else that names them carry on unchanged. The PV
keeps the volumeHandle and volumeAttributes, which is what makes this zero-copy: the RBD image or
CephFS subvolume is found by them, not by the driver name. Each secret ref keeps its secret's name
and moves to the new driver's namespace (the csi-* secrets exist under the same names in both).

The PVC carries no volumeName. The PV is created first, pre-bound to the claim by its claimRef,
and the binder binds a claim to the PV that names it (every StorageClass here binds Immediate). The
binder then records spec.volumeName under its own field manager, exactly as the original binding
did. Set by this script instead, volumeName would belong to the kubectl manager, which Flux claims
as its own: Flux would then try to clear it on any PVC whose git definition doesn't name its volume,
and the bound PVC's immutable spec fails the whole Kustomization. ceph-csi-swap.yml checks that the
claim bound to this PV.

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

# The PVC's own class, unset when it was: an unset class would be defaulted at admission.
if rec["pvcStorageClassName"] is not None:
    pvc["spec"]["storageClassName"] = rec["pvcStorageClassName"]
if rec["mountOptions"]:
    pv["spec"]["mountOptions"] = rec["mountOptions"]

json.dump({"apiVersion": "v1", "kind": "List", "items": [pv, pvc]}, sys.stdout)
