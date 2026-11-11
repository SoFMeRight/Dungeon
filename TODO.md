# TODO

## Container Security Audit

See [docs/container-security-audit.md](docs/container-security-audit.md) for the complete security posture audit of all containerized workloads.

## CRITICAL: Velero Backup Failure - Nov 6-11, 2025

**Issue:** Velero was misconfigured with `defaultVolumesToFsBackup: false`, causing catastrophic data loss during Ceph migration.

**Impact:**
- All backups from Oct 12 - Nov 10 were **unusable**
- Backups only stored Kubernetes resource metadata + CSI snapshot references in MinIO
- Actual volume data remained in Ceph CSI snapshots (not in MinIO)
- During Nov 7-8 infrastructure refactor, Ceph RBD images were deleted
- This destroyed all CSI snapshots, making backups unrestorable
- **Permanent data loss:**
  - Grafana dashboards, panels, datasources (since Nov 4)
  - plex-ms-x libraries and configuration
  - Any other applications relying on Nov 6-10 backups

**Root Cause:**
- Velero defaults to CSI snapshots when `defaultVolumesToFsBackup` is not set
- CSI snapshots are stored in the same storage backend being backed up (Ceph)
- This creates a dependency on the infrastructure being protected
- Backups were not truly independent or disaster-proof

**Fix Applied (Nov 11, 2025):**
- Set `defaultVolumesToFsBackup: true` in daily backup schedule
- File-level backups now use node-agent (restic/kopia) to copy data to MinIO
- Backups are now independent of Ceph storage backend
- Can survive complete storage infrastructure failure
- Change: commit 581354f8 "Fix critical Velero backup misconfiguration"

**Verification:**
- ✅ node-agent DaemonSet running (5/5 pods)
- ✅ Backup schedule updated with `defaultVolumesToFsBackup: true`
- ✅ Velero deployment restarted to apply changes
- ⏳ Next automatic backup: 2:00 AM (will use file-level backup to MinIO)

**Lessons Learned:**
- Always verify backup restoration works **before** depending on backups
- CSI snapshots are not true backups - they're storage-level features
- Backup systems must be independent of the infrastructure they protect
- Test restore procedures regularly

**Action Items:**
- [ ] Monitor Nov 12 2am backup to confirm file-level backup works
- [ ] Verify backup data appears in MinIO with actual volume files
- [ ] Document backup verification/restore testing procedures
- [ ] Consider implementing automated backup restore tests

## PVC Naming Standard Alignment

CLAUDE.md specifies PVC naming pattern for StatefulSets: `<namespace>-<app>-<purpose>-<app>-<ordinal>`
(Note: Due to StatefulSet behavior, app name appears twice: once in volumeClaimTemplate name, once from StatefulSet name)

**Completed migrations:**
- ✅ Plex: `temple-of-time-plex-config-plex-0`, `temple-of-time-plex-transcode-plex-0`
- ✅ Jellyfin: `temple-of-time-jellyfin-config-jellyfin-0`, `temple-of-time-jellyfin-cache-jellyfin-0`
- ✅ Linkwarden: `temple-of-time-linkwarden-data-linkwarden-0`, `temple-of-time-linkwarden-postgres-linkwarden-postgres-0`, `temple-of-time-linkwarden-meilisearch-linkwarden-meilisearch-0`
- ✅ Mealie: `temple-of-time-mealie-data-mealie-0`, `temple-of-time-mealie-postgres-mealie-postgres-0`

**Remaining non-compliant StatefulSet PVCs:**

### temple-of-time namespace:
- [ ] PhotoPrism MariaDB: `database-photoprism-mariadb-0` → `temple-of-time-photoprism-mariadb-database-mariadb-0`
- [ ] PhotoPrism: `storage-photoprism-0` → `temple-of-time-photoprism-storage-photoprism-0`
- [ ] Immich (old PVCs - need cleanup): `library-immich-0`, `model-cache-immich-0`, `postgres-immich-0`

### compass namespace:
- [ ] AdGuard: `adguard-conf-adguard-0` → `compass-adguard-conf-adguard-0`
- [ ] AdGuard: `adguard-data-adguard-0` → `compass-adguard-data-adguard-0`

### optcp-operators-privileged namespace:
- [ ] Ceph RGW: `rgw-data-ceph-rgw-0` → `optcp-operators-privileged-ceph-rgw-data-ceph-rgw-0`
- [ ] Ceph RGW: `rgw-data-ceph-rgw-1` → `optcp-operators-privileged-ceph-rgw-data-ceph-rgw-1`

### shooting-gallery namespace:
- [ ] Minecraft: `data-minecraft-0` → `shooting-gallery-minecraft-data-minecraft-0`

### lens-of-truth namespace:
- [ ] Shinobi: `app-shinobi-0` → `lens-of-truth-shinobi-app-shinobi-0`
- [ ] Shinobi: `mysql-shinobi-0` → `lens-of-truth-shinobi-mysql-shinobi-0`
- [ ] Shinobi: `streams-shinobi-0` → `lens-of-truth-shinobi-streams-shinobi-0`
- [ ] Wazuh Dashboard: `dashboard-data-wazuh-dashboard-0` → `lens-of-truth-wazuh-dashboard-data-wazuh-dashboard-0`
- [ ] Wazuh Indexer: `wazuh-indexer-data-wazuh-indexer-0` → `lens-of-truth-wazuh-indexer-data-wazuh-indexer-0`
- [ ] Wazuh Manager: `wazuh-manager-data-wazuh-manager-0` → `lens-of-truth-wazuh-manager-data-wazuh-manager-0`

### tingle-tuner namespace:
- [ ] Ollama: `data-ollama-0` → `tingle-tuner-ollama-data-ollama-0`
- [ ] LibreTranslate: `models-libretranslate-0` → `tingle-tuner-libretranslate-models-libretranslate-0`

**Migration process (learned from Jellyfin/Plex migrations):**
1. Update volumeClaimTemplate names in StatefulSet patch to include namespace prefix
2. Scale down StatefulSet to 0 replicas
3. Commit changes and let FluxCD reconcile
4. Create recovery PVCs to mount old PVs
5. Use rsync with --delete flag to copy all data to new PVCs
6. Scale up StatefulSet and verify functionality
7. Clean up old PVCs, PVs, and RBD images from Ceph

**Note:** Each migration requires app downtime. Plan migrations during maintenance windows.

## Application Deployment - Final Stretch

### Remaining Applications to Template and Deploy to Kubernetes
- [ ] matrix-synapse - Matrix homeserver (federated chat)
- [ ] mastodon - Federated social media platform

**Status:** Final 3 applications remaining out of 100+ total applications inventoried across all Portainer endpoints.

**Applications that would be nice to add to the stack:**
- [ ] tinkerbell (Machine deployment automations)
- [ ] kubevirt (hypervisor)
- [ ] rook-ceph ~ Could potentially migrate PVE Ceph to K8s with BGP loadbalancing & disk passthrough we would lose nothing...
- [ ] vyOS ~ could extend k8s to handling routing and setup something truly resiliant and robust as compared to pfsense.
- [ ] Spegel (P2P container image sharing) - Nodes share images peer-to-peer, reducing registry pulls. New nodes get images from peers instantly. Zero additional storage overhead. https://github.com/spegel-org/spegel

**Large stacks to migrate** (not yet deployed to K8s):
- [ ] ARK servers (6 instances) - Game servers on Jabu-Jabu
- [ ] Minecraft servers (2 instances) - Game servers on Jabu-Jabu

**Custom container images needed:**
- [ ] Proxmox Backup Server - No decent official container image available, will need to create custom image

**Custom landing pages / static sites to containerize:**
- [ ] sofmeright.com - Personal landing page
- [ ] precisionplanit.com - Business landing page
- [ ] yesimvegan.com - Vegan resources landing page
- [ ] astralfocal.com - Landing page
- [ ] homelabhelpdesk.com - Homelab resources landing page

## Applications Requiring Further Review

**Applications that cannot be deployed to Kubernetes in current form:**

### Nextcloud AIO (All-in-One)
**Status:** Architecture incompatible with Kubernetes
**Reason:** Nextcloud AIO is designed specifically for Docker and Docker Compose with tight coupling to:
- Docker socket access for managing its own containers
- Self-managed backup system requiring specific volume structure
- Master container pattern that dynamically creates/destroys other containers
- Hardcoded container names that cannot be changed without breaking functionality
- Reliance on Docker-specific networking and volume behaviors

**Current deployment:** Running on Docker host at `10.30.1.123` (Moor)

**Why standard Nextcloud Helm charts won't work:**
- No support for Nextcloud apps/plugins (Collabora, OnlyOffice, Talk, etc.)
- Missing integrated components that AIO provides (imaginary, fulltextsearch, notify_push)
- Requires manual assembly of disparate components with complex configuration
- No equivalent to AIO's automated backup/restore system
- Would lose significant functionality compared to current AIO deployment

**Decision:** Keep running on dedicated Docker host - AIO provides superior experience and functionality

## Infrastructure Modernization

### Standardize Ceph CSI Provisioner Naming
**Status:** Inconsistent naming between RBD and CephFS provisioners
**Current state:**
- RBD StorageClasses use `rbd.csi.ceph.com` provisioner (generic upstream naming)
- CephFS StorageClasses use `gorons-bracelet.cephfs.csi.ceph.com` provisioner (cluster-specific naming)

**Target state:** Both provisioners should follow the same naming pattern
- Option 1: Rename RBD to `gorons-bracelet.rbd.csi.ceph.com` (matches CephFS pattern)
- Option 2: Rename CephFS to `rbd.csi.ceph.com` pattern (but CephFS is already deployed as cluster-specific)

**Recommended approach:** Rename RBD provisioner to match CephFS cluster-specific naming

**Migration tasks:**
- [ ] Update RBD Driver CRD name from `gorons-bracelet.rbd.csi.ceph.com` to match naming pattern
- [ ] Update all RBD StorageClasses to use new provisioner name
- [ ] Migrate existing PVCs using old provisioner name to new provisioner (may require PVC recreation)
- [ ] Update application manifests referencing old StorageClass names
- [ ] Test dynamic provisioning with new RBD provisioner name
- [ ] Clean up old provisioner resources after migration

**Note:** This will cause downtime for applications using RBD PVCs during migration. Plan carefully.

## Cilium cluster-pool IPAM Migration

### Overview
Migrate from `ipam: kubernetes` to `ipam: cluster-pool` to enable static pod IP assignments and improve network segmentation through IP-based tiering.

### Primary Goal
Enable static pod IP for CrowdSec cloudflare-bouncer to prevent duplicate LAPI registrations.

**Problem:** CrowdSec LAPI tracks bouncers by source IP. Each pod restart = new IP = duplicate bouncer registration.

**Solution:** Static pod IP annotation (requires cluster-pool IPAM mode).

### Planned IP Segmentation

#### IPv4 Pod CIDR: 192.168.144.0/20 (4096 IPs total)

**Tier 0: Core Infrastructure** - `192.168.144.0/22` (1024 IPs)
- Namespaces: `kube-system`, `flux-system`, `optcp-operators-privileged`
- Purpose: K8s control plane, storage operators, CSI drivers, core CNI

**Tier 1: Security & Administrative** - `192.168.148.0/23` (512 IPs)
- Namespaces: `zeldas-lullaby`, `lens-of-truth`, `wallmaster`
- Purpose: Vault, Zitadel, External Secrets, CrowdSec, Wazuh, IDS/IPS, bot protection

**Tier 2: Monitoring & Observability** - `192.168.150.0/24` (256 IPs)
- Namespaces: `gossip-stone`
- Purpose: Prometheus, Grafana, Loki, Alloy, Thanos

**Tier 3: Networking Services** - `192.168.151.0/24` (256 IPs)
- Namespaces: `compass`, `king-of-red-lions`
- Purpose: DNS (AdGuard), NTP (Chrony), Traefik, cert-manager, Gateway API

**Tier 4: Business/Work - Tenant A** - `192.168.152.0/22` (1024 IPs)
- Namespaces: `hyrule-castle`
- Purpose: GitLab, ERPNext, Dolibarr, InvoiceNinja, business applications

**Tier 5: Media & Content** - `192.168.156.0/23` (512 IPs)
- Namespaces: `temple-of-time`, `pedestal-of-time`
- Purpose: Plex, Jellyfin, Immich, Calibre-Web, Mealie, content management

**Tier 6: General Services** - `192.168.158.0/23` (512 IPs)
- Namespaces: `lost-woods`, `tingle-tuner`, `kokiri-forest`, `delivery-bag`, `fairy-bottle`
- Purpose: Dashboards, IT tools, file browsers, notifications, backups (Velero)

**Tier 7: Isolated/VPN-routed** - `192.168.160.0/24` (256 IPs)
- Namespaces: `swift-sail`
- Purpose: Arr apps (Prowlarr, Radarr, Sonarr, etc.) through Gluetun VPN

**Tier 8: Game Servers** - `192.168.161.0/24` (256 IPs)
- Namespaces: `shooting-gallery`
- Purpose: Minecraft, ARK, Pelican Panel, game hosting

**Tier 9: Remote Access** - `192.168.162.0/24` (256 IPs)
- Namespaces: `hookshot`
- Purpose: Guacamole, TacticalRMM, MeshCentral

**Static Infrastructure Assignments** - `192.168.163.0/24` (256 IPs)
- Purpose: Reserved pool for static pod IP annotations
- Examples: CrowdSec cloudflare-bouncer (192.168.163.200)

#### IPv6 Pod CIDR: fc00:f1:d759:3053:a573::/64

Mirrors IPv4 tier structure with equivalent subnet sizes:

- **Tier 0**: `fc00:f1:d759:3053:a573:0::/67` - Core Infrastructure
- **Tier 1**: `fc00:f1:d759:3053:a573:2000::/67` - Security & Admin
- **Tier 2**: `fc00:f1:d759:3053:a573:4000::/68` - Monitoring
- **Tier 3**: `fc00:f1:d759:3053:a573:5000::/68` - Networking Services
- **Tier 4**: `fc00:f1:d759:3053:a573:6000::/66` - Business/Work
- **Tier 5**: `fc00:f1:d759:3053:a573:a000::/67` - Media & Content
- **Tier 6**: `fc00:f1:d759:3053:a573:c000::/67` - General Services
- **Tier 7**: `fc00:f1:d759:3053:a573:e000::/68` - Isolated/VPN
- **Tier 8**: `fc00:f1:d759:3053:a573:e100::/68` - Game Servers
- **Tier 9**: `fc00:f1:d759:3053:a573:e200::/68` - Remote Access
- **Static**: `fc00:f1:d759:3053:a573:e300::/68` - Static Infrastructure

### Implementation

**File**: `/srv/dungeon/fluxcd/infrastructure/controllers/base/cilium/helmrelease.yaml`

Change from:
```yaml
ipam:
  mode: kubernetes
```

To:
```yaml
ipam:
  mode: cluster-pool
  operator:
    clusterPoolIPv4PodCIDRList:
      - "192.168.144.0/22"    # Tier 0: Infrastructure
      - "192.168.148.0/23"    # Tier 1: Security & Admin
      - "192.168.150.0/24"    # Tier 2: Monitoring
      - "192.168.151.0/24"    # Tier 3: Networking
      - "192.168.152.0/22"    # Tier 4: Business/Work
      - "192.168.156.0/23"    # Tier 5: Media & Content
      - "192.168.158.0/23"    # Tier 6: General Services
      - "192.168.160.0/24"    # Tier 7: Isolated/VPN
      - "192.168.161.0/24"    # Tier 8: Game Servers
      - "192.168.162.0/24"    # Tier 9: Remote Access
      - "192.168.163.0/24"    # Static Infrastructure
    clusterPoolIPv6PodCIDRList:
      - "fc00:f1:d759:3053:a573:0::/67"
      - "fc00:f1:d759:3053:a573:2000::/67"
      - "fc00:f1:d759:3053:a573:4000::/68"
      - "fc00:f1:d759:3053:a573:5000::/68"
      - "fc00:f1:d759:3053:a573:6000::/66"
      - "fc00:f1:d759:3053:a573:a000::/67"
      - "fc00:f1:d759:3053:a573:c000::/67"
      - "fc00:f1:d759:3053:a573:e000::/68"
      - "fc00:f1:d759:3053:a573:e100::/68"
      - "fc00:f1:d759:3053:a573:e200::/68"
      - "fc00:f1:d759:3053:a573:e300::/68"
```

**Static IP Annotation** (already applied to CrowdSec cloudflare-bouncer):
```yaml
# File: fluxcd/infrastructure/controllers/overlays/production/crowdsec/statefulset-cloudflare-bouncer-patch.yaml
spec:
  template:
    metadata:
      annotations:
        ipam.cilium.io/ip-address: "192.168.163.200"
```

### Migration Impact

**Estimated Downtime**: 5-15 minutes rolling disruption

**What Changes**:
- All 321 pods get new IPs from cluster-pool as Cilium DaemonSet rolls out
- Pod IPs reassigned within same overall CIDR (192.168.144.0/20)
- Connections drop and reconnect as pods restart

**What Stays Stable**:
- Service ClusterIPs (10.144.0.0/12) - unchanged
- LoadBalancer IPs (172.22.30.0/24) - unchanged
- Node IPs (172.22.144.x) - unchanged
- BGP routes - entire /20 still advertised

**Risk Assessment**: Medium
- Pods communicate via Services/DNS (not direct pod IPs) - minimal impact
- Network policies use label selectors (not IPs) - no changes needed
- Potential issues: Long-lived connections, WebSockets may drop temporarily

### Benefits

- **Static pod IPs**: Annotations enable permanent IP assignment (solves CrowdSec bouncer issue)
- **Network segmentation**: IP-based tiers enable clearer security boundaries
- **Multi-tenancy ready**: IP isolation supports future tenant segregation
- **Advanced features**: Unlocks per-namespace pools, IP reservation, multi-cluster IPAM

## GPU Infrastructure

### Host-Installed NVIDIA Drivers for dungeon-chest-004

**Status:** Active - Using Ubuntu-provided NVIDIA drivers

**Node:** dungeon-chest-004 (172.22.144.173)

**Configuration:**
- **Driver Source:** Ubuntu repository (`nvidia-driver-580`)
- **Driver Version:** 580.95.05
- **Signing:** Canonical-signed (Secure Boot compatible)
- **GPU Operator Mode:** `driver.enabled: false` (host drivers only)
- **Kernel:** Automatically updates with Ubuntu security patches

**Rationale:**
- Ubuntu's NVIDIA drivers are Canonical-signed and work with Secure Boot on any kernel version
- Kernel can receive security updates without waiting for NVIDIA precompiled containers
- GPU Operator still provides device plugin, monitoring, GFD, CDI, time-slicing, etc.
- Same driver version (580.95.05) used successfully on other production workstations

**GPU Operator Capabilities (with `driver.enabled: false`):**
- ✅ GPU Feature Discovery (GFD) - Automatic node labeling
- ✅ Device Plugin - Exposes `nvidia.com/gpu` resources
- ✅ DCGM Exporter - GPU metrics and monitoring
- ✅ Node Feature Discovery (NFD) - Hardware detection
- ✅ NVIDIA Container Toolkit - CDI mode support
- ✅ Time-slicing - GPU sharing (10 replicas configured)
- ✅ Validator - GPU functionality testing

**Maintenance:**

Driver updates via standard Ubuntu package management:
```bash
ssh dungeon-chest-004 "sudo apt update && sudo apt upgrade -y"
# Reboot required after driver upgrades
ssh dungeon-chest-004 "sudo reboot"
```

Check installed driver version:
```bash
ssh dungeon-chest-004 "nvidia-smi"
```

Verify GPU availability in Kubernetes:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.'nvidia\.com/gpu'
```

**Related Documentation:**
- GPU Operator with Pre-installed Drivers: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#considerations-for-pre-installed-drivers
- GPU Operator Platform Support: https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html

**Last Updated:** 2025-11-10

## Prometheus Metrics - Exportarr Sidecars

**Status:** Pending

**Goal:** Add Prometheus metrics exporters to the downloadarrs pod for monitoring arr apps and qBittorrent.

### Exportarr Sidecars
- [ ] Add exportarr sidecar for Sonarr metrics
- [ ] Add exportarr sidecar for Radarr metrics
- [ ] Add exportarr sidecar for Lidarr metrics
- [ ] Add exportarr sidecar for Readarr metrics
- **Source:** https://github.com/onedr0p/exportarr

### qBittorrent Exporter
- [ ] Add qbittorrent-exporter sidecar to downloadarrs pod
- **Source:** https://github.com/caseyscarborough/qbittorrent-exporter or https://github.com/esanchezm/prometheus-qbittorrent-exporter

**Note:** These sidecars will expose `/metrics` endpoints that Alloy can scrape (requires `prometheus.io/scrape: "true"` annotation).

- [ ] Create PrometheusRule alert for `prometheus_remote_write_samples_failed_total` to monitor metrics ingestion health

## PostgreSQL HA Alternatives Evaluation

**Status:** Research complete - Decision pending

**Context:** CNPG clusters experienced replica divergence during node outages. 3/12 clusters failed (zitadel, gitlab, appflowy) while 9/12 survived identical hardware scenarios. Root cause: WAL timeline divergence when replicas can't catch up before WAL is recycled.

### Current Solution: CloudNativePG (CNPG)
- **Architecture:** Single-primary with streaming replication
- **Failure mode:** Timeline divergence during failovers - replicas need pg_rewind or rebuild
- **Strengths:** Actual PostgreSQL, full extension support, mature operator
- **Weaknesses:** Failover creates new timeline, requires WAL availability for replica recovery
- **Fix applied:** Increased `wal_keep_size` and `max_slot_wal_keep_size` for consistency across clusters

### Alternative 1: YugabyteDB
- **Architecture:** Distributed SQL with Raft consensus per shard
- **Engine:** PostgreSQL wire-compatible (not actual PostgreSQL)
- **License:** Apache 2.0 (fully open source)
- **Strengths:**
  - True distributed consistency via Raft - no timeline divergence
  - Automatic failover without data loss
  - Read-your-writes guarantee across all nodes
- **Weaknesses:**
  - Not actual PostgreSQL - some extensions won't work
  - Higher resource overhead (Raft consensus)
  - Smaller community than PostgreSQL
- **Best for:** Apps needing strong consistency, can tolerate PostgreSQL-compatible vs actual PostgreSQL

### Alternative 2: pgEdge
- **Architecture:** Multi-master using logical replication (Spock extension)
- **Engine:** Actual PostgreSQL
- **License:** PostgreSQL License (permissive, OSI-approved)
- **Strengths:**
  - True multi-master/active-active - any node accepts writes
  - No failover needed - all nodes are primary
  - Full PostgreSQL extension compatibility (pgVector, PostGIS, etc.)
  - Open source core (Spock, LOLOR, Snowflake extensions)
- **Weaknesses:**
  - Eventual consistency for cross-node reads (replication lag)
  - Timestamp-based conflict resolution (last-write-wins)
  - DDL replication only recently added
  - Smaller community than YugabyteDB
- **Best for:** Apps needing real PostgreSQL with multi-master, can tolerate eventual consistency

### Alternative 3: TiDB (MySQL-compatible)
- **Architecture:** Distributed SQL with Raft consensus (inspired by Google Spanner)
- **Engine:** MySQL wire-compatible (not actual MySQL)
- **License:** Apache 2.0 (fully open source, including enterprise features)
- **Storage:** TiKV (CNCF graduated project)
- **Strengths:**
  - Strong consistency via Raft (like YugabyteDB)
  - MySQL 8.0 compatible - use existing MySQL clients/ORMs
  - HTAP support - both OLTP and OLAP workloads
  - Horizontal scaling without sharding complexity
  - Two-phase commit for ACID across nodes
- **Weaknesses:**
  - Not actual MySQL - some edge cases may differ
  - Higher resource overhead (3+ TiKV nodes, 3+ PD nodes, TiDB nodes)
  - Complex architecture (TiDB + TiKV + PD components)
  - Smaller community than PostgreSQL ecosystem
- **Best for:** MySQL workloads needing strong consistency, horizontal scaling, or analytics (HTAP)

### Consistency Model Comparison

| Scenario | CNPG | YugabyteDB | pgEdge |
|----------|------|------------|--------|
| Write to Node A, read from Node B immediately | N/A (single primary) | Consistent (Raft) | May see stale data (async replication) |
| Simultaneous writes to same row | N/A (single primary) | Serialized (Raft) | Last-write-wins (timestamp) |
| Node failure during write | Failover + potential data loss | No data loss (Raft quorum) | Other nodes continue (async lag) |
| Read-your-writes guarantee | Yes (single primary) | Yes (always) | Only on same node |

### Recommendation

1. **Keep CNPG** for most workloads - it works well with proper WAL retention settings
2. **Consider YugabyteDB** for new apps requiring strong consistency (financial, inventory)
3. **Consider pgEdge** if multi-master is needed AND eventual consistency is acceptable

### Healing Script for CNPG Replica Failures

Location: `bash/maintenance/cnpg-heal-replica.sh`

Usage:
```bash
# Heal a specific failed replica (does NOT auto-detect - you specify the replica)
./bash/maintenance/cnpg-heal-replica.sh <cluster-name> <namespace> <replica-number>

# Examples for current failed replicas:
./bash/maintenance/cnpg-heal-replica.sh gitlab-postgresql hyrule-castle 1
./bash/maintenance/cnpg-heal-replica.sh gitlab-postgresql hyrule-castle 3
./bash/maintenance/cnpg-heal-replica.sh zitadel-postgres zeldas-lullaby 2
./bash/maintenance/cnpg-heal-replica.sh zitadel-postgres zeldas-lullaby 3
./bash/maintenance/cnpg-heal-replica.sh appflowy-postgres temple-of-time 1
```

**Last Updated:** 2026-01-16

## Gateway API: CSP Header Override

Some apps set restrictive `frame-ancestors 'self'` CSP headers blocking dashboard embedding. Need EnvoyFilter response header manipulation to override for: zitadel, photoprism, qbittorrent, calibre-web.

## Gateway API: Request Body Size Limits

Unlike nginx (`client_max_body_size`), Istio has no default request body limit. Consider adding EnvoyFilter limits on public gateways (phloem/cell-membrane) to prevent DoS, with exceptions for apps needing large uploads.

```yaml
spec:
  configPatches:
    - applyTo: HTTP_CONNECTION_MANAGER
      match:
        context: GATEWAY
      patch:
        operation: MERGE
        value:
          max_request_bytes: 52428800  # 50MB
```

## Jellyfin 10.11.x Upgrade Investigation

**Status:** Blocked - Plugin compatibility unknown

**Current State:**
- Jellyfin version: 10.10.7
- SSO Authentication plugin: v3.5.2.4
- Skin Manager plugin: v2.0.2.0

**Required for 10.11.x Upgrade:**

### SSO Authentication Plugin
- [ ] Update SSO plugin from v3.5.2.4 to v4.0.0.3
- **Source:** https://github.com/9p4/jellyfin-plugin-sso/releases
- **Note:** v3.5.2.4 is for 10.10.x, v4.0.0.3 required for 10.11.x
- **Install method:** Manual - download zip to `/config/plugins/SSO Authentication_4.0.0.3/`

### Skin Manager Plugin
- [ ] Investigate Skin Manager compatibility with 10.11.x
- **Source:** https://github.com/danieladov/jellyfin-plugin-skin-manager
- **Current version:** 2.0.2.0 (last updated Nov 2022)
- **Status:** Marked as "stale", some features broken in 10.10.7
- **Risk:** HIGH - likely to break with no maintainer to fix

### JellySkin Theme
- [ ] Investigate JellySkin theme compatibility with 10.11.x
- **Source:** https://github.com/prayag17/JellySkin

**Decision:** Stay on 10.10.7 until plugin compatibility is confirmed or alternatives found for Skin Manager.
