# Infrastructure Three-Tier Restructure

## Definitions

Based on official Kubernetes definitions:

- **Controller**: Control loop that manages built-in Kubernetes resources (no CRDs)
  - Examples: kube-vip (manages control plane VIP), ceph-csi (CSI driver)

- **Operator**: Custom controller that extends Kubernetes with CRDs + application-specific logic
  - Examples: Strimzi (Kafka operator), CloudNative-PG (PostgreSQL operator)
  - **Key characteristic**: Provides or manages Custom Resource Definitions (CRDs)

- **Service**: Infrastructure-tier applications (not controllers or operators)
  - Examples: Vault, GitLab, Harbor, Grafana, Mimir

## Original Dependency Chain (User)
```
SOPS -> Ceph (RDB/RGW/FS) -> Vault -> Adguard DNS -> Harbor + aptcacherng -> Zitadel -> GitLab -> Monitoring -> Vaultwarden -> Dashboards -> Velero -> SearxNG
```

---

## New Three-Tier Structure

```
infrastructure/
├── controllers/     # K8s controllers (no CRDs)
├── operators/       # Operators (provide CRDs)
└── services/        # Infrastructure applications
    ├── phase-01-storage/
    ├── phase-02-critical/
    ├── phase-03-core/
    └── phase-04-platform/
```

---

## TIER 1: Controllers

**Deploy First** - Core Kubernetes control plane components (no CRDs)

| Controller | Purpose | Must Be First? |
|------------|---------|----------------|
| kube-vip | Control plane HA (VIP management) | No (but early) |
| ceph-csi | Ceph CSI driver for RBD volumes | No |
| cifs-csi | SMB/CIFS CSI driver | No |

**Key Rule**: Controllers manage core K8s resources without extending the API

---

## TIER 2: Operators

**Deploy Second** - All CRD providers and custom controllers

| Operator | Provides CRDs | Purpose |
|----------|---------------|---------|
| cilium | CiliumNetworkPolicy, BGPPeer, etc. | CNI + BGP + LoadBalancer IPAM |
| snapshot-controller | VolumeSnapshot, VolumeSnapshotContent | CSI snapshots |
| gpu-operator | ClusterPolicy | NVIDIA GPU support |
| ceph-rook-ceph/operator | CephCluster, CephObjectStore, etc. | Ceph orchestration |
| external-secrets | ExternalSecret, SecretStore | Secrets from Vault |
| bank-vaults | Vault (CR) | Vault operator |
| cloudnative-pg | Cluster, Backup, etc. | PostgreSQL operator |
| redis-operator | Redis, RedisCluster | Redis operator |
| mariadb-operator-crds | MariaDB (CRDs only) | MariaDB CRDs |
| mariadb-operator | - | MariaDB operator (uses CRDs above) |
| strimzi-kafka-operator | Kafka, KafkaNodePool, KafkaTopic | Kafka operator |
| cert-manager | Certificate, Issuer, ClusterIssuer | TLS certificate management |
| velero | Backup, Restore, Schedule | Backup/DR operator |
| istio | Gateway, VirtualService (Gateway API) | Service mesh + ingress |

**Key Rule**: ALL operators that provide CRDs must deploy before any services that use those CRDs

**Critical Note**: `ceph-rook-ceph/external-cluster/` is NOT deployed here - it creates a CephCluster CR and belongs in services/phase-01

---

## TIER 3: Services

### Phase 01: Storage
**Purpose**: Deploy storage infrastructure before apps need PVCs

| Service | Uses CRDs | Purpose |
|---------|-----------|---------|
| ceph-external-cluster | CephCluster (from rook-ceph operator) | External Ceph cluster connection |
| ceph-rgw | - | Ceph RGW S3 gateway (StatefulSet) |

**Future-proof**: If migrating to internal Ceph, replace external-cluster with internal CephCluster deployment here

---

### Phase 02: Critical Infrastructure
**Purpose**: Core infrastructure that other services depend on

| Service | Uses CRDs | Uses ExternalSecrets? | Purpose |
|---------|-----------|----------------------|---------|
| vault | Vault (from bank-vaults) | No (uses SOPS) | Secrets management |
| adguard | - | No | DNS |
| chrony | - | No | NTP |

**Key Rule**: Infrastructure that doesn't use ExternalSecrets but others depend on

---

### Phase 03: Core Services
**Purpose**: Services that apps depend on (Auth, Git, Container Registries)

| Service | Uses CRDs | Uses ExternalSecrets? | Purpose |
|---------|-----------|----------------------|---------|
| gitlab | Cluster (PostgreSQL), Redis, ExternalSecret | Yes | Git server (hosts FluxCD repo) |
| harbor | Cluster (PostgreSQL), ExternalSecret | Yes | Container registry (cr.optcp.com) |
| zitadel | Cluster (PostgreSQL), ExternalSecret | Yes | Authentication/SSO |
| jfrog-artifactory | Cluster (PostgreSQL), ExternalSecret | Yes | Artifact registry (jcr.pcfae.com) |
| quay | Cluster (PostgreSQL), ExternalSecret | Yes | Container registry |
| apt-cacher-ng | - | No | APT package cache |

**Note**: jfrog, quay, apt-cacher-ng moved from `apps/` to `infrastructure/services/` (infrastructure-tier)

---

### Phase 04: Platform Services
**Purpose**: Observability, monitoring, networking, utilities

| Service | Uses CRDs | Uses ExternalSecrets? | Purpose |
|---------|-----------|----------------------|---------|
| weave-gitops | - | No | GitOps dashboard |
| grafana | Cluster (PostgreSQL), ExternalSecret | Yes | Visualization dashboards |
| mimir | Kafka, KafkaNodePool (from Strimzi) | No | Metrics storage (with Kafka ingest) |
| thanos | - | No | Metrics storage (S3-based) |
| loki | - | No | Log aggregation (S3-based) |
| alloy | - | No | Unified observability collector |
| kube-state-metrics | - | No | K8s object metrics |
| netbird | Cluster (PostgreSQL) | No | VPN |
| stunner | - | No | WebRTC gateway |
| uptime-kuma | - | No | Uptime monitoring |
| ntfy | - | No | Notification service |
| graphite-exporter-truenas | - | No | TrueNAS metrics exporter |
| prometheus-exporter-eaton-ups | - | No | UPS metrics exporter |
| prometheus-exporter-pve | - | No | Proxmox VE metrics exporter |
| wazuh | - | No | SIEM |
| crowdsec | ExternalSecret | Yes | IDS/IPS |
| nutify | ExternalSecret | Yes | UPS monitoring/notifications |
| vaultwarden | Cluster (PostgreSQL), ExternalSecret | Yes | Password manager (moved from apps/) |
| searxng | - | No | Privacy-respecting metasearch (moved from apps/) |

**Note**: vaultwarden, searxng moved from `apps/` to `infrastructure/services/` (infrastructure-tier)

---

## FluxCD Kustomization Deployment Order

```yaml
# 1. Controllers
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-controllers
spec:
  dependsOn:
    - name: namespaces
  path: ./fluxcd/infrastructure/controllers/overlays/production

---
# 2. Operators
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-operators
spec:
  dependsOn:
    - name: infra-controllers
  path: ./fluxcd/infrastructure/operators/overlays/production

---
# 3. Services Phase-01
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-services-phase-01
spec:
  dependsOn:
    - name: infra-operators
  path: ./fluxcd/infrastructure/services/overlays/production/phase-01-storage

---
# 4. Services Phase-02
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-services-phase-02
spec:
  dependsOn:
    - name: infra-services-phase-01
  path: ./fluxcd/infrastructure/services/overlays/production/phase-02-critical

---
# 5. Services Phase-03
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-services-phase-03
spec:
  dependsOn:
    - name: infra-services-phase-02
  path: ./fluxcd/infrastructure/services/overlays/production/phase-03-core

---
# 6. Services Phase-04
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-services-phase-04
spec:
  dependsOn:
    - name: infra-services-phase-03
  path: ./fluxcd/infrastructure/services/overlays/production/phase-04-platform

---
# 7. Configs (secrets, ConfigMaps)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: infra-configs
spec:
  dependsOn:
    - name: infra-services-phase-04
  path: ./fluxcd/infrastructure/configs/overlays/production

---
# 8. Apps (all other applications)
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
spec:
  dependsOn:
    - name: infra-configs
  path: ./fluxcd/apps/overlays/production
```

---

## Deployment Flow Diagram

```
External Ceph Cluster (Proxmox)
    ↓
┌──────────────────────────────────────────┐
│ TIER 1: Controllers                      │
│ - kube-vip, ceph-csi, cifs-csi           │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ TIER 2: Operators (Install CRDs)        │
│ - cilium, snapshot-controller            │
│ - ceph-rook-ceph/operator                │
│ - strimzi-kafka-operator                 │
│ - cloudnative-pg, redis-operator         │
│ - external-secrets, bank-vaults          │
│ - cert-manager, velero, istio            │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ TIER 3 Phase-01: Storage                │
│ - ceph-external-cluster (CephCluster CR) │
│ - ceph-rgw (S3 gateway)                  │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ TIER 3 Phase-02: Critical Infrastructure│
│ - vault (SOPS, no ExternalSecrets)       │
│ - adguard (DNS), chrony (NTP)            │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ TIER 3 Phase-03: Core Services          │
│ - gitlab, harbor, zitadel                │
│ - jfrog, quay, apt-cacher-ng             │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ TIER 3 Phase-04: Platform Services      │
│ - mimir (with Kafka cluster)             │
│ - grafana, loki, alloy, thanos           │
│ - vaultwarden, searxng                   │
│ - wazuh, crowdsec, monitoring tools      │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ Infrastructure Configs                   │
│ - Secrets, ConfigMaps                    │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ Apps                                     │
│ - All other applications                 │
└──────────────────────────────────────────┘
```

---

## Critical Dependencies Verified

✅ **Cilium first**: Networking before anything else (in Operators tier)
✅ **CSI drivers before storage**: ceph-csi deploys before ceph-external-cluster
✅ **Rook operator before CephCluster**: operator (Tier 2) before external-cluster (Phase-01)
✅ **Strimzi before Mimir Kafka**: operator (Tier 2) before mimir/kafka-cluster (Phase-04)
✅ **CloudNative-PG before PostgreSQL users**: operator (Tier 2) before gitlab/grafana/harbor (Phase-03/04)
✅ **ExternalSecrets operator before users**: operator (Tier 2) before apps using ExternalSecret (Phase-02+)
✅ **Vault before ExternalSecrets**: vault (Phase-02) before apps using ExternalSecrets (Phase-03+)
✅ **Storage before apps**: Phase-01 completes before apps requesting PVCs (Phase-02+)

---

## Apps Moved to Infrastructure/Services

The following were moved from `apps/` to `infrastructure/services/phase-03-core/`:
- jfrog-artifactory (container/artifact registry - same tier as Harbor)
- quay (container registry - same tier as Harbor)
- apt-cacher-ng (package cache - infrastructure-tier)

The following were moved from `apps/` to `infrastructure/services/phase-04-platform/`:
- vaultwarden (password manager - uses PostgreSQL + ExternalSecrets)
- searxng (metasearch engine - no CRD deps)

---

## Legacy Components (Graveyard)

The following legacy components have been moved to `overlays/production/zz-graveyard/` for reference:

| Component | Superseded By | Reason | Moved Date |
|-----------|---------------|--------|------------|
| prometheus | Mimir + kube-prometheus-stack | Standalone Prometheus replaced by Grafana Mimir with Kafka-based ingest storage | 2025-11-07 |
| traefik | Istio + Gateway API | Migration to service mesh architecture with Kubernetes Gateway API | 2025-11-07 |
| pihole | AdGuard Home | Better DNS filtering, HTTPS DNS-over-TLS, improved UI/management | 2025-11-07 |

**Note**: These components are NOT deployed by FluxCD. They are preserved for reference only.

---

## Next Steps

1. ✅ Define three-tier structure (Controllers/Operators/Services)
2. ✅ Move legacy components to graveyard
3. ⬜ Create directory structure with git mv (preserve history)
4. ⬜ Create kustomization.yaml for each tier/phase
5. ⬜ Update infrastructure.yaml with new FluxCD kustomizations
6. ⬜ Commit three-tier infrastructure structure
7. ⬜ Test deployment with `flux reconcile`
8. ⬜ Verify Strimzi operator installs Kafka CRDs (Tier 2)
9. ⬜ Verify Mimir + Kafka cluster deploys successfully (Phase-04)
10. ⬜ Test metrics flow: Alloy → Mimir → Kafka
