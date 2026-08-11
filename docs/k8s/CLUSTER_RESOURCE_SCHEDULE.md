# Kubernetes Cluster Resource Schedule
**Cluster:** dungeon (production)
**Generated:** 2025-11-13
**Purpose:** Resource allocation planning and optimization

## Summary Stats
- **Worker Nodes:** 5 (16 cores each = 80 total cores)
- **Current Allocation:** ~76 cores requested (95% utilization)
- **Blocking Issue:** Kafka brokers 3-4 pending (need 3 cores)

---

## Resource Allocation by Namespace

### 🔴 **gossip-stone** (Monitoring & Metrics) - **~11,500m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| **Mimir Kafka** | 5 | 500m-1500m | 2-3Gi | **5,500m** | 13Gi | ⚠️ Brokers 3-4 PENDING @ 1500m each | **CRITICAL: Need 3 CPU freed** |
| Mimir Ingester | 3 | 500m | 2Gi | 1,500m | 6Gi | Metrics storage (necessary) | Keep |
| Mimir Distributor | 9 | 200m | 1Gi | 1,800m | 9Gi | ⚠️ Many evicted pods | Cleanup evicted |
| Mimir Store Gateway | 1 | 200m | 1Gi | 200m | 1Gi | Object storage gateway | Keep |
| Mimir Compactor | 1 | 200m | 1Gi | 200m | 1Gi | Data compaction | Keep |
| Mimir Querier | 2 | 200m | 512Mi | 400m | 1Gi | Query execution | Keep |
| Mimir Query Frontend | 2 | 200m | 512Mi | 400m | 1Gi | Query interface | Keep |
| Mimir Query Scheduler | 2 | 100m | 128Mi | 200m | 256Mi | Query scheduling | Keep |
| Mimir Alertmanager | 1 | 10m | 32Mi | 10m | 32Mi | Alerting | Keep |
| Mimir Overrides Exporter | 1 | 100m | 128Mi | 100m | 128Mi | Config exports | Keep |
| Mimir Rollout Operator | 1 | 100m | 100Mi | 100m | 100Mi | K8s operator | Keep |
| Kafka Entity Operator | 1 | 100m | 256Mi | 100m | 256Mi | Kafka operator | Keep |
| Kafka Exporter | 1 | 100m | 128Mi | 100m | 128Mi | Kafka metrics | Keep |
| Grafana | 1 | 100m | 256Mi | 100m | 256Mi | Visualization | Keep |
| Kube-State-Metrics | 1 | 10m | 64Mi | 10m | 64Mi | K8s metrics | Keep |
| NetAlertX | 1 | 100m | 256Mi | 100m | 256Mi | Network monitoring | Keep |
| Beszel | 1 | 50m | 128Mi | 50m | 128Mi | Server monitoring | Keep |
| Graphite Exporter | 1 | 50m | 64Mi | 50m | 64Mi | TrueNAS metrics | Keep |
| Prometheus Exporters | 2 | 50m | 64Mi | 100m | 128Mi | UPS + PVE metrics | Keep |

---

### 🟡 **hyrule-castle** (Business Applications) - **~7,500m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| **GitLab** | - | - | - | **3,900m** | **14Gi** | CI/CD platform (KEEP) | **User wants to keep** |
| ├─ Webservice | 3 | 500m | 2Gi | 1,500m | 6Gi | Web UI & API | Keep (CI platform) |
| ├─ Sidekiq | 3 | 300m | 1Gi | 900m | 3Gi | Background jobs | Keep (CI platform) |
| └─ PostgreSQL | 3 | 500m | 1Gi | 1,500m | 3Gi | Database (HA) | Keep (CI platform) |
| **ERPNext** | - | - | - | **1,000m** | **3Gi** | ERP system | 🎯 Reduce to 600m |
| ├─ Sites | 1 | 500m | 2Gi | 500m | 2Gi | App server | → 250m |
| └─ MariaDB | 1 | 500m | 1Gi | 500m | 1Gi | Database | Keep |
| **InvoiceNinja** | - | - | - | **1,000m** | **3Gi** | Invoicing | 🎯 Reduce to 600m |
| ├─ App | 1 | 500m | 2Gi | 500m | 2Gi | App server | → 250m |
| └─ MySQL | 1 | 500m | 1Gi | 500m | 1Gi | Database | Keep |
| **OrangeHRM** | 1 | 500m | 2Gi | **500m** | 2Gi | HR management | 🎯 → 250m |
| **JFrog Artifactory** | - | - | - | **750m** | **3Gi** | Container registry | Keep (critical) |
| ├─ Artifactory | 1 | 250m | 2Gi | 250m | 2Gi | Artifact server | Keep |
| └─ PostgreSQL | 1 | 500m | 1Gi | 500m | 1Gi | Database | Keep |
| Apt-Cacher-NG | 1 | 500m | 1Gi | 500m | 1Gi | Package cache | Keep |

**Potential Savings: 750m (ERPNext 250m + InvoiceNinja 250m + OrangeHRM 250m)**

---

### 🟢 **temple-of-time** (Personal Productivity & Content) - **~4,000m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| **Open-WebUI** | 3 | 500m | 2Gi | **1,500m** | 6Gi | AI chat interface | 🎯 **Reduce to 250m per pod** |
| **AppFlowy Cloud** | - | - | - | **1,000m** | **3Gi** | Productivity suite | 🎯 **Reduce to 300m** |
| ├─ AppFlowy | 1 | 500m | 2Gi | 500m | 2Gi | App server | → 200m |
| └─ Minio | 1 | 500m | 1Gi | 500m | 1Gi | Object storage | → 100m |
| **Linkwarden** | - | - | - | **300m** | **768Mi** | Bookmark manager | Keep (personal) |
| ├─ App | 1 | 200m | 512Mi | 200m | 512Mi | Web app | Keep |
| └─ Meilisearch | 1 | 100m | 256Mi | 100m | 256Mi | Search engine | Keep |
| Mealie | 1 | 200m | 512Mi | 200m | 512Mi | Recipe manager | Keep |
| Jellyfin | 1 | 200m | 1Gi | 200m | 1Gi | Media server | Keep |
| Calibre-Web | 1 | 100m | 256Mi | 100m | 256Mi | Ebook library | Keep |
| Audiobookshelf | 1 | 100m | 256Mi | 100m | 256Mi | Audiobook server | Keep |
| Paperless-NGX | - | - | - | 700m | 2Gi | Document management | Keep |

**Potential Savings: 1,450m (Open-WebUI 750m per-pod reduction + AppFlowy 700m per-pod reduction)**

---

### 🔵 **lens-of-truth** (Security & SIEM) - **~2,500m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| Wazuh Manager | 1 | 500m | 2Gi | 500m | 2Gi | SIEM manager | Keep (security) |
| Wazuh Indexer | 1 | 500m | 2Gi | 500m | 2Gi | Log indexer | Keep (security) |
| Wazuh Dashboard | 1 | 200m | 1Gi | 200m | 1Gi | SIEM dashboard | Keep |
| CrowdSec LAPI | 3 | 200m | 512Mi | 600m | 1.5Gi | Threat detection | Keep (security) |
| CrowdSec Dashboard | 1 | 200m | 512Mi | 200m | 512Mi | CrowdSec UI | Keep |
| Anubis | 1 | 100m | 256Mi | 100m | 256Mi | Bot protection | Keep |
| Wallabag | 1 | 100m | 256Mi | 100m | 256Mi | Read-it-later | Keep |

---

### 🟣 **zeldas-lullaby** (Administration) - **~2,000m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| Vault | 3 | 250m | 512Mi | 750m | 1.5Gi | Secrets management | Keep (critical) |
| Zitadel | 3 | 200m | 512Mi | 600m | 1.5Gi | Identity provider | Keep (critical) |
| Zitadel PostgreSQL | 3 | 250m | 1Gi | 750m | 3Gi | Database (HA) | Keep (critical) |
| External Secrets | - | - | - | 300m | 512Mi | K8s operator | Keep |
| NetBox | - | - | - | 750m | 2Gi | IPAM/DCIM | Keep |
| ├─ Server | 1 | 500m | 1Gi | 500m | 1Gi | App server | Keep |
| └─ PostgreSQL | 1 | 250m | 1Gi | 250m | 1Gi | Database | Keep |
| Weave GitOps | 1 | 100m | 256Mi | 100m | 256Mi | FluxCD UI | Keep |

---

### 🟠 **lost-woods** (Discovery & Dashboards) - **~1,500m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| **Homarr** | - | - | - | **450m** | **832Mi** | Dashboard | Keep (HA setup) |
| ├─ App | 3 | 100m | 256Mi | 300m | 768Mi | Dashboard app (HA) | Keep |
| └─ Sentinel | 3 | 50m | 64Mi | 150m | 192Mi | Redis sentinel | Keep |
| Homepage | 3 | 100m | 256Mi | 300m | 768Mi | Dashboard | Keep (HA) |
| Zipline | 1 | 200m | 512Mi | 200m | 512Mi | File sharing | Keep |
| Stirling-PDF | 1 | 200m | 512Mi | 200m | 512Mi | PDF tools | Keep |

---

### 🔶 **shooting-gallery** (Game Servers) - **~1,000m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| **Pelican Panel** | 1 | 500m | 2Gi | **500m** | 2Gi | Game server manager | 🎯 → 250m |
| Minecraft Servers | Various | 100-250m | 512Mi-2Gi | ~500m | ~4Gi | Game servers | Keep as-is |

**Potential Savings: 250m (Pelican Panel)**

---

### 🟤 **gorons-bracelet** (Storage Infrastructure) - **~3,000m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-----------|-------|--------------|
| Ceph RBD CSI | 2+5 | 250m | 512Mi | 1,750m | 3.5Gi | Block storage driver | Keep (critical) |
| Ceph CephFS CSI | 2+5 | 250m | 512Mi | 1,750m | 3.5Gi | File storage driver | Keep (critical) |
| Ceph RGW | 2 | 250m | 512Mi | 500m | 1Gi | S3 gateway | Keep |
| SMB CSI | 2+10 | 10m | 20Mi | 120m | 240Mi | SMB storage driver | Keep |
| Redis Operator | 1 | 500m | 500Mi | 500m | 500Mi | Redis management | Keep |
| Rook-Ceph Operator | 1 | 100m | 128Mi | 100m | 128Mi | Ceph operator | Keep |
| Strimzi Operator | 2 | 200m | 512Mi | 400m | 1Gi | Kafka operator | Keep |
| GPU Operator | Various | 5-200m | 64-128Mi | ~500m | ~1Gi | NVIDIA GPU support | Keep |

---

### 🟢 **tingle-tuner** (Utilities & Tools) - **~800m CPU**

| Application | Replicas | CPU/pod | Mem/pod | Total CPU | Total Mem | Notes | Optimization |
|------------|----------|---------|---------|-----------|-------|--------------|
| IT-Tools | 3 | 100m | 128Mi | 300m | 384Mi | Dev tools | Already minimal |
| Neko Gateway | 1 | 500m | 2Gi | 500m | 2Gi | Browser isolation | Keep |
| Podinfo | 1 | 1m | 16Mi | 1m | 16Mi | Demo/testing | Minimal |

---

### ⚪ **Other Namespaces** - **~4,000m CPU**

| Namespace | Applications | Total CPU | Notes |
|-----------|-------------|-----------|-------|
| **compass** | AdGuard (2), DNS/NTP, Speed Tests | ~800m | Keep (networking) |
| **delivery-bag** | Ntfy, Mailcow | ~500m | Keep (mail/notifications) |
| **fairy-bottle** | Velero, Node Agents | ~600m | Keep (backups) |
| **flux-system** | Flux Controllers | ~350m | Keep (GitOps) |
| **arylls-lookout** | Xylem Gateway (Istio) | ~300m | Keep (internal gateway) |
| **kokiri-forest** | Phloem Gateway, Linkstack | ~400m | Keep (public gateway) |
| **king-of-red-lions** | Traefik, Istio | ~500m | Keep (routing) |
| **pedestal-of-time** | Paperless, Restricted Apps | ~500m | Keep (restricted) |

---

## 🎯 **IMMEDIATE ACTION PLAN TO FREE 3 CPU CORES**

### Phase 1: Personal Apps - Per-Pod CPU Optimization (750m freed)
1. **Open-WebUI**: 1,500m → 750m (-750m)
   - Keep 3 replicas (HA maintained)
   - Reduce CPU request per pod: 500m → 250m
2. **AppFlowy Cloud**: 1,000m → 300m (-700m)
   - AppFlowy: 500m → 200m per pod
   - Minio: 500m → 100m per pod

### Phase 2: Business Apps - Per-Pod CPU Optimization (750m freed)
3. **ERPNext Sites**: 500m → 250m (-250m)
   - App server CPU request reduction
4. **InvoiceNinja App**: 500m → 250m (-250m)
   - App server CPU request reduction
5. **OrangeHRM**: 500m → 250m (-250m)
   - App server CPU request reduction

### Phase 3: Game Server Manager - Per-Pod CPU Optimization (250m freed)
6. **Pelican Panel**: 500m → 250m (-250m)
   - Game server manager CPU request reduction

**TOTAL AVAILABLE: 1,750m (1.75 cores) from per-pod optimization WITHOUT reducing replica counts**

**NOTE:** Additional optimizations can be considered on a per-application basis if more CPU is needed. All recommendations maintain current replica counts and HA configurations.

---

## Notes for Future Optimization

1. **GitLab** (3.9 cores): User wants to keep as-is (CI platform)
2. **Security tools** (Wazuh, CrowdSec): Keep untouched (critical)
3. **Infrastructure** (Vault, Zitadel, Ceph): Keep untouched (critical)
4. **Replica counts**: Maintained for HA - user switched from Docker to K8s for BETTER availability
5. **Per-pod optimization**: Focus on reducing CPU/memory requests per pod, not replica counts

## How to Use This Document

1. **Planning**: Review before deploying new apps
2. **Optimization**: Identify over-provisioned apps
3. **Troubleshooting**: When pods can't schedule (like Kafka brokers 3-4)
4. **Capacity Planning**: Track total resource usage vs cluster capacity

---

**Last Updated:** 2025-11-13
**Next Review:** When adding/removing major applications
