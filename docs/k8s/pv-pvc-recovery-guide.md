# PersistentVolume Recovery and PVC Binding Guide

## Overview

This guide documents methods for recovering data from released PersistentVolumes and binding them to new PersistentVolumeClaims, particularly useful when migrating from Deployments to StatefulSets.

## Understanding PV States and Reclaim Policies

### PV States
- **Available**: PV is free and can be bound to a new PVC
- **Bound**: PV is bound to a PVC and in use
- **Released**: PVC was deleted but PV still contains data (if Retain policy)
- **Failed**: PV has failed and needs manual intervention

### Reclaim Policies
- **Retain**: Data survives PVC deletion - **recoverable**
- **Delete**: Data is wiped when PVC is deleted - **not recoverable**
- **Recycle**: Data is scrubbed but PV is reused - **not recoverable**

## Method 1: Direct PV Binding to StatefulSet PVC

This method binds an existing PV directly to a StatefulSet PVC by name.

### Prerequisites
- Released PV with Retain policy
- StatefulSet that creates PVCs with predictable names

### Steps

1. **Scale down the StatefulSet**:
   ```bash
   kubectl scale statefulset <name> -n <namespace> --replicas=0
   ```

2. **Find released PVs**:
   ```bash
   kubectl get pv | grep Released
   ```

3. **Clear the claim reference**:
   ```bash
   kubectl patch pv <pv-name> -p '{"spec":{"claimRef":null}}'
   ```

4. **Verify PV is Available**:
   ```bash
   kubectl get pv <pv-name>
   # Should show STATUS: Available
   ```

5. **Patch PV to bind to StatefulSet PVC**:
   ```bash
   kubectl patch pv <pv-name> --type merge -p '{
     "spec": {
       "claimRef": {
         "name": "<statefulset-pvc-name>",
         "namespace": "<namespace>",
         "uid": "",
         "resourceVersion": ""
       }
     }
   }'
   ```

6. **Scale up StatefulSet**:
   ```bash
   kubectl scale statefulset <name> -n <namespace> --replicas=1
   ```

### Example
```bash
# Scale down Plex
kubectl scale statefulset plex -n operationtimecapsule --replicas=0

# Clear claim reference
kubectl patch pv pvc-ba846bda-91df-4194-8c4a-649e3a538a9f -p '{"spec":{"claimRef":null}}'

# Bind to StatefulSet PVC
kubectl patch pv pvc-ba846bda-91df-4194-8c4a-649e3a538a9f --type merge -p '{
  "spec": {
    "claimRef": {
      "name": "config-plex-0",
      "namespace": "operationtimecapsule",
      "uid": "",
      "resourceVersion": ""
    }
  }
}'

# Scale up
kubectl scale statefulset plex -n operationtimecapsule --replicas=1
```

## Method 2: Data Migration Between PVs

When PV binding isn't possible, migrate data from old PV to new PVC.

### Steps

1. **Create recovery PVC for old PV**:
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: data-recovery
     namespace: <namespace>
   spec:
     accessModes:
       - ReadWriteOnce
     storageClassName: ""
     volumeName: <old-pv-name>
     resources:
       requests:
         storage: <size>
   ```

2. **Create migration job**:
   ```yaml
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: data-migration
     namespace: <namespace>
   spec:
     template:
       spec:
         restartPolicy: Never
         containers:
         - name: migrate
           image: docker.io/library/alpine:latest
           command:
           - sh
           - -c
           - |
             echo "Starting migration..."
             cp -av /old-data/* /new-data/
             echo "Migration complete!"
           volumeMounts:
           - name: old-data
             mountPath: /old-data
           - name: new-data
             mountPath: /new-data
         volumes:
         - name: old-data
           persistentVolumeClaim:
             claimName: data-recovery
         - name: new-data
           persistentVolumeClaim:
             claimName: <new-pvc-name>
   ```

## Troubleshooting Storage Class Issues

### CSI Secret Namespace Mismatch

**Problem**: PV has hardcoded CSI secret references to wrong namespace

**Error**: `fetching NodeStageSecretRef namespace/secret failed: secrets "secret" not found`

#### Solution 1: Copy Secrets (Temporary)
```bash
# Copy secrets to required namespace
kubectl get secrets -n kube-system ceph-secret ceph-secret-user -o yaml | \
  sed 's/namespace: kube-system/namespace: <target-namespace>/' | \
  kubectl apply -f -
```

#### Solution 2: Patch PV (Only when detached)
**Note**: CSI fields are immutable when PV is bound!

```bash
# Only works when PV is Available/Released
kubectl patch pv <pv-name> --type merge -p '{
  "spec": {
    "csi": {
      "controllerExpandSecretRef": {"namespace": "kube-system"},
      "nodeStageSecretRef": {"namespace": "kube-system"}
    }
  }
}'
```

### StorageClass Parameter Updates

**Problem**: StorageClass parameters are immutable

**Solution**: Delete and recreate
```bash
# Delete old storage class
kubectl delete storageclass <name>

# Let FluxCD recreate with new parameters
flux reconcile kustomization infra-configs
```

## StatefulSet Conversion Best Practices

### 1. Delete Existing StatefulSet First
When adding volumeClaimTemplates to existing StatefulSet:
```bash
# StatefulSet spec is immutable for volumeClaimTemplates
kubectl delete statefulset <name> -n <namespace>
# Let FluxCD recreate with new spec
```

### 2. Use Proper Storage Classes
- **Production**: `ceph-rbd-retain` (Retain policy)
- **Development**: `ceph-rbd-delete` (Delete policy)
- **Shared storage**: Static PVs with specific names

### 3. Namespace Management
Ensure Ceph secrets exist in correct namespaces:
```bash
# Check where secrets are located
kubectl get secrets --all-namespaces | grep ceph

# Copy to required namespaces if needed
```

## Recovery Checklist

- [ ] Identify PV reclaim policy (only Retain is recoverable)
- [ ] Scale down consuming pods/StatefulSets
- [ ] Clear PV claim references
- [ ] Check for storage class/CSI namespace issues
- [ ] Copy secrets to required namespaces if needed
- [ ] Bind PV to new PVC or migrate data
- [ ] Scale up services
- [ ] Verify data integrity
- [ ] Clean up temporary resources

## Common Pitfalls

1. **Delete Reclaim Policy**: Data is lost when PVC is deleted
2. **Immutable CSI References**: Can't change namespace refs when PV is bound
3. **StatefulSet Spec**: Can't modify volumeClaimTemplates on existing StatefulSet
4. **Storage Class Updates**: Parameters are immutable, must delete/recreate
5. **Timing Issues**: Allow time for PV/PVC binding and mounting

## Prevention

- Use `ceph-rbd-retain` storage class for all persistent data
- Implement StatefulSets from the start for stateful services
- Regular backups of critical data
- Document PV/PVC relationships
- Monitor reclaim policies in storage classes
