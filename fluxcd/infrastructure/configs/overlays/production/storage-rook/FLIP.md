# RBD → Rook operator driver: staged migration (ready to flip)

This directory holds the operator-driver (`gorons-bracelet.rbd.csi.ceph.com`) versions of the six
`ceph-rbd*` StorageClasses + the RBD VolumeSnapshotClass. It is **not referenced by any active
kustomization**, so Flux does not reconcile it — staging has **zero live effect**.

Both drivers are the same ceph-csi RBD binary against the same external ceph (clusterID
`0985467c…`, pools `dungeon`/`dungeon_hdd`); the operator driver already has its credentials
(`csi-rbd-provisioner` / `csi-rbd-node` in `gorons-bracelet`). Provisioning + mount + write were
validated end-to-end on this driver before staging.

## Safety — existing volumes are NOT touched
A bound PV pins its driver in its own spec (`spec.csi.driver: rbd.csi.ceph.com`). A StorageClass
is read **only when a new PVC provisions**. So flipping the classes affects only **new** volumes;
all existing RBD PVs keep running on the old Helm driver, which stays installed. (At last check:
361 Retain + 2 Delete on `rbd.csi.ceph.com`.) Deleting a StorageClass object does not disturb any
bound PVC/PV — only a new PVC created during the brief recreate gap would pend.

## The flip (do all steps together)
1. Note the baseline (these stay on the old driver, untouched):
   ```
   kubectl get pv -o json | jq '[.items[]|select(.spec.csi.driver=="rbd.csi.ceph.com")]|length'
   ```
2. Delete the old-driver objects — their `provisioner`/`driver` is immutable, so they must be
   recreated, not edited (safe; see above):
   ```
   kubectl delete storageclass ceph-rbd ceph-rbd-hdd ceph-rbd-templated \
       ceph-rbd-delete ceph-rbd-retain ceph-rbd-static
   kubectl delete volumesnapshotclass csi-rbdplugin-snapclass
   ```
3. Point GitOps at this directory instead of the old-driver files:
   - `../storage/kustomization.yaml`: replace the RBD resources
     (`../../../base/storage`, `ceph-rbd.yaml`, `ceph-rbd-hdd.yaml`, `ceph-rbd-templated.yaml`)
     with `../storage-rook`. Leave `cephfs-nvme.yaml` / `cephfs-hdd.yaml`.
   - `../volume-snapshot-class/`: drop its `csi-rbdplugin-snapclass` resource (storage-rook now
     provides it).
   Commit + push.
4. Reconcile → recreates the six classes + snapclass on the operator driver:
   ```
   flux reconcile kustomization infra-configs --with-source
   kubectl get sc | grep ceph-rbd        # provisioner should read gorons-bracelet.rbd.csi.ceph.com
   ```
5. Validate: create a 1Gi PVC on `ceph-rbd` → binds on the operator driver (proven pattern).

## Rollback
Revert the step-3 commit, `kubectl delete` the operator-driver classes, `flux reconcile` — Flux
recreates the old-driver classes. Existing volumes were never affected either way.

## After the flip (a separate, later cleanup — NOT part of this)
The old `ceph-csi-rbd` HelmRelease keeps serving all existing RBD PVs and MUST stay installed until
they have all migrated (which happens only as their PVCs are recreated — gradually, or never).
Retire it only when the step-1 count reaches 0.
