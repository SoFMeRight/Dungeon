- Repository Information:
  - Git repository: ssh://git@10.30.1.123:2424/SoFMeRight/dungeon
  - Repository name: dungeon (formerly ant_parade-public)
  - **Git Commits**: Only sign commits as sofmeright@gmail.com / SoFMeRight. No anthropic attribution comments in commits.

- Image-Based Tool Standards:
  - **kubectl**: Use `docker.io/alpine/k8s` image (e.g., `docker.io/alpine/k8s:1.34.0`) - includes shell and kubectl for job sidecars and init containers

- CRITICAL RULES:
  - Prefer using flux to reconcile resources from source. We are GitOps native, we use kubectl commands to adjust state only when it is otherwise impossible!!!!!
  - When working with files in source control, make clean moves that dont create a headache of files!!!!
  - STAY ON TASK when following directions. NO BAND AID, NO FUCKING WORK AROUNDS. IF YOU THINK WE NEED TO GIVE UP or regroup and re-evaluate. ASK. DONT MAKE THE CALL ON YOUR OWN to find alternative solutions or FIND A SHORTCUT. I CAN FIND MY OWN WAYS TO BASTARDIZE THINGS I DONT NEED YOUR FUCKING HELP. I want things done exactly how I ask. If I am to be offered an alternative, conversation should stop till I tell you if I agree/disagree with the alternative proposed.
  - **NEVER drain nodes or force delete database pods without explicit permission** - causes unrecoverable PostgreSQL/MariaDB WAL corruption and RBD data loss. Safe procedure: cordon → audit stateful workloads → migrate database primaries gracefully → drain with --grace-period=300.
  - **NEVER delete PVCs for CNPG-managed PostgreSQL clusters** - deleting PVCs corrupts the CNPG instance index and breaks cluster management. To heal a stuck/diverged replica, use `ansible-playbook k8s/recovery/hasteward.yml -e engine=cnpg -e cluster_name=<name> -e namespace=<ns> -e mode=repair -e instance_number=<N>` which triages the cluster, then fences the instance, clears pgdata on the existing PVC, runs pg_basebackup from the primary, then unfences. Use `mode=triage` for read-only diagnostics.
  - **hasteward** (`ansible/k8s/recovery/hasteward.yml`) - HASteward (High Availability Steward) - Ansible playbook that standardizes recovery logic for common stateful services (PostgreSQL, MariaDB) to safely revive stalled replicas where possible
    - Engines: `galera` (MariaDB Galera clusters), `cnpg` (CloudNativePG PostgreSQL clusters)
    - `mode=triage` - read-only diagnostic, triages all instances
    - `mode=repair` - triage → safety gate → escrow backup → heal all unhealthy instances → re-triage
    - `mode=repair -e instance_number=N` - triage → safety gate → escrow backup → heal specific instance
    - `mode=backup` - take a backup of the cluster (dump to backups_path, or native S3 for CNPG)
    - `mode=restore` - restore a cluster from a backup (dump method)
    - `force=true` - override split-brain/healthy checks (targeted repair only)
    - `backups_path=/path` - local filesystem path for backup storage (required for repair unless no_escrow, required for backup/restore dump)
    - `no_escrow=true` - skip escrow backup before repair (accept the risk)
    - `retain_escrow=true` - keep escrow after successful repair (otherwise deleted on success)
    - `backup_method=dump|native` - dump (default, works everywhere) or native (CNPG barmanObjectStore only)
    - Galera example: `ansible-playbook k8s/recovery/hasteward.yml -e engine=galera -e cluster_name=osticket-mariadb -e namespace=hyrule-castle -e mode=repair -e instance_number=0 -e backups_path=/backups`
    - CNPG example: `ansible-playbook k8s/recovery/hasteward.yml -e engine=cnpg -e cluster_name=zitadel-postgres -e namespace=zeldas-lullaby -e mode=repair -e instance_number=3 -e backups_path=/backups`
    - Backup example: `ansible-playbook k8s/recovery/hasteward.yml -e engine=cnpg -e cluster_name=zitadel-postgres -e namespace=zeldas-lullaby -e mode=backup -e backups_path=/backups`
    - Restore example: `ansible-playbook k8s/recovery/hasteward.yml -e engine=galera -e cluster_name=osticket-mariadb -e namespace=hyrule-castle -e mode=restore -e backups_path=/backups`

- FluxCD Infrastructure Structure:
  - `fluxcd/infrastructure/controllers/base` should contain TEMPLATED infrastructure resources WITHOUT any environment-specific values including: no hardcoded namespaces, image tags, replicas, storage classes, LoadBalancer IPs, cluster-specific annotations (lbipam.cilium.io/*), domain names, URLs, etc.
  - `fluxcd/infrastructure/controllers/overlays/production` should contain ALL environment-specific infrastructure configurations and patches for the production cluster: LoadBalancer IPs, cluster-specific annotations, domain names, storage classes, etc.
  - **NAMESPACE MANAGEMENT STANDARD**: All infrastructure overlays MUST use kustomization-level `namespace:` field (standard kustomize pattern):
    - Base resources: NO namespace metadata anywhere
    - Overlay kustomization.yaml: `namespace: <target-namespace>` field at kustomization level
    - Kustomize automatically adds namespace to all resources
    - Critical for infrastructure: Avoids conflicts between FluxCD namespace (flux-system) and target deployment namespace (kube-system, etc.)
  - `fluxcd/infrastructure/configs` should only provide secrets and configuration values
  - `fluxcd/infrastructure/namespaces` manages all Kubernetes namespaces - ALL namespaces MUST be deployed via this path only
    - Namespaces (Ocarina of Time theme):
      - tingle-tuner: Tools and utilities (quirky helper character)
      - zeldas-lullaby: Administrative services (vault, weave, zitadel)
      - compass: DNS & NTP services (navigation/direction)
      - gossip-stone: Monitoring services (tells you secrets/info)
      - lost-woods: Discovery & Dashboards (exploration/finding things)
      - temple-of-time: Archival/Content Management & Media Servers (linkwarden, calibre-web, mealie, plex)
      - fairy-bottle: Backup services (velero, urbackup - restores/saves state)
      - gorons-bracelet: Storage services (minio, longhorn, rook-ceph - provides strength/lifting power)
      - arylls-lookout: Gateway for internal-only services (xylem replacement)
      - kokiri-forest: Gateway for personal/public services (phloem replacement)
      - hyrule-castle: Gateway for business/work services (cell-membrane replacement)
      - king-of-red-lions: Routing & Gateway infrastructure (traefik, stunner - guides you across the sea)
      - shooting-gallery: Game servers (minecraft, etc - aiming for fun)
      - lens-of-truth: IDS/IPS/SIEM security monitoring (reveals hidden threats)
      - hookshot: RDP/remote control services (tacticalrmm, meshcentral - grappling to reach remote targets)
      - swift-sail: Arr apps & downloaders (prowlarr, radarr, sonarr - swift sailing across the seas)
      - pedestal-of-time: Restricted/privileged services (only link can pull the master sword)
      - delivery-bag: Mail services (mailcow - postman's delivery bag)
      - wallmaster: Bot protection & security services (anubis - the hand that grabs intruders)
      - gerudo-crest: Controlled access & internal trust wiring (reflector - sealed fortress, guards the gate)
  - Base should NEVER contain deployment-ready configs - only generic templates that overlays patch with real values. Base should document application defaults from upstream/vendor documentation, not production-specific configurations.
  - Always use overlays/production for actual deployment to the production cluster, never deploy from base

- Secret Management Strategy:
  - Critical infrastructure apps (vault, zitadel, etc.) use SOPS for secret management so they can run with local auth without dependencies during cluster issues
  - **CRITICAL: Never edit .enc.yaml files directly!** These are SOPS-encrypted files. Direct editing corrupts them and destroys secrets permanently. Always use `sops` command to decrypt, edit plaintext, then re-encrypt.
  - Most other applications use Vault External Secrets Operator to manage secrets from Vault at http://172.22.30.86:8200/ui/vault/secrets/operationtimecapsule/kv/list
  - Vault secret path structure in operationtimecapsule namespace:
    - `apps/<app-name>` - bundled comprehensive secrets specific to that application (e.g., apps/linkwarden)
    - `smtp/<service-name>` - SMTP-related secrets that may be shared between applications (e.g., smtp/ofcourseimvegan)
    - `smb/<share-name>` - SMB/storage secrets that may be shared between applications (e.g., smb/media-books-rw)
    - Shared paths (smtp/, smb/) are for secrets used by multiple applications, app-specific paths (apps/) are for single application use
- Container Image Standards:
  - **ALWAYS use fully qualified image names** with registry prefix (e.g., `docker.io/binwiederhier/ntfy:v2.11.0` NOT `binwiederhier/ntfy:v2.11.0`)
  - **Container Registry Credentials**: Managed as shared resources in `infrastructure/configs/overlays/production/registries/`
    - Base template: `infrastructure/configs/base/registries/docker.io-example/`
    - Production overlays: `infrastructure/configs/overlays/production/registries/<registry>-<account>/`
    - Apps reference the pull secret by name (e.g., `cr-pcfae-admin-pull-secret`) in their deployment `imagePullSecrets`
    - Credentials stored in Vault at `registries/<registry-url>` with keys: `username`, `password`

- Harbor Container Registry Strategy:
  - **Primary Registry**: Harbor (internal) at `cr.pcfae.com`, admin-managed. Runs external to the cluster for independent availability. **Replaces the retired JFrog/JCR** — `jcr.pcfae.com`, `*.jcr.pcfae.com`, `jcr-pcfae-dungeon-pull-secret`, and the `jcr-pull-secret` label are all DEAD; do not reference them.
  - **Pull-Through Cache Registries**: Harbor proxy-cache projects proxy upstream registries via `*.cr.pcfae.com` subdomains
    - `docker.cr.pcfae.com` - Docker Hub (docker.io) pull-through cache
    - `ghcr.cr.pcfae.com` - GitHub Container Registry (ghcr.io) pull-through cache
    - `quay.cr.pcfae.com` - Quay.io (quay.io) pull-through cache
    - `lscr.cr.pcfae.com` - LinuxServer.io (lscr.io) pull-through cache
  - **CRI-O Registry Mirrors (Automatic)**:
    - All cluster nodes have CRI-O registry mirrors configured to route upstream names through the Harbor mirrors
    - **Transparent redirection**: Images can be requested using original registry names (e.g., `docker.io/redis:alpine`) and CRI-O automatically pulls through the Harbor mirrors
    - **Automatic fallback**: If Harbor is unavailable, CRI-O falls back to upstream registries
    - **Mirrored registries**: docker.io → docker.cr.pcfae.com, ghcr.io → ghcr.cr.pcfae.com, lscr.io → lscr.cr.pcfae.com, quay.io → quay.cr.pcfae.com
    - **Benefits**: Reduces bandwidth, avoids rate limits, caches images, no manifest changes required.
  - **Image Pull Strategy**:
    - **All Applications**: Always use original upstream registry names (docker.io, ghcr.io, quay.io, lscr.io) - CRI-O mirrors automatically route through Harbor with transparent fallback
    - **No need to explicitly reference `*.cr.pcfae.com`**: CRI-O handles the routing automatically, no manifest changes required
  - **Pull Secret**: `cr-pcfae-admin-pull-secret`, distributed by a ClusterExternalSecret (ESO, Vault-backed; auths `cr.pcfae.com`) to every namespace labeled `cr-pcfae-pull-secret: "enabled"`. Namespaces are labeled in `fluxcd/infrastructure/namespaces/<ns>.yaml`.

- FluxCD App Structure:
  - `fluxcd/apps/base/<app>/` contains TEMPLATED Kubernetes resources WITHOUT any environment-specific values including: no hardcoded namespaces, image tags, replicas, storage classes, LoadBalancer IPs, cluster-specific annotations (lbipam.cilium.io/*), domain names, URLs, etc. These are reusable templates across environments.
  - `fluxcd/apps/overlays/production/<app>/` references the base (`../../../base/<app>`) and contains ALL environment-specific configurations via patches: namespace, image tags, replica counts, storage classes, LoadBalancer configurations, ingress configs, domain names, URLs, cluster-specific annotations, etc. for the production cluster.
  - **NAMESPACE MANAGEMENT STANDARD**: All overlays MUST use kustomization-level `namespace:` field (standard kustomize pattern):
    - Base resources: NO namespace metadata anywhere
    - Overlay kustomization.yaml: `namespace: <target-namespace>` field at kustomization level
    - Kustomize automatically adds namespace to all resources
    - **CRITICAL**: Use `patches:` field ONLY - `patchesStrategicMerge` is deprecated by FluxCD
    - Benefits: Standard kustomize behavior, clean and simple, no complex patches needed
  - Base should NEVER contain deployment-ready configs - only generic templates that overlays patch with real values. Base should document application defaults from upstream/vendor documentation, not production-specific configurations. If you see cluster-specific IPs, domains, or annotations in base, they must be moved to overlay patches.
  - Other environments (staging, dev) can inherit the same base with different overlays.
  - Never deploy directly from base - always use overlays for actual deployments.
- Cluster initialization is handled by bash\_importing_from_sibling_repo\bootstrap-k8s-install-dependencies.sh bootstrap-k8s-initialize-control-plane.sh and a reset script. No other manipulation should be needed for initial cluster setup.

- Policy Contract Standard (Universal Capability Model):
  - **ONE STANDARD for all network policy contracts. No per-protocol conventions. No exceptions.**
  - Every backend type (postgres, redis, mariadb, kafka, s3, etc.) uses the exact same label pattern:
  - **Client capability** (what a workload may use):
    - `policy.prplanit.com/cap.<service>: "true"` — e.g., `cap.postgres`, `cap.redis`, `cap.s3`
    - Capabilities compose: a multi-backend pod declares all capabilities it holds
  - **Authorization scope** (which instance it may access):
    - `policy.prplanit.com/access-scope-<service>: <namespace>.<app>.<service>` — per-protocol key required (K8s labels are single-value)
  - **Server identity** (what a service provides):
    - `policy.prplanit.com/access-class: <service>` — e.g., `access-class: postgres`
  - **Instance identity** (the specific backend):
    - `policy.prplanit.com/service-scope: <namespace>.<app>.<service>` — globally unique
  - **Policy evaluation**: `client capability AND scope annotation exists AND server class match`
  - **CCNP contracts are backend-class admission gates**, NOT instance-scoped. Instance-level authorization (scope value matching) requires per-service CNPs.
  - **Infrastructure labels** (unchanged): `ingress`, `metrics`, `probe`, `webhook`, `cnpg` — boolean flags for infrastructure contract CCNPs
  - **Never use**: `client-postgres`, `client-redis`, `client-mariadb`, or any per-protocol client-role label. Use `cap.*` only.

- Helm Release Naming Standard:
  - HelmRelease metadata name should be the application name ONLY, without namespace prefix (e.g., `name: external-secrets` NOT `name: zeldas-lullaby-external-secrets`)
  - Always set `spec.releaseName` to match the application name for consistency
  - Always set `fullnameOverride` in Helm values to the application name to prevent namespace-prefixed pod names
  - Pod names should follow pattern: `<app-name>-<component>-<hash/index>` NOT `<namespace>-<app-name>-<component>-<hash/index>`
  - Examples:
    - HelmRelease name: `external-secrets`, releaseName: `external-secrets`, fullnameOverride: `external-secrets`
    - Results in pods: `external-secrets-xxxxx`, `external-secrets-webhook-xxxxx`, `external-secrets-cert-controller-xxxxx`
    - NOT: `zeldas-lullaby-external-secrets-xxxxx`
  - Benefits: Cleaner pod names, easier identification, consistent with custom StatefulSet naming

- Stateful sets should be used for PVCs that are for stateful applications! Deployments should only be used when the applications state doesnt need to be kept!

- PersistentVolume Naming Standard:
  - **NO hostPath VOLUMES**: This is a cluster - hostPath only works on a single node. Use ConfigMaps, Secrets, or PVCs instead.
  - **StatefulSet volumeClaimTemplates Behavior**: StatefulSets automatically append the StatefulSet name before the ordinal when creating PVCs from volumeClaimTemplates
    - Template naming pattern: `<namespace>-<app>-<purpose>`
    - StatefulSet name: `<app>`
    - Resulting PVC name: `<namespace>-<app>-<purpose>-<app>-<ordinal>`
    - **NOTE**: This creates intentional redundancy where the app name appears twice - this is how Kubernetes StatefulSets work and cannot be avoided without non-standard naming
  - Components:
    - `<namespace>`: The Kubernetes namespace (e.g., temple-of-time, lost-woods, gossip-stone)
    - `<app>`: The application name (e.g., jellyfin, homarr, netalertx, beszel)
    - `<purpose>`: Descriptive purpose/type identifying what the volume stores
      - For databases: Use specific DB type (postgres, mysql, sqlite, redis) NOT generic "database" or "data"
      - For storage: Use descriptive purpose (config, images, media, transcode, cache, storage, data)
    - `<ordinal>`: StatefulSet replica index (0, 1, 2, etc.)
  - **Actual PVC naming examples** (as created by StatefulSets):
    - `temple-of-time-jellyfin-config-jellyfin-0` - Jellyfin configuration (template: temple-of-time-jellyfin-config)
    - `temple-of-time-jellyfin-cache-jellyfin-0` - Jellyfin cache (template: temple-of-time-jellyfin-cache)
    - `lost-woods-homarr-sqlite-homarr-0` - Homarr SQLite database (template: lost-woods-homarr-sqlite)
    - `lost-woods-homarr-images-homarr-0` - Homarr image storage (template: lost-woods-homarr-images)
    - `gossip-stone-netalertx-config-netalertx-0` - NetAlertX configuration (template: gossip-stone-netalertx-config)
    - `gossip-stone-beszel-data-beszel-0` - Beszel data (template: gossip-stone-beszel-data)

- Ceph Storage Configuration:
  - External Ceph cluster managed via Proxmox
  - Cluster FSID: `0985467c-d8f3-4483-b27f-f0a512397ec2`
  - MON hosts: `fc00:f1:ada:104e:1ace::1-5` (IPv6)
  - **Ceph Pool Structure**:
    - `dungeon` - Primary pool for RBD (block storage for PVCs) and general Ceph usage
    - `dungeon-rgw` - RGW metadata pool (realm/zone/control/meta/log/index)
    - `dungeon-rgw-data` - RGW object data pool (actual S3 bucket objects)
  - **Ceph Users**:
    - `client.dungeon-provisioner` - RBD volume provisioner
      (caps: mon 'allow r, allow command "osd blacklist", allow command "osd blocklist"',
      osd 'allow rwx pool=dungeon, allow rwx pool=dungeon_hdd,
      allow class-read object_prefix rbd_children,
      allow class-write object_prefix rbd_children', mgr 'allow rw')
    - `client.dungeon` - RBD volume mounter
      (caps: mon 'allow r, allow command "osd blacklist", allow command "osd blocklist"',
      osd 'allow class-read object_prefix rbd_children,
      allow rwx pool=dungeon, allow rwx pool=dungeon_hdd', mgr 'allow rw')
    - `client.dungeon-rgw` - RADOS Gateway user (caps: mon 'allow rw', osd 'allow rwx', mgr 'allow rw')
  - **RGW (S3) Configuration**:
    - Deployed in `gorons-bracelet` namespace as StatefulSet
    - **Canonical S3 endpoint**: `https://s3.pcfae.com` (all clients, internal and external)
    - TLS terminated at xylem-gateway (172.22.30.69) using `*.pcfae.com` Let's Encrypt wildcard cert — publicly trusted, no custom CA plumbing needed
    - HTTPRoute `ceph-rgw-s3` in gorons-bracelet routes `s3.pcfae.com` → ceph-rgw service (port 80)
    - All S3 clients MUST use path-style addressing (`s3ForcePathStyle: true`)
    - LoadBalancer IP: 172.22.30.101 (direct RGW access, admin/monitoring only)
    - Uses Ceph RBD for local cache/WAL (ReadWriteOnce PVCs)
    - Object data stored in `dungeon-rgw-data` pool via RADOS
    - **Principle**: Internal services use publicly trusted TLS identities. No split identity (`.svc.cluster.local` vs public). No `AWS_CA_BUNDLE`, no CA mounts, no reflector for trust.
  - **Setting up RGW pools on Proxmox Ceph cluster**:
    ```bash
    # Enable RGW on main dungeon pool (allows sharing with RBD)
    ceph osd pool application enable dungeon rgw --yes-i-really-mean-it

    # Create dedicated RGW pools with sensible naming
    ceph osd pool create dungeon-rgw 8 8           # Metadata pool
    ceph osd pool create dungeon-rgw-data 32 32    # Object data pool

    # Enable RGW application on pools
    ceph osd pool application enable dungeon-rgw rgw
    ceph osd pool application enable dungeon-rgw-data rgw
    ```
  - **Ceph CSI RBD Image Metadata** (for cross-pool migrations):
    - CSI stores 3 metadata keys on each RBD image - all inferable from K8s objects:
      - `csi.storage.k8s.io/pv/name` = PV name (format: `pvc-<PVC_UID>`)
      - `csi.storage.k8s.io/pvc/name` = PVC name
      - `csi.storage.k8s.io/pvc/namespace` = PVC namespace
    - **Migration procedure** (e.g., moving PVC from NVMe to HDD pool):
      1. Scale down workload to 0 replicas
      2. Delete old PVC (Retain policy keeps RBD image)
      3. Delete StatefulSet with `--cascade=orphan` (volumeClaimTemplates are immutable)
      4. Update overlay with new storageClassName, flux reconcile to recreate StatefulSet
      5. Scale up to create fresh PVC on new pool, capture PV name
      6. Scale down, then on Ceph node:
         ```bash
         # Copy data from old to new image
         rbd cp <old-pool>/csi-vol-<old-uuid> <new-pool>/csi-vol-<new-uuid>
         # Restore CSI metadata on new image
         rbd image-meta set <new-pool>/csi-vol-<new-uuid> csi.storage.k8s.io/pv/name <pv-name>
         rbd image-meta set <new-pool>/csi-vol-<new-uuid> csi.storage.k8s.io/pvc/name <pvc-name>
         rbd image-meta set <new-pool>/csi-vol-<new-uuid> csi.storage.k8s.io/pvc/namespace <namespace>
         ```
      7. Scale up workload

- Cluster Networking:
  - **NO MANUAL ROUTES EVER**: Cilium handles all routing via native eBPF with DSR, masquerading, BGP, LoadBalancer IPAM, and Gateway API (HTTPRoute). Never create manual ip route commands or static routes.
  - Pfsense router IPs are 172.22.144.21 & 172.22.144.23; the carp vip is 172.22.144.22. They provide BGP by peering with 172.22.144.150-154 172.22.144.170-74 and receiving /32 host routes for LoadBalancer IPs from the cluster. **CRITICAL: pfSense must NOT advertise 172.22.30.0/24 back to the cluster - doing so creates routing loops with DSR mode.**
  - **Dual-Stack Configuration**:
    - Cluster Pod CIDR IPv4: 192.168.144.0/20
    - Cluster Pod CIDR IPv6: fc00:f1:0ca4:15a0::/56
    - Service CIDR IPv4: 10.144.0.0/12
    - Service CIDR IPv6: fc00:f1:5e1d:a007::/112
    - DNS ClusterIP: 10.144.0.10
  - **Node Network (Dual-Stack)**:
    - dungeon-chest-001  172.22.144.170  /  fc00:f1:ada:1043:1ac3::170
    - dungeon-chest-002  172.22.144.171  /  fc00:f1:ada:1043:1ac3::171
    - dungeon-chest-003  172.22.144.172  /  fc00:f1:ada:1043:1ac3::172
    - dungeon-chest-004  172.22.144.173  /  fc00:f1:ada:1043:1ac3::173
    - dungeon-chest-005  172.22.144.174  /  fc00:f1:ada:1043:1ac3::174
    - dungeon-map-001    172.22.144.150  /  fc00:f1:ada:1043:1ac3::150
    - dungeon-map-002    172.22.144.151  /  fc00:f1:ada:1043:1ac3::151
    - dungeon-map-003    172.22.144.152  /  fc00:f1:ada:1043:1ac3::152
    - dungeon-map-004    172.22.144.153  /  fc00:f1:ada:1043:1ac3::153
    - dungeon-map-005    172.22.144.154  /  fc00:f1:ada:1043:1ac3::154
    - Control Plane VIP  172.22.144.105  /  fc00:f1:ada:1043:1ac3::105
  - BGP LOAD BALANCERS:
    - General CIDR: 172.22.30.0/24.
    - Shared IPs (Ocarina of Time naming theme):
      - Administrative (vault, zitadel, netbird): 172.22.30.86 (sharing-key: zeldas-lullaby)
      - Network infrastructure (unifi): 172.22.30.20 (sharing-key: kaepora-gaebora)
      - Mail services (ntfy-smtp): 172.22.30.102 (sharing-key: delivery-bag)
      - Bot protection services (anubis): 172.22.30.187 (sharing-key: wallmaster)
      - General MediaServers (jellyfin, plex): 172.22.30.123 (sharing-key: song-of-storms)
      - Media secondary (plex-ms-x, paperless): 172.22.30.124 (sharing-key: song-of-storms)
      - DNS & NTP, core services (chrony, adguard, netbootxyz, apt-cacher-ng): 172.22.30.122 (sharing-key: compass)
      - Monitoring (pve-exporter, truenas-exporter, eaton-ups, nutify): 172.22.30.137 (sharing-key: gossip-stone)
      - Alerting: 172.22.30.138 (sharing-key: navi)
      - Discovery & Dashboards: 172.22.30.223 (sharing-key: lost-woods)
      - Tools w/o userdata (xbackbone, neko-vpn, vlmcsd, endlessh-go, searxng): 172.22.30.107 (sharing-key: tingle-tuner)
      - Archival/Content Management (linkwarden, calibre-web, mealie): 172.22.30.222 (sharing-key: song-of-time)
      - Backup services (urbackup): 172.22.30.117 (sharing-key: fairy-bottle)
      - Storage services (ceph-rgw): 172.22.30.101 (sharing-key: gorons-bracelet)
      - Game servers (ark-sa, ark-se, minecraft): 172.22.30.231 (sharing-key: shooting-gallery)
      - VPN-routed *arr apps & tools (prowlarr, radarr, sonarr, py-kms): 172.22.30.33 (sharing-key: great-sea)
      - SIEM/IDS/IPS & cameras (wazuh-manager, frigate): 172.22.30.119 (sharing-key: lens-of-truth)
        > Drift: originally planned as split — lens-of-truth-managers (.119) + lens-of-truth-dashboards (.118). Only .119 deployed, uses key `lens-of-truth` (no `-managers` suffix). .118 is unallocated.
      - RDP/remote control services (tacticalrmm, meshcentral, rustdesk): 172.22.30.8 (sharing-key: hookshot)
      - Zero-trust access (boundary workers): 172.22.30.88 (sharing-key: farores-wind)
      - STUNner TURN/STUN gateway (neko-vpn WebRTC): 172.22.30.120 (no sharing-key — kyverno-mutated)

- Traefik & Gateway API Routing Strategy:
  - **IP-based Domain Isolation**: Use separate Gateway resources with unique LoadBalancer IPs to enable firewall-based internet exposure control (pfSense NAT rules per IP)
  - **Gateway Architecture**:
    - **xylem-gateway** (172.22.30.69, sharing-key: arylls-lookout): Internal-only services (*.pcfae.com) - NO pfSense port forward = internal only, can be enabled on-demand
    - **phloem-gateway** (172.22.30.70, sharing-key: kokiri-forest): Personal/public services (*.sofmeright.com, *.arbitorium.com, *.yesimvegan.com) - pfSense forwards port 443
    - **cell-membrane-gateway** (172.22.30.71, sharing-key: hyrule-castle): Business/work services (*.precisionplanit.com, *.prplanit.com, *.optcp.com, *.ipleek.com, *.uni2.cc) - pfSense forwards port 443
  - Each Gateway has its own:
    - Unique LoadBalancer IP via `lbipam.cilium.io/ips` annotation
    - Dedicated TLS certificate (cert-manager + Let's Encrypt)
    - Wildcard hostname listener for its domain(s)
  - HTTPRoutes reference the appropriate Gateway via `parentRefs` and hostname matching
  - Firewall (pfSense) controls public/private exposure via port forward rules per Gateway IP
  - Benefits: Same nginx-extras isolation model, firewall-controlled exposure, k8s-native routing
