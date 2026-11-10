# Ceph Infrastructure Reorganization Plan

## Executive Summary

This document outlines the reorganization of Ceph-related resources in the FluxCD infrastructure to improve clarity, maintainability, and separation of concerns.

**Goal**: Group Ceph resources by technology source (Rook vs Direct CSI vs Custom RGW) while maintaining clear separation between controllers and configs.

---

## Current State Analysis

### Active Ceph Systems

1. **Rook Operator** - Manages CephFS CSI drivers
   - Deployed: ✅ Running in `gorons-bracelet` namespace
   - Purpose: Provides CephFS CSI driver (`gorons-bracelet.cephfs.csi.ceph.com`)
   - Used by: `cephfs-nvme` StorageClass

2. **Direct RBD CSI** - Independent RBD block storage
   - Deployed: ✅ Running via Helm chart
   - Purpose: Provides RBD CSI driver (`rbd.csi.ceph.com`)
   - Used by: `ceph-rbd*` StorageClasses

3. **Rook CephCluster CRD** - External cluster integration
   - Deployed: ✅ CephCluster in external mode
   - Purpose: Represents external Proxmox-managed Ceph cluster
   - Status: Progressing (crash collector issue - non-critical)

4. **Ceph RGW** - S3 Object Storage Gateway
   - Deployed: ✅ Custom StatefulSet
   - Purpose: S3-compatible object storage
   - Used by: GitLab, Harbor

### Problems Identified

1. **Mixed Technology Sources**
   - Rook resources scattered across multiple directories
   - Direct CSI and Rook CSI mixed together
   - Unclear which system manages what

2. **Fragmented CephFS Root Access**
   - Root filesystem access in multiple application namespaces
   - Security risk: Application namespaces can access entire CephFS
   - Per-app root PVCs: `cephfs-root-temp-grafana-pvc`, `cephfs-root-temp-pvc`

3. **Storage Class Confusion**
   - Storage classes split between multiple locations
   - Base "templates" contain production values
   - Unclear which storage class to use

4. **Config vs Controller Misplacement**
   - Jobs in controller overlays instead of configs
   - Storage classes in wrong locations

---

## Target Organization

### Directory Structure

```
fluxcd/infrastructure/
├── controllers/
│   ├── base/
│   │   ├── rook-ceph/                    # Everything from Rook project
│   │   │   ├── operator/                 # Rook operator Helm release
│   │   │   │   ├── helmrelease.yaml
│   │   │   │   ├── helmrepository.yaml
│   │   │   │   └── kustomization.yaml
│   │   │   ├── external-cluster/         # CephCluster CRD for external Ceph
│   │   │   │   ├── cephcluster.yaml
│   │   │   │   └── kustomization.yaml
│   │   │   └── README.md                 # "Manages CephFS CSI via Rook"
│   │   ├── ceph-csi/                     # Direct CSI Helm charts (not via Rook)
│   │   │   ├── helmrelease-rbd.yaml      # RBD CSI Helm release
│   │   │   ├── helmrepository.yaml
│   │   │   ├── kustomization.yaml
│   │   │   └── README.md                 # "Manages RBD CSI independently"
│   │   └── ceph-rgw/                     # Custom RGW deployment
│   │       ├── statefulset.yaml
│   │       ├── service.yaml
│   │       ├── configmap.yaml
│   │       ├── init-job.yaml
│   │       ├── zone-config-template.yaml
│   │       ├── kustomization.yaml
│   │       └── README.md                 # "S3 object storage gateway"
│   └── overlays/production/
│       ├── rook-ceph/
│       │   ├── operator/
│       │   │   ├── helmrelease-patch.yaml
│       │   │   └── kustomization.yaml
│       │   └── external-cluster/
│       │       ├── cephcluster-patch.yaml
│       │       └── kustomization.yaml
│       ├── ceph-csi/
│       │   ├── values-patch.yaml         # RBD CSI production config
│       │   ├── kustomization.yaml
│       │   └── README.md
│       └── ceph-rgw/
│           ├── configmap-patch.yaml
│           ├── statefulset-patch.yaml
│           ├── service-patch.yaml
│           ├── init-job-patch.yaml
│           ├── zone-config-patch.yaml
│           └── kustomization.yaml
├── configs/
│   ├── base/
│   │   └── storage/
│   │       ├── ceph-rbd-delete-storageclass.yaml    # Template with PLACEHOLDER values
│   │       ├── ceph-rbd-retain-storageclass.yaml    # Template with PLACEHOLDER values
│   │       └── README.md                            # "Templates for other environments"
│   └── overlays/production/
│       ├── storage/                          # ALL STORAGE CLASSES
│       │   ├── ceph-rbd.yaml                 # Default, Retain policy
│       │   ├── ceph-rbd-delete.yaml          # Delete policy
│       │   ├── ceph-rbd-retain.yaml          # Retain policy (explicit)
│       │   ├── cephfs-nvme.yaml              # CephFS storage class
│       │   ├── kustomization.yaml
│       │   └── README.md
│       ├── ceph-connection/                  # Shared cluster connection
│       │   ├── cluster-config-kube-system.yaml      # For direct CSI
│       │   ├── cluster-config-gorons-bracelet.yaml  # For Rook
│       │   ├── kustomization.yaml
│       │   └── README.md
│       ├── ceph-rbd/                         # RBD secrets only
│       │   ├── ceph-secret.enc.yaml
│       │   ├── kustomization.yaml
│       │   └── README.md
│       ├── ceph-cephfs/                      # CephFS secrets + volumes
│       │   ├── ceph-cephfs-secret.enc.yaml
│       │   ├── root-access/                  # Admin PVCs for init
│       │   │   ├── cephfs-root-pvc.yaml
│       │   │   ├── cephfs-init-grafana.yaml
│       │   │   ├── cephfs-init-ark-sa.yaml
│       │   │   ├── kustomization.yaml
│       │   │   └── README.md
│       │   ├── static-volumes/               # App-specific static PVs
│       │   │   ├── grafana-plugins-pv.yaml
│       │   │   ├── ark-sa-pvs.yaml
│       │   │   ├── kustomization.yaml
│       │   │   └── README.md
│       │   ├── kustomization.yaml
│       │   └── README.md
│       └── ceph-rgw/                         # RGW secrets + jobs
│           ├── ceph-rgw-keyring.enc.yaml
│           ├── ceph-rgw-gitlab-user.enc.yaml
│           ├── gitlab-s3-setup-job.yaml
│           ├── harbor-credentials-externalsecret.yaml
│           ├── harbor-user-job.yaml
│           ├── kustomization.yaml
│           └── README.md
```

---

## Key Design Decisions

### 1. Technology Source Organization

**Rationale**: Group by where the technology comes from (Rook vs Direct CSI vs Custom)

- `rook-ceph/`: All Rook-related resources (operator + external cluster CRD)
- `ceph-csi/`: Direct CSI Helm charts (independent of Rook)
- `ceph-rgw/`: Custom RADOS Gateway deployment

**Benefits**:
- Clear ownership: "This comes from Rook" vs "This is direct CSI"
- Easy dependency tracking
- README files explain each system's purpose

### 2. Controllers vs Configs Separation

**Controllers** (`infrastructure/controllers/`):
- Deployments, StatefulSets, Services
- Running workloads
- HelmReleases

**Configs** (`infrastructure/configs/`):
- Secrets, ConfigMaps
- StorageClasses
- PersistentVolumes
- Jobs (one-time tasks)

### 3. All Storage Classes in One Location

**Location**: `configs/overlays/production/storage/`

**Rationale**:
- Single source of truth for all storage classes
- Easy to compare RBD vs CephFS options
- Clear visibility of available storage options

### 4. Base Templates with Placeholders

**Base storage classes** contain:
- `clusterID: "PLACEHOLDER_CLUSTER_ID"`
- `pool: "PLACEHOLDER_POOL_NAME"`
- Generic secret names

**Production overlays** contain:
- `clusterID: "0985467c-d8f3-4483-b27f-f0a512397ec2"`
- `pool: "dungeon"`
- Real secret names: `ceph-secret`, `ceph-secret-user`

### 5. Centralized CephFS Root Access

**Security Improvement**: Consolidate root filesystem access to storage namespace

**Before**:
- `cephfs-root-temp-grafana-pvc` in `gossip-stone` namespace
- `cephfs-root-temp-pvc` in `shooting-gallery` namespace
- Risk: Application namespaces have root access

**After**:
- Single `gorons-bracelet-cephfs-root` PVC in `gorons-bracelet` namespace
- Init jobs run in storage namespace
- Application namespaces only get specific subdirectories

---

## Migration Plan

### Phase 1: Move Controller Resources

**Note**: `git mv` automatically creates destination directories - no need to create them manually.

#### Step 1.1: Move Rook operator (base)
```bash
cd /srv/dungeon/fluxcd/infrastructure/controllers/base
git mv rook-ceph-operator/helmrelease.yaml rook-ceph/operator/
git mv rook-ceph-operator/helmrepository.yaml rook-ceph/operator/
git mv rook-ceph-operator/kustomization.yaml rook-ceph/operator/
```

#### Step 1.2: Move Rook external cluster (base)
```bash
git mv rook-ceph-cluster/cephcluster.yaml rook-ceph/external-cluster/
git mv rook-ceph-cluster/kustomization.yaml rook-ceph/external-cluster/
```

#### Step 1.3: Remove old Rook base directories
```bash
rmdir rook-ceph-operator rook-ceph-cluster
```

#### Step 1.4: Move Rook operator (production overlay)
```bash
cd /srv/dungeon/fluxcd/infrastructure/controllers/overlays/production
git mv rook-ceph-operator/helmrelease-patch.yaml rook-ceph/operator/
git mv rook-ceph-operator/kustomization.yaml rook-ceph/operator/
```

#### Step 1.5: Move Rook external cluster (production overlay)
```bash
git mv rook-ceph-cluster/cephcluster-patch.yaml rook-ceph/external-cluster/
git mv rook-ceph-cluster/kustomization.yaml rook-ceph/external-cluster/
```

#### Step 1.6: Remove old Rook production directories
```bash
rmdir rook-ceph-operator rook-ceph-cluster
```

#### Step 1.7: Update kustomization paths in moved files
Files to update:
- `rook-ceph/operator/kustomization.yaml` (base and overlay)
- `rook-ceph/external-cluster/kustomization.yaml` (base and overlay)

---

### Phase 2: Move Config Resources

#### Step 2.1: Rename ceph-csi configs to ceph-rbd
```bash
cd /srv/dungeon/fluxcd/infrastructure/configs/overlays/production
git mv ceph-csi ceph-rbd
```

#### Step 2.2: Rename rook-ceph-external to ceph-connection
```bash
git mv rook-ceph-external ceph-connection
```

#### Step 2.3: Move storage classes to storage/
```bash
# Move from ceph-rbd (formerly ceph-csi)
git mv ceph-rbd/storageclass.yaml storage/ceph-rbd.yaml
git mv ceph-rbd/cephfs-storageclass-nvme.yaml storage/cephfs-nvme.yaml

# Note: ceph-config.yaml stays in ceph-rbd/ (it's not a storage class)
```

#### Step 2.4: Update base storage class templates with placeholders
Edit these files to replace production values with placeholders:
- `configs/base/storage/ceph-rbd-delete-storageclass.yaml`
- `configs/base/storage/ceph-rbd-retain-storageclass.yaml`

Replace:
- `clusterID: 0985467c-d8f3-4483-b27f-f0a512397ec2` → `clusterID: PLACEHOLDER_CLUSTER_ID`
- `pool: dungeon` → `pool: PLACEHOLDER_POOL_NAME`
- Secret names → `PLACEHOLDER_SECRET_NAME`

#### Step 2.5: Move CephFS init jobs to root-access/
```bash
cd /srv/dungeon/fluxcd/infrastructure/controllers/overlays/production
git mv ceph-csi/cephfs-root-pvc.yaml ../../configs/overlays/production/ceph-cephfs/root-access/
git mv ceph-csi/cephfs-init-grafana.yaml ../../configs/overlays/production/ceph-cephfs/root-access/
git mv ceph-csi/cephfs-init-ark-sa.yaml ../../configs/overlays/production/ceph-cephfs/root-access/
```

#### Step 2.6: Move CephFS static volumes
```bash
cd /srv/dungeon/fluxcd/infrastructure/controllers/overlays/production
git mv grafana/cephfs-static-pv.yaml ../../configs/overlays/production/ceph-cephfs/static-volumes/grafana-plugins-pv.yaml

cd /srv/dungeon/fluxcd/apps/overlays/production
git mv ark-sa/cephfs-static-pvs.yaml ../../../infrastructure/configs/overlays/production/ceph-cephfs/static-volumes/ark-sa-pvs.yaml
```

#### Step 2.7: Move RGW jobs from controllers to configs
```bash
cd /srv/dungeon/fluxcd/infrastructure/controllers/overlays/production
git mv ceph-rgw/gitlab-s3-setup-job.yaml ../../configs/overlays/production/ceph-rgw/
git mv ceph-rgw/harbor-credentials-externalsecret.yaml ../../configs/overlays/production/ceph-rgw/
git mv ceph-rgw/harbor-user-job.yaml ../../configs/overlays/production/ceph-rgw/
```

---

### Phase 3: Update Kustomization Files

#### Step 3.1: Update controller base kustomizations

**File**: `controllers/base/rook-ceph/operator/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
```

**File**: `controllers/base/rook-ceph/external-cluster/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cephcluster.yaml
```

#### Step 3.2: Update controller production overlay kustomizations

**File**: `controllers/overlays/production/rook-ceph/operator/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gorons-bracelet
resources:
  - ../../../../base/rook-ceph/operator
patches:
  - path: helmrelease-patch.yaml
```

**File**: `controllers/overlays/production/rook-ceph/external-cluster/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gorons-bracelet
resources:
  - ../../../../base/rook-ceph/external-cluster
patches:
  - path: cephcluster-patch.yaml
```

#### Step 3.3: Update ceph-csi overlay kustomization

**File**: `controllers/overlays/production/ceph-csi/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: flux-system
resources:
  - ../../../base/ceph-csi
patches:
  - path: values-patch.yaml
    target:
      kind: HelmRelease
      name: ceph-csi-rbd
```

#### Step 3.4: Create storage kustomization

**File**: `configs/overlays/production/storage/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kube-system
resources:
  - ceph-rbd.yaml
  - ceph-rbd-delete.yaml
  - ceph-rbd-retain.yaml
  - cephfs-nvme.yaml
```

#### Step 3.5: Update ceph-connection kustomization

**File**: `configs/overlays/production/ceph-connection/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cluster-config-kube-system.yaml
  - cluster-config-gorons-bracelet.yaml
```

**Split existing file**:
- Create `cluster-config-kube-system.yaml` with ceph-csi-config for kube-system namespace
- Create `cluster-config-gorons-bracelet.yaml` with ceph-csi-config for gorons-bracelet namespace

#### Step 3.6: Update ceph-rbd kustomization

**File**: `configs/overlays/production/ceph-rbd/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kube-system
resources:
  - ceph-config.yaml
  - ceph-secret.enc.yaml
```

Note: Remove storage class references (moved to storage/)

#### Step 3.7: Create ceph-cephfs kustomizations

**File**: `configs/overlays/production/ceph-cephfs/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gorons-bracelet
resources:
  - ceph-cephfs-secret.enc.yaml
  - root-access/
  - static-volumes/
```

**File**: `configs/overlays/production/ceph-cephfs/root-access/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gorons-bracelet
resources:
  - cephfs-root-pvc.yaml
  - cephfs-init-grafana.yaml
  - cephfs-init-ark-sa.yaml
```

**File**: `configs/overlays/production/ceph-cephfs/static-volumes/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - grafana-plugins-pv.yaml
  - ark-sa-pvs.yaml
```

#### Step 3.8: Update ceph-rgw kustomization

**File**: `configs/overlays/production/ceph-rgw/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gorons-bracelet
resources:
  - ceph-rgw-keyring.enc.yaml
  - ceph-rgw-gitlab-user.enc.yaml
  - gitlab-s3-setup-job.yaml
  - harbor-credentials-externalsecret.yaml
  - harbor-user-job.yaml
```

#### Step 3.9: Update top-level kustomizations

Update any top-level kustomizations that reference these directories:
- Update paths to rook-ceph resources
- Add new storage/ directory
- Add new ceph-connection/ directory
- Update ceph-cephfs references

---

### Phase 4: Create README Files

#### Step 4.1: Rook Ceph README

**File**: `controllers/base/rook-ceph/README.md`
```markdown
# Rook Ceph Integration

This directory contains Rook operator and external cluster CRD resources for managing CephFS storage.

## Components

- **operator/**: Rook operator Helm release (manages Rook CRDs and CSI drivers)
- **external-cluster/**: CephCluster CRD representing the external Proxmox-managed Ceph cluster

## Purpose

Rook is used to manage **CephFS CSI drivers only**. The RBD CSI is managed independently via direct Helm charts (see `ceph-csi/`).

## CSI Driver Provided

- **CephFS**: `gorons-bracelet.cephfs.csi.ceph.com`
  - Used by: `cephfs-nvme` StorageClass
  - For: ReadWriteMany filesystem storage

## External Cluster Mode

This uses Rook in "external cluster" mode, meaning:
- Ceph cluster is managed by Proxmox (not by Rook)
- Rook only provides CSI drivers to access the external cluster
- No Ceph daemons (mon, osd, mgr) run in Kubernetes
```

#### Step 4.2: Ceph CSI README

**File**: `controllers/base/ceph-csi/README.md`
```markdown
# Ceph CSI (Direct)

This directory contains direct CSI driver Helm charts for RBD block storage, independent of Rook.

## Purpose

Provides RBD CSI driver directly via upstream Helm charts, not managed by Rook.

## CSI Driver Provided

- **RBD**: `rbd.csi.ceph.com`
  - Used by: `ceph-rbd*` StorageClasses
  - For: ReadWriteOnce block storage

## Why Direct CSI?

Historical setup - RBD was deployed via direct CSI before Rook was introduced for CephFS. Both coexist:
- RBD: Direct CSI Helm charts
- CephFS: Rook-managed CSI

Both connect to the same external Proxmox-managed Ceph cluster.
```

#### Step 4.3: Ceph RGW README

**File**: `controllers/base/ceph-rgw/README.md`
```markdown
# Ceph RADOS Gateway (RGW)

Custom StatefulSet deployment of Ceph RADOS Gateway for S3-compatible object storage.

## Purpose

Provides S3 API for:
- GitLab container registry backend
- Harbor registry backend
- General S3 object storage

## Architecture

- StatefulSet with RBD PVCs for local cache/WAL
- Connects to external Ceph cluster via RADOS
- Object data stored in `dungeon-rgw-data` Ceph pool

## Endpoints

- Internal: `http://ceph-rgw.optcp-operators-privileged.svc.cluster.local`
- External LoadBalancer: `172.22.30.101` (shared with storage services)
```

#### Step 4.4: Storage README

**File**: `configs/overlays/production/storage/README.md`
```markdown
# Storage Classes

All Kubernetes StorageClasses for the dungeon cluster.

## RBD Block Storage (ReadWriteOnce)

- **ceph-rbd** (default): Retain policy, ext4 filesystem
- **ceph-rbd-delete**: Delete policy, ext4 filesystem
- **ceph-rbd-retain**: Retain policy (explicit), ext4 filesystem

All RBD storage classes use:
- CSI Driver: `rbd.csi.ceph.com`
- Ceph Pool: `dungeon`
- Image Features: `layering`
- Filesystem: `ext4`
- Mount Options: `discard`

## CephFS Filesystem Storage (ReadWriteMany)

- **cephfs-nvme**: Retain policy, kernel mounter

CephFS storage class uses:
- CSI Driver: `gorons-bracelet.cephfs.csi.ceph.com` (Rook-managed)
- Ceph Filesystem: `Seed_Bank`
- Ceph Pool: `dungeon-fs-nvme`
- Mounter: `kernel`

## Usage

Default storage class: `ceph-rbd`

Choose based on access mode:
- **Single pod access (RWO)**: Use `ceph-rbd*`
- **Multi-pod access (RWX)**: Use `cephfs-nvme`
```

#### Step 4.5: Ceph Connection README

**File**: `configs/overlays/production/ceph-connection/README.md`
```markdown
# Ceph Cluster Connection Configuration

Shared Ceph cluster connection configuration for both direct CSI and Rook CSI drivers.

## Files

- **cluster-config-kube-system.yaml**: ConfigMap for direct RBD CSI (kube-system namespace)
- **cluster-config-gorons-bracelet.yaml**: ConfigMap for Rook CephFS CSI (gorons-bracelet namespace)

## Cluster Details

- **Cluster ID**: `0985467c-d8f3-4483-b27f-f0a512397ec2`
- **Filesystem**: `Seed_Bank`
- **Monitors** (IPv6):
  - `[fc00:f1:ada:104e:1ace::1]:6789`
  - `[fc00:f1:ada:104e:1ace::2]:6789`
  - `[fc00:f1:ada:104e:1ace::3]:6789`
  - `[fc00:f1:ada:104e:1ace::4]:6789`
  - `[fc00:f1:ada:104e:1ace::5]:6789`

## External Cluster

Ceph cluster is managed by Proxmox, not by Kubernetes. These ConfigMaps provide connection details for CSI drivers to access the external cluster.
```

#### Step 4.6: CephFS Root Access README

**File**: `configs/overlays/production/ceph-cephfs/root-access/README.md`
```markdown
# CephFS Root Access for Initialization

Centralized root filesystem access for running initialization jobs.

## Security Model

Root CephFS access is restricted to the `gorons-bracelet` namespace (storage namespace). Application namespaces only receive access to specific subdirectories via static PVs.

## Resources

- **cephfs-root-pvc.yaml**: Single PVC providing root CephFS access (`/`)
- **cephfs-init-grafana.yaml**: Job to create `/dungeon/nvme/apps/grafana/plugins` directory
- **cephfs-init-ark-sa.yaml**: Job to create `/dungeon/nvme/games/ark-sa/*` directories

## Init Job Pattern

1. Job runs in `gorons-bracelet` namespace
2. Mounts `gorons-bracelet-cephfs-root` PVC
3. Creates directory structure with proper ownership
4. TTL cleanup after 300 seconds

## Replacing Old Pattern

**Old** (insecure):
- Per-app root PVCs in application namespaces
- Example: `cephfs-root-temp-grafana-pvc` in `gossip-stone`

**New** (secure):
- Single root PVC in storage namespace
- Init jobs run centrally
- Apps get static PVs to specific paths only
```

#### Step 4.7: CephFS Static Volumes README

**File**: `configs/overlays/production/ceph-cephfs/static-volumes/README.md`
```markdown
# CephFS Static Volumes

Pre-initialized CephFS volumes for specific applications.

## Pattern

1. Run init job from `root-access/` to create directory structure
2. Create static PV pointing to specific CephFS path
3. Application binds to PVC, receives only that subdirectory

## Static Volumes

### Grafana Plugins
- **PV**: `grafana-plugins-pv`
- **PVC**: `gossip-stone-grafana-plugins`
- **Path**: `/dungeon/nvme/apps/grafana/plugins`
- **Size**: 2Gi
- **Ownership**: UID/GID 472 (grafana)

### ARK Survival Ascended
- **Serverfiles PV**: `ark-sa-serverfiles-pv`
- **Serverfiles PVC**: `ark-sa-serverfiles-pvc`
- **Serverfiles Path**: `/dungeon/nvme/games/ark-sa/serverfiles`
- **Serverfiles Size**: 250Gi

- **Cluster PV**: `ark-sa-cluster-pv`
- **Cluster PVC**: `ark-sa-cluster-pvc`
- **Cluster Path**: `/dungeon/nvme/games/ark-sa/cluster`
- **Cluster Size**: 20Gi

- **Ownership**: UID/GID 7777 (pok)

## Benefits

- Application namespaces cannot access CephFS root
- Clear path isolation
- Proper ownership set during initialization
```

---

### Phase 5: Deprecate Old Resources

#### Step 5.1: Remove old per-app root access

**Files to remove**:
- `infrastructure/controllers/overlays/production/grafana/cephfs-init.yaml`
- `apps/overlays/production/ark-sa/cephfs-init.yaml`

**Remove from kustomizations**:
Update Grafana and ARK kustomizations to remove references to old init jobs.

#### Step 5.2: Document deprecated resources

Create `docs/deprecated-ceph-resources.md`:
```markdown
# Deprecated Ceph Resources

## Removed in Reorganization

### Old CephFS Init Jobs (Security Risk)
- `infrastructure/controllers/overlays/production/grafana/cephfs-init.yaml`
- `apps/overlays/production/ark-sa/cephfs-init.yaml`

**Reason**: Created root PVCs in application namespaces, exposing entire filesystem.

**Replaced by**: Centralized init jobs in `configs/overlays/production/ceph-cephfs/root-access/`

### Old Directory Structure
- `controllers/base/rook-ceph-operator/` → `controllers/base/rook-ceph/operator/`
- `controllers/base/rook-ceph-cluster/` → `controllers/base/rook-ceph/external-cluster/`
- `configs/overlays/production/ceph-csi/` → `configs/overlays/production/ceph-rbd/`
- `configs/overlays/production/rook-ceph-external/` → `configs/overlays/production/ceph-connection/`
```

---

### Phase 6: Testing and Validation

#### Step 6.1: Validate kustomize builds
```bash
# Test all base kustomizations
kustomize build fluxcd/infrastructure/controllers/base/rook-ceph/operator
kustomize build fluxcd/infrastructure/controllers/base/rook-ceph/external-cluster
kustomize build fluxcd/infrastructure/controllers/base/ceph-csi
kustomize build fluxcd/infrastructure/controllers/base/ceph-rgw

# Test all production overlays
kustomize build fluxcd/infrastructure/controllers/overlays/production/rook-ceph/operator
kustomize build fluxcd/infrastructure/controllers/overlays/production/rook-ceph/external-cluster
kustomize build fluxcd/infrastructure/controllers/overlays/production/ceph-csi
kustomize build fluxcd/infrastructure/controllers/overlays/production/ceph-rgw

# Test config overlays
kustomize build fluxcd/infrastructure/configs/overlays/production/storage
kustomize build fluxcd/infrastructure/configs/overlays/production/ceph-connection
kustomize build fluxcd/infrastructure/configs/overlays/production/ceph-rbd
kustomize build fluxcd/infrastructure/configs/overlays/production/ceph-cephfs
kustomize build fluxcd/infrastructure/configs/overlays/production/ceph-rgw
```

#### Step 6.2: Verify no broken references
```bash
# Search for old paths that should no longer exist
grep -r "rook-ceph-operator" fluxcd/infrastructure/
grep -r "rook-ceph-cluster" fluxcd/infrastructure/
grep -r "ceph-csi/storageclass" fluxcd/infrastructure/
grep -r "rook-ceph-external" fluxcd/infrastructure/
```

Should return no results if migration is complete.

#### Step 6.3: Check FluxCD reconciliation
```bash
# Force reconcile to pick up new structure
flux reconcile source git flux-system
flux reconcile kustomization infrastructure-controllers
flux reconcile kustomization infrastructure-configs
```

#### Step 6.4: Verify running resources unchanged
```bash
# Check CSI drivers still running
kubectl get pods -n gorons-bracelet | grep -E "ceph|rook"

# Check storage classes still exist
kubectl get storageclass | grep ceph

# Check PVCs still bound
kubectl get pvc -A | grep ceph
```

---

## Rollback Plan

If issues occur during migration:

### Rollback via Git
```bash
# Revert to commit before reorganization
git revert <commit-range>
git push

# Force FluxCD to reconcile
flux reconcile source git flux-system
```

### Manual Rollback Steps

1. Restore old directory structure
2. Move files back to original locations
3. Restore original kustomization.yaml files
4. Reconcile FluxCD

---

## Post-Migration Checklist

- [ ] All kustomize builds succeed
- [ ] No broken path references in repo
- [ ] FluxCD reconciliation successful
- [ ] CSI drivers still running
- [ ] Storage classes still exist
- [ ] Existing PVCs still bound
- [ ] New PVCs can be created with each storage class
- [ ] README files created for all directories
- [ ] Old deprecated resources documented
- [ ] Git history clean (all moves preserved)

---

## Benefits of Reorganization

1. **Clarity**: Clear separation by technology source (Rook vs Direct CSI vs Custom RGW)
2. **Security**: CephFS root access centralized to storage namespace
3. **Maintainability**: Single location for all storage classes
4. **Discoverability**: README files explain each component
5. **Scalability**: Clean structure for adding new Ceph services
6. **Safety**: Base templates prevent accidental production value commits

---

## Component Reference

### Active Ceph Systems After Reorganization

| Component | Type | Location | CSI Driver | Purpose |
|-----------|------|----------|------------|---------|
| Rook Operator | Helm | `controllers/base/rook-ceph/operator/` | `gorons-bracelet.cephfs.csi.ceph.com` | CephFS CSI driver |
| Rook CephCluster | CRD | `controllers/base/rook-ceph/external-cluster/` | N/A | External cluster representation |
| RBD CSI | Helm | `controllers/base/ceph-csi/` | `rbd.csi.ceph.com` | RBD block storage |
| Ceph RGW | StatefulSet | `controllers/base/ceph-rgw/` | N/A | S3 object storage |

### Storage Classes After Reorganization

| Name | Driver | Access Mode | Reclaim Policy | Default |
|------|--------|-------------|----------------|---------|
| ceph-rbd | rbd.csi.ceph.com | RWO | Retain | ✅ Yes |
| ceph-rbd-delete | rbd.csi.ceph.com | RWO | Delete | No |
| ceph-rbd-retain | rbd.csi.ceph.com | RWO | Retain | No |
| cephfs-nvme | gorons-bracelet.cephfs.csi.ceph.com | RWX | Retain | No |

---

## References

- **Ceph Cluster**: Proxmox-managed external cluster
- **Cluster ID**: `0985467c-d8f3-4483-b27f-f0a512397ec2`
- **Ceph Filesystem**: `Seed_Bank`
- **RBD Pool**: `dungeon`
- **CephFS Pool**: `dungeon-fs-nvme`
- **RGW Pools**: `dungeon-rgw`, `dungeon-rgw-data`

---

*Document Version: 1.0*
*Last Updated: 2025-11-06*
