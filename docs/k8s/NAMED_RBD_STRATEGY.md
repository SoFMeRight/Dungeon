# Named RBD Migration Strategy - Zitadel

## Rationale
- Current: 617MB used out of 20GB (3% usage, wasteful)
- CloudNativePG requires: max_wal_size × 5 = 5GB minimum free
- New size: 12GB (5GB WAL + 1GB data growth + 6GB buffer)

## Step 1: Create Named RBD Images (Proxmox)

SSH to 10.30.1.123:

```bash
rbd create dungeon/zeldas-lullaby-zitadel-postgres-1 --size 12G --image-feature layering
rbd create dungeon/zeldas-lullaby-zitadel-postgres-2 --size 12G --image-feature layering
rbd create dungeon/zeldas-lullaby-zitadel-postgres-3 --size 12G --image-feature layering
```

## Step 2: Copy Data

```bash
rbd copy dungeon/csi-vol-e175d04d-cbec-4fea-a393-f8149157c6f7 dungeon/zeldas-lullaby-zitadel-postgres-1
rbd copy dungeon/csi-vol-1a4ce908-c6a0-45b5-992c-05da02dc80b6 dungeon/zeldas-lullaby-zitadel-postgres-2
rbd copy dungeon/csi-vol-b5002ab6-bb35-486e-83e7-9e61a15f440f dungeon/zeldas-lullaby-zitadel-postgres-3
```

## Step 3: Delete Cluster

```bash
kubectl delete cluster zitadel-postgres -n zeldas-lullaby
kubectl delete statefulset zitadel -n zeldas-lullaby
```

## Step 4: Delete Old PVCs/PVs

```bash
kubectl delete pvc zitadel-postgres-{1,2,3} -n zeldas-lullaby
kubectl delete pv pvc-c8d37e79-9b81-4c02-bb87-3b8d601db65b pvc-71da428c-a1f2-4b14-a71a-f1fb6e69180e pvc-bc2b8c5d-c903-4e00-aedc-a131ea879ff6
```

## Step 5: Apply & Verify

```bash
git add fluxcd/ docs/ && git commit -m "Migrate Zitadel to 12Gi named RBDs" && git push
flux reconcile kustomization infra-services-phase-03
kubectl get pv,pvc,pod -n zeldas-lullaby -w
```
