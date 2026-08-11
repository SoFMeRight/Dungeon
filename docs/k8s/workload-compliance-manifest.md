# Workload Compliance Manifest

Living document tracking all workloads against production best practices aligned with **CIS Kubernetes Benchmark**, **SOC 2 Type II**, and **NIST 800-53** controls.

**Last Full Audit**: 2026-02-05 (initial creation)
**Target Compliance**: CIS Kubernetes Benchmark v1.8+, SOC 2 Trust Principles, NIST 800-53 Rev 5

## Quick Navigation

| Section | Purpose |
|---------|---------|
| [Compliance Framework Mapping](#compliance-framework-mapping) | CIS/SOC2/NIST control coverage |
| [Global Enforcement Standards](#global-enforcement-standards) | All required standards (SEC, RES, OBS, REL, IMG, NET, PSA, RBAC, SECRETS, etc.) |
| [Compliance Matrix by Namespace](#compliance-matrix-by-namespace) | Per-app current state tracking |
| [Pod Security Admission](#pod-security-admission-by-namespace) | PSA enforcement per namespace |
| [RBAC & ServiceAccount Audit](#rbac--serviceaccount-audit) | Access control status |
| [Secrets Management Audit](#secrets-management-audit) | Secrets hygiene tracking |
| [Image Security Status](#image-security-status) | Vulnerability and supply chain |
| [Backup & Disaster Recovery](#backup--disaster-recovery) | Backup schedules, RTO/RPO |
| [Runtime Security](#runtime-security) | Falco and threat detection |
| [Audit & Logging Status](#audit--logging-status) | Logging pipeline and compliance |
| [Encryption Status](#encryption-status) | At-rest and in-transit encryption |
| [Network Policy Planning](#network-policy-planning) | Zero-trust network segmentation |
| [Compliance Summary](#compliance-summary) | Overall scores and priority actions |
| [Appendix: Checklists](#appendix-implementation-checklists) | Onboarding, namespace, periodic audit |

---

## Compliance Framework Mapping

### CIS Kubernetes Benchmark Coverage

| CIS Section | Control Area | Our Standard | Status |
|-------------|--------------|--------------|--------|
| 5.1.x | RBAC & Service Accounts | RBAC-* | Tracking |
| 5.2.1 | Minimize privileged containers | SEC-1,2 | Enforcing |
| 5.2.2 | Minimize allowPrivilegeEscalation | SEC-5 | Enforcing |
| 5.2.3 | Minimize root containers | SEC-1,2 | Enforcing |
| 5.2.4 | Minimize NET_RAW capability | SEC-6 | Enforcing |
| 5.2.5 | Minimize added capabilities | SEC-6 | Enforcing |
| 5.2.6 | Minimize SYS_ADMIN capability | SEC-6 | Enforcing |
| 5.2.7-9 | Minimize host namespace sharing | SEC-9,10,11 | Tracking |
| 5.2.10 | Minimize containers without securityContext | SEC-* | Enforcing |
| 5.3.x | Network Policies | NET-* | Planning |
| 5.4.1 | Secrets as files not env vars | SECRETS-2 | Tracking |
| 5.7.x | General Policies | Various | Partial |

### SOC 2 Trust Principles Coverage

| Principle | Our Controls | Status |
|-----------|--------------|--------|
| **Security** | SEC-*, NET-*, RBAC-*, IMG-* | Partial |
| **Availability** | REL-*, RES-*, BACKUP-* | Tracking |
| **Processing Integrity** | OBS-*, AUDIT-* | Tracking |
| **Confidentiality** | SECRETS-*, NET-*, ENCRYPT-* | Tracking |
| **Privacy** | Data classification (future) | Not Started |

### NIST 800-53 Control Families

| Family | Controls | Our Standards | Status |
|--------|----------|---------------|--------|
| AC (Access Control) | AC-2,3,6 | RBAC-*, SEC-8 | Tracking |
| AU (Audit) | AU-2,3,6,12 | AUDIT-*, OBS-* | Tracking |
| CA (Assessment) | CA-7 | Continuous monitoring | Tracking |
| CM (Config Mgmt) | CM-2,6,7 | GitOps, IMG-* | Implemented |
| CP (Contingtic Plan) | CP-9,10 | BACKUP-* | Tracking |
| IA (Identification) | IA-2,5 | SECRETS-*, mTLS | Partial |
| SC (Sys/Comm Prot) | SC-7,8,13 | NET-*, ENCRYPT-* | Planning |
| SI (Sys/Info Integ) | SI-2,3,4 | IMG-*, RUNTIME-* | Tracking |

---

## Global Enforcement Standards

These are the mandatory standards for all production workloads.

### Security Context (SEC)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| SEC-1 | `runAsNonRoot` | `true` | Exceptions require documented reason |
| SEC-2 | `runAsUser/runAsGroup` | Explicit UID/GID | No implicit root |
| SEC-3 | `fsGroup` | Set for PVC workloads | Ensures volume permissions |
| SEC-4 | `readOnlyRootFilesystem` | `true` | Use emptyDir for writable paths |
| SEC-5 | `allowPrivilegeEscalation` | `false` | No setuid/setgid |
| SEC-6 | `capabilities.drop` | `[ALL]` | Then add back minimums |
| SEC-7 | `seccompProfile` | `RuntimeDefault` | Syscall filtering |
| SEC-8 | `automountServiceAccountToken` | `false` | Unless K8s API access needed |

### Resource Management (RES)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| RES-1 | CPU requests | Set | Enables proper scheduling |
| RES-2 | CPU limits | Set | Prevents CPU starvation |
| RES-3 | Memory requests | Set | Enables proper scheduling |
| RES-4 | Memory limits | Set | Prevents OOM issues |
| RES-5 | emptyDir sizeLimit | Set on ALL emptyDirs | Prevents unbounded growth |

### Observability (OBS)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| OBS-1 | Logging to stdout/stderr | Yes | No file-based logs; goes to k8s → Loki |
| OBS-2 | Liveness probe | Set | Detects hung processes |
| OBS-3 | Readiness probe | Set | Controls traffic routing |
| OBS-4 | Startup probe | Set (slow apps) | Prevents premature liveness failures |
| OBS-5 | Labels: `app` | Set | Required for metrics/selection |
| OBS-6 | Labels: `component` | Set (multi-container) | Identifies container role |

### Reliability (REL)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| REL-1 | `terminationGracePeriodSeconds` | Appropriate value | 30s default often too short for DBs |
| REL-2 | PodDisruptionBudget | Set (HA apps) | Prevents simultaneous eviction |
| REL-3 | Anti-affinity | Set (multi-replica) | Spreads across nodes |

### Image Hygiene (IMG)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| IMG-1 | Pinned image tag | Yes | No `:latest` |
| IMG-2 | Fully qualified name | Yes | Include registry prefix |
| IMG-3 | `imagePullPolicy` | `IfNotPresent` | `Always` only for mutable tags |

### Timezone (TZ)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| TZ-1 | Consistent timezone | `America/Los_Angeles` or `UTC` | Per app requirements |

### Network (NET) - Future Planning

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| NET-1 | NetworkPolicy exists | Yes | Zero-trust pod traffic |
| NET-2 | Ingress rules defined | Minimal required | Only allow necessary sources |
| NET-3 | Egress rules defined | Minimal required | Only allow necessary destinations |
| NET-4 | mTLS enabled | Yes (where possible) | Encryption in transit |

> **Note**: Network policies require detailed discussion of app-to-app communication patterns. See [Network Policy Planning](#network-policy-planning) section.

### Pod Security Admission (PSA)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| PSA-1 | Namespace PSA label | `restricted` or `baseline` | Per-namespace enforcement |
| PSA-2 | PSA audit mode | `restricted` | Log violations |
| PSA-3 | PSA warn mode | `restricted` | Warn on violations |

### RBAC & Service Accounts (RBAC)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| RBAC-1 | Custom ServiceAccount | Yes (not default) | Least privilege principle |
| RBAC-2 | automountServiceAccountToken | `false` | Unless API access needed |
| RBAC-3 | Role/RoleBinding scoped | Namespace-scoped | Avoid ClusterRoles when possible |
| RBAC-4 | No wildcard permissions | Yes | Explicit resource/verb listing |

### Secrets Management (SECRETS)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| SECRETS-1 | No plaintext in manifests | Yes | Use Vault ESO or SOPS |
| SECRETS-2 | Secrets as files not env | Preferred | CIS 5.4.1 |
| SECRETS-3 | Rotation policy defined | Yes | Document rotation schedule |
| SECRETS-4 | No secrets in logs | Yes | Mask sensitive data |

### Image Security (IMG-SEC)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| IMG-SEC-1 | Vulnerability scan | Clean or accepted | Trivy/Grype |
| IMG-SEC-2 | No critical CVEs | Yes | Block critical vulns |
| IMG-SEC-3 | Image signing | Preferred | cosign/notation |
| IMG-SEC-4 | SBOM available | Preferred | Supply chain transparency |
| IMG-SEC-5 | Base image < 90 days | Yes | Keep images fresh |

### Backup & Disaster Recovery (BACKUP)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| BACKUP-1 | Velero schedule | Yes (stateful apps) | Automated backups |
| BACKUP-2 | Backup retention | Defined | Per data classification |
| BACKUP-3 | Restore tested | Yes | Documented test date |
| BACKUP-4 | RTO defined | Yes | Recovery time objective |
| BACKUP-5 | RPO defined | Yes | Recovery point objective |

### Runtime Security (RUNTIME)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| RUNTIME-1 | Falco rules | Deployed | Runtime threat detection |
| RUNTIME-2 | Security alerts | Configured | Alert on anomalies |
| RUNTIME-3 | Process monitoring | Enabled | Detect unexpected processes |

### Audit & Logging (AUDIT)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| AUDIT-1 | API server audit | Enabled | K8s control plane audit |
| AUDIT-2 | Log retention | >= 90 days | Compliance requirement |
| AUDIT-3 | Log immutability | Yes | Tamper-evident storage |
| AUDIT-4 | Centralized logging | Yes (Loki) | Aggregated analysis |

### Encryption (ENCRYPT)

| ID | Requirement | Target | Notes |
|----|-------------|--------|-------|
| ENCRYPT-1 | Secrets at rest | Encrypted | etcd encryption |
| ENCRYPT-2 | PVC encryption | Yes | Ceph RBD encryption |
| ENCRYPT-3 | Transit encryption | TLS/mTLS | Service mesh or app-level |

---

## Compliance Legend

- **Y** = Compliant
- **N** = Not compliant (needs work)
- **P** = Partial (some containers)
- **N/A** = Not applicable
- **?** = Unknown (needs audit)
- **X** = Exception documented

---

## Compliance Matrix by Namespace

### compass (DNS & NTP Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| echo-ip | geoip-update | ? | ? | ? | ? | ? | ? | Y | ? | |
| echo-ip | echo-ip | ? | ? | ? | ? | ? | ? | Y | ? | |
| librespeed-speedtest | librespeed-speedtest | ? | ? | ? | ? | ? | ? | Y | ? | Runs as root |
| netbootxyz | netbootxyz | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| openspeedtest | openspeedtest | Y (101:101) | N | ? | ? | ? | ? | Y | ? | nginx-unprivileged |

### delivery-bag (Mail Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| mailcow | multiple | ? | ? | ? | ? | ? | ? | ? | ? | Complex multi-container |

### fairy-bottle (Backup Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| urbackup-server | urbackup | ? | ? | ? | ? | ? | ? | Y | ? | |

### gossip-stone (Monitoring Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| beszel | beszel | ? | ? | ? | ? | ? | ? | Y | ? | |
| netalertx | netalertx | ? | N | ? | ? | ? | ? | Y | ? | Has NET_RAW/NET_ADMIN caps |
| speedtest-tracker | speedtest-tracker | Y (1000:1000) | N | N | Y | Y | ? | Y | Y | LSIO non-root pattern |
| speedtest-tracker | postgres | ? | ? | ? | Y | ? | ? | Y | ? | |
| umami | umami | ? | ? | ? | ? | ? | ? | Y | ? | |
| umami | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |

### gorons-bracelet (Storage Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| ceph-rgw | rgw | ? | ? | ? | ? | ? | ? | Y | ? | |
| minio | minio | ? | ? | ? | ? | ? | ? | Y | ? | |

### hookshot (RDP/Remote Control)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| guacamole | guacamole | ? | ? | ? | ? | ? | ? | Y | ? | |
| guacamole | guacd | ? | ? | ? | ? | ? | ? | Y | ? | |
| guacamole | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| rustdesk-server | rustdesk | ? | ? | ? | ? | ? | ? | Y | ? | |
| tacticalrmm | multiple (10+) | ? | ? | ? | ? | ? | ? | Y | ? | Complex multi-container |

### hyrule-castle (Business/Work Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| bagisto-demo | bagisto | ? | ? | ? | ? | ? | ? | Y | ? | |
| bagisto-demo | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| bookstack | bookstack | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| bookstack | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| calcom | calcom | ? | ? | ? | ? | ? | ? | Y | ? | |
| dolibarr | dolibarr | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| dolibarr | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| erpnext | multiple (8+) | ? | ? | ? | ? | ? | ? | Y | ? | Complex multi-container |
| invoiceninja | invoiceninja | ? | ? | ? | ? | ? | ? | Y | ? | |
| invoiceninja | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| invoiceninja | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| kimai | kimai | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| netbox | netbox | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| opnform | multiple | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| orangehrm | orangehrm | ? | ? | ? | ? | ? | ? | Y | ? | |
| orangehrm | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| osticket | osticket | X | ? | ? | ? | ? | ? | Y | ? | Apache root pattern |
| penpot | backend | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | frontend | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | exporter | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | reactive-resume | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| reactive-resume | chrome | Y (999:999) | ? | ? | ? | ? | ? | Y | ? | browserless |
| reactive-resume | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | minio | ? | ? | ? | ? | ? | ? | Y | ? | |
| semaphore | semaphore | Y (1000:1000) | N | N | ? | ? | ? | Y | ? | |
| twenty | twenty | ? | ? | ? | ? | ? | ? | Y | ? | |
| twenty | twenty-worker | ? | ? | ? | ? | ? | ? | Y | ? | |
| twenty | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| twenty | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |

### kokiri-forest (Personal/Public Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| ghost | ghost | ? | ? | ? | ? | ? | ? | Y | ? | |
| ghost | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkstack | linkstack | P | ? | ? | ? | ? | ? | Y | ? | fsGroup:101, init needs root |
| linkstack | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | shlink | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | web-client | ? | ? | ? | ? | ? | ? | Y | ? | |
| wikijs-vegan | wikijs | ? | ? | ? | ? | ? | ? | Y | ? | |
| wikijs-vegan | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |

### lens-of-truth (IDS/IPS/SIEM)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| frigate | frigate | X | ? | ? | ? | ? | ? | Y | ? | Needs device/GPU, privileged |
| home-assistant | home-assistant | X | ? | ? | ? | ? | ? | Y | ? | Needs host device access |
| mosquitto | mosquitto | ? | ? | ? | ? | ? | ? | Y | ? | |
| zigbee2mqtt | zigbee2mqtt | X | ? | ? | ? | ? | ? | Y | ? | Needs device access |

### lost-woods (Discovery & Dashboards)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| astralfocal-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| enamorafoto-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| etherealclique-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| ferdium | ferdium | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| homarr | homarr | ? | ? | ? | ? | ? | ? | Y | ? | |
| homarr | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| homelabhelpdesk-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| kai-hamilton-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| organizr | organizr | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| precisionplanit-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| sofmeright-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |
| yesimvegan-site | nginx | ? | ? | ? | ? | ? | ? | Y | ? | Custom site image |

### pedestal-of-time (Restricted/Privileged)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| actualbudget | actualbudget | Y (1000:1000) | N | ? | ? | ? | ? | Y | ? | |
| dailytxt | dailytxt | Y (101:101) | N | ? | ? | ? | ? | Y | Y | nginx ConfigMap override |
| homebox | homebox | ? | ? | ? | ? | ? | ? | Y | ? | |
| lubelogger | lubelogger | X | ? | ? | ? | ? | ? | Y | ? | Mounts /root/.aspnet |
| monica | monica | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| monica | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| paperless-ngx | paperless | ? | ? | ? | ? | ? | ? | Y | ? | |
| paperless-ngx | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| paperless-ngx | redis | ? | ? | ? | ? | ? | ? | Y | ? | |
| photoprism | photoprism | Y (2432:1000) | N | ? | ? | ? | ? | Y | Y | PHOTOPRISM_UID/GID |
| photoprism-x | photoprism | Y (2432:1000) | N | ? | ? | ? | ? | Y | Y | PHOTOPRISM_UID/GID |
| plex-ms-x | plex | ? | ? | ? | ? | ? | ? | Y | ? | |
| roundcube | roundcube | ? | ? | ? | ? | ? | ? | Y | ? | |
| roundcube | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |

### shooting-gallery (Game Servers)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| emulatorjs | emulatorjs | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| minecraft-optcp | minecraft | ? | ? | ? | ? | ? | ? | Y | ? | |
| romm | romm | X | ? | ? | ? | ? | ? | Y | ? | Known bugs #1302,#1327,#1338 |
| romm | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |

### swift-sail (Arr Apps & Downloaders)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| anirra | anirra | ? | ? | ? | ? | ? | ? | Y | ? | Custom image, unknown |
| bazarr | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| bazarr | bazarr | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| byparr | gluetun | P | N | P | Y | ? | ? | Y | Y | NET_ADMIN required |
| byparr | byparr | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | emptyDir for venv |
| downloadarrs | gluetun | P | N | P | Y | ? | ? | Y | Y | NET_ADMIN required |
| downloadarrs | qbittorrent | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | LSIO image |
| downloadarrs | radarr | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | LSIO image |
| downloadarrs | sonarr | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | LSIO image |
| downloadarrs | lidarr | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | LSIO image |
| downloadarrs | readarr | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | LSIO image |
| downloadarrs | cross-seed | Y (1000:1000) | N | ? | Y | ? | ? | Y | Y | |
| jellyseerr | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| jellyseerr | jellyseerr | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| overseerr | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| overseerr | overseerr | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| pinchflat | gluetun | P | N | P | ? | ? | ? | Y | Y | NET_ADMIN required |
| pinchflat | pinchflat | Y (3000:3141) | N | ? | ? | ? | ? | Y | Y | Already non-root |
| prowlarr | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| prowlarr | prowlarr | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| pyload-ng | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| pyload-ng | pyload-ng | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| sabnzbd | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| sabnzbd | sabnzbd | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| thelounge | gluetun | P | N | P | ? | ? | ? | Y | ? | NET_ADMIN required |
| thelounge | thelounge | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| whisparr | whisparr | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| neko-vpn | gluetun | P | N | P | ? | ? | ? | Y | Y | NET_ADMIN required |
| neko-vpn | neko | ? | ? | ? | ? | ? | ? | Y | Y | |
| py-kms | py-kms | ? | ? | ? | ? | ? | ? | Y | ? | Likely has non-root |
| supermicro-license-generator | app | Y (100:101) | N | ? | ? | ? | ? | Y | ? | Fixed image |
| vlmcsd | vlmcsd | Y (65534:65534) | N | ? | ? | ? | ? | Y | ? | nobody user |

### temple-of-time (Archival/Content Management & Media)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| appflowy | multiple (7+) | ? | ? | ? | ? | ? | ? | Y | ? | Complex multi-container |
| calibre-web | calibre-web | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image, fsGroup:1000 |
| ghost | ghost | ? | ? | ? | ? | ? | ? | Y | ? | |
| ghost | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| immich | immich | ? | ? | ? | ? | ? | ? | Y | ? | |
| jellyfin | jellyfin | ? | ? | ? | ? | ? | ? | Y | ? | |
| joplin | joplin | ? | ? | ? | ? | ? | ? | Y | ? | |
| joplin | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkwarden | linkwarden | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkwarden | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkwarden | meilisearch | X | ? | ? | ? | ? | ? | Y | ? | Non-root reverted v0.25.0 |
| mealie | mealie | X | ? | ? | ? | ? | ? | Y | ? | Uses PUID/PGID, starts root |
| mealie | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| open-webui | open-webui | ? | ? | ? | ? | ? | ? | Y | ? | |
| open-webui | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| open-webui | sentinel | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | backend | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | frontend | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | exporter | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| photoprism | photoprism | Y (2432:1000) | N | ? | ? | ? | ? | Y | Y | |
| plex | plex | ? | ? | ? | ? | ? | ? | Y | ? | |
| projectsend | projectsend | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| projectsend | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | reactive-resume | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| reactive-resume | chrome | Y (999:999) | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | minio | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | shlink | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | web-client | ? | ? | ? | ? | ? | ? | Y | ? | |
| wikijs-vegan | wikijs | ? | ? | ? | ? | ? | ? | Y | ? | |
| wikijs-vegan | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| xbackbone | xbackbone | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |

### tingle-tuner (Tools & Utilities)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| code-server | code-server | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| convertx | convertx | ? | ? | ? | ? | ? | ? | Y | ? | Unknown SQLite perms |
| draw.io | draw.io | Y (1001:999) | N | ? | ? | ? | ? | Y | ? | tomcat user |
| endlessh-go | endlessh-go | ? | ? | ? | ? | ? | ? | Y | ? | |
| faster-whisper | faster-whisper | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| filebrowser | filebrowser | ? | ? | ? | ? | ? | ? | Y | ? | |
| google-webfonts-helper | app | ? | ? | ? | ? | ? | ? | Y | ? | |
| hrconvert2 | hrconvert2 | X | ? | ? | ? | ? | ? | Y | ? | Apache needs root for 80 |
| it-tools | it-tools | Y (101:101) | N | ? | ? | ? | ? | Y | ? | nginx ConfigMap port 8080 |
| kasm | kasm | X | ? | ? | ? | ? | ? | Y | ? | Needs privileged for DinD |
| lenpaste | lenpaste | Y (1000:1000) | ? | ? | ? | ? | ? | Y | ? | |
| lenpaste | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| libretranslate | libretranslate | Y (1032:1032) | N | ? | ? | ? | ? | Y | ? | nvidia runtime |
| mazanoke | mazanoke | ? | ? | ? | ? | ? | ? | Y | ? | nginx:alpine, needs ConfigMap |
| ollama | ollama | X | ? | ? | ? | ? | ? | Y | ? | Stores data in /root/.ollama |
| openwakeword | openwakeword | X | ? | ? | ? | ? | ? | Y | ? | Root, no USER |
| piper | piper | X | ? | ? | ? | ? | ? | Y | ? | Root, no USER |
| renovate | renovate | Y (1000:1000) | ? | ? | ? | ? | N/A | Y | ? | CronJob |
| stable-diffusion-webui | sdwebui | ? | ? | ? | ? | ? | ? | Y | ? | |

### wallmaster (Bot Protection & Security)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| anubis | anubis | ? | ? | ? | ? | ? | ? | Y | ? | Multiple containers |

### zeldas-lullaby (Administrative Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| 2fauth | twofauth | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | netbox | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| oauth2-proxy | oauth2-proxy | ? | ? | ? | ? | ? | ? | Y | ? | |
| semaphore | semaphore | Y (1000:1000) | N | N | ? | ? | ? | Y | ? | |
| unifi | unifi | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| unifi | mongodb | ? | ? | ? | ? | ? | ? | Y | ? | |

---

## Compliance Summary

### Container Security (Estimated)

| Category | Compliant | Non-Compliant | Exceptions | Unknown |
|----------|-----------|---------------|------------|---------|
| SEC-1/2 (Non-root) | ~25 | ~10 | ~20 | ~65 |
| SEC-4 (ReadOnlyRoot) | ~0 | ~30 | ~0 | ~90 |
| SEC-5/6 (Caps/PrivEsc) | ~12 (gluetun) | ~10 | ~0 | ~98 |
| RES (Resources) | ~15 | ~5 | ~0 | ~100 |
| OBS-1 (Logging) | ~5 | ~0 | ~0 | ~115 |
| OBS-2/3 (Probes) | ~0 | ~0 | ~0 | ~120 |
| IMG-1/2 (Images) | ~115 | ~5 | ~0 | ~0 |
| TZ (Timezone) | ~15 | ~0 | ~0 | ~105 |

### Infrastructure Security (Estimated)

| Category | Status | Notes |
|----------|--------|-------|
| PSA Enforcement | 0% | No namespaces have PSA labels |
| Network Policies | 0% | Not implemented |
| RBAC Audit | 0% | Not audited |
| Secrets Hygiene | 80% | Vault ESO + SOPS, env vars |
| Image Scanning | 0% | No automated scanning |
| Backup Testing | 0% | No documented restore tests |
| Runtime Security | 0% | Falco not deployed |
| Audit Logging | ? | K8s API audit unknown |
| Encryption at Rest | ? | Needs verification |
| mTLS | 0% | Not implemented |

### Overall Compliance Score

| Framework | Estimated Score | Target |
|-----------|-----------------|--------|
| CIS Kubernetes Benchmark | ~30% | 80%+ |
| SOC 2 Security Principle | ~40% | 90%+ |
| NIST 800-53 (subset) | ~35% | 80%+ |

### Priority Actions (Ranked)

**Critical (Security Gaps)**:
1. Deploy Falco for runtime threat detection
2. Implement Network Policies (deny-all default)
3. Enable K8s API server audit logging
4. Verify etcd encryption at rest

**High (Compliance Gaps)**:
5. Add PSA labels to all namespaces
6. Audit all apps for unknown states (`?` cells)
7. Implement automated image vulnerability scanning
8. Document and test backup restore procedures

**Medium (Hardening)**:
9. Add health probes to all apps
10. Add resource limits to all apps
11. Standardize logging (stdout/stderr only)
12. Move secrets from env vars to files

**Low (Future Improvements)**:
13. Implement mTLS between services
14. Add image signing verification
15. Generate SBOMs for all images
16. ReadOnlyRootFilesystem for all apps

---

## Pod Security Admission by Namespace

| Namespace | Current Mode | Target Mode | Violations | Notes |
|-----------|--------------|-------------|------------|-------|
| compass | None | baseline | ? | DNS services may need NET_BIND_SERVICE |
| delivery-bag | None | baseline | ? | Mail services complex |
| fairy-bottle | None | restricted | ? | Backup agents |
| flux-system | None | restricted | ? | GitOps controllers |
| gorons-bracelet | None | baseline | ? | Storage services |
| gossip-stone | None | restricted | ? | Monitoring |
| hookshot | None | baseline | ? | Remote access services |
| hyrule-castle | None | baseline | ? | Business apps, many root exceptions |
| king-of-red-lions | None | baseline | ? | Gateway/routing |
| kokiri-forest | None | restricted | ? | Personal services |
| lens-of-truth | None | privileged | ? | IDS/IPS needs host access |
| lost-woods | None | restricted | ? | Dashboards |
| pedestal-of-time | None | privileged | ? | Privileged services by design |
| shooting-gallery | None | baseline | ? | Game servers |
| swift-sail | None | baseline | ? | VPN sidecars need NET_ADMIN |
| temple-of-time | None | restricted | ? | Media/archive |
| tingle-tuner | None | baseline | ? | Mixed utilities |
| wallmaster | None | restricted | ? | Security services |
| zeldas-lullaby | None | restricted | ? | Admin services |

**Implementation**: Add labels to namespace definitions in `fluxcd/infrastructure/namespaces/`
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

## RBAC & ServiceAccount Audit

### Cluster-Wide RBAC Status

| Item | Status | Notes |
|------|--------|-------|
| Default SA token automount | ? | Check cluster default |
| ClusterRoleBindings audit | ? | List all non-system bindings |
| Wildcard permissions | ? | Search for `*` in roles |

### Per-App ServiceAccount Status

| App | Namespace | Custom SA | automount | API Access Needed | Notes |
|-----|-----------|-----------|-----------|-------------------|-------|
| external-secrets | zeldas-lullaby | Y | Y | Y | Needs to read secrets |
| cert-manager | cert-manager | Y | Y | Y | Manages certificates |
| traefik | king-of-red-lions | Y | Y | Y | Reads ingress/routes |
| velero | fairy-bottle | Y | Y | Y | Backup controller |
| prometheus | gossip-stone | Y | Y | Y | Scrapes metrics |
| ... | ... | ? | ? | ? | Audit needed |

**Action Items**:
1. Audit all apps for ServiceAccount usage
2. Set `automountServiceAccountToken: false` where not needed
3. Create dedicated ServiceAccounts with minimal RBAC

---

## Secrets Management Audit

### Secrets Source Tracking

| App | Namespace | Secret Source | Env vs File | Rotation | Notes |
|-----|-----------|---------------|-------------|----------|-------|
| speedtest-tracker | gossip-stone | Vault ESO | Env | N/A | DB creds |
| vaultwarden | zeldas-lullaby | SOPS | File | Manual | Admin token |
| zitadel | zeldas-lullaby | SOPS | File | Manual | Master key |
| ... | ... | ? | ? | ? | Audit needed |

### Secrets Hygiene Checklist

| Check | Status | Notes |
|-------|--------|-------|
| No secrets in git (plaintext) | Y | SOPS encrypted or Vault ESO |
| No secrets in container args | ? | Audit needed |
| No secrets in ConfigMaps | ? | Audit needed |
| Secrets not logged | ? | Audit app log output |
| Vault audit logging | ? | Enable if not already |

---

## Image Security Status

### Vulnerability Scanning

| Image | Critical | High | Medium | Last Scan | Action |
|-------|----------|------|--------|-----------|--------|
| postgres:17 | ? | ? | ? | - | Scan needed |
| redis:alpine | ? | ? | ? | - | Scan needed |
| linuxserver/* | ? | ? | ? | - | Scan needed |
| ... | ? | ? | ? | - | Full inventory scan needed |

### Image Freshness

| Base Image | Current Tag | Latest | Age | Update Needed |
|------------|-------------|--------|-----|---------------|
| alpine | 3.23 | ? | ? | Check |
| debian | bookworm | ? | ? | Check |
| ubuntu | 24.04 | ? | ? | Check |

### Supply Chain Security

| Item | Status | Notes |
|------|--------|-------|
| JCR pull-through cache | Y | Reduces external dependency |
| Image signature verification | N | Not implemented |
| SBOM generation | N | Not implemented |
| Admission controller (image policy) | N | Consider Kyverno/OPA |

**Recommended Tools**:
- Trivy for vulnerability scanning
- Cosign for image signing
- Syft for SBOM generation
- Kyverno for admission policies

---

## Backup & Disaster Recovery

### Backup Schedule by App

| App | Namespace | Data Type | Velero Schedule | Last Backup | Last Restore Test | RTO | RPO |
|-----|-----------|-----------|-----------------|-------------|-------------------|-----|-----|
| vaultwarden | zeldas-lullaby | Critical | ? | ? | ? | 1h | 24h |
| paperless-ngx | pedestal-of-time | Important | ? | ? | ? | 4h | 24h |
| photoprism | temple-of-time | Important | ? | ? | ? | 4h | 24h |
| plex | temple-of-time | Media (replaceable) | ? | ? | ? | 24h | 7d |
| home-assistant | lens-of-truth | Important | ? | ? | ? | 1h | 24h |
| ... | ... | ? | ? | ? | ? | ? | ? |

### Data Classification

| Classification | RTO | RPO | Backup Frequency | Retention | Examples |
|----------------|-----|-----|------------------|-----------|----------|
| Critical | 1h | 4h | Every 4h | 90 days | Auth, secrets |
| Important | 4h | 24h | Daily | 30 days | Documents, photos |
| Standard | 24h | 7d | Weekly | 14 days | App configs |
| Replaceable | 72h | 30d | Monthly | 7 days | Cache, media |

### DR Procedures Status

| Procedure | Documented | Tested | Last Test | Notes |
|-----------|------------|--------|-----------|-------|
| Full cluster restore | N | N | - | Document needed |
| Single app restore | N | N | - | Document needed |
| Database restore | N | N | - | Document needed |
| Secrets recovery | P | N | - | SOPS keys documented |

---

## Runtime Security

### Falco Deployment Status

| Item | Status | Notes |
|------|--------|-------|
| Falco DaemonSet | N | Not deployed |
| Custom rules | N | - |
| Alert routing | N | - |
| Response automation | N | - |

### Security Monitoring Gaps

| Gap | Risk | Remediation |
|-----|------|-------------|
| No runtime detection | High | Deploy Falco |
| No file integrity monitoring | Medium | Falco or AIDE |
| No network anomaly detection | Medium | Cilium Hubble + alerts |
| No process anomaly detection | High | Falco |

### Recommended Falco Rules

```yaml
# Priority rules to implement
- Detect shell in container
- Detect package manager execution
- Detect sensitive file access
- Detect outbound connections to unusual ports
- Detect privilege escalation attempts
- Detect crypto mining
```

---

## Audit & Logging Status

### Logging Pipeline

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ Containers  │───▶│   stdout    │───▶│   Promtail  │───▶│    Loki     │
│ (apps)      │    │   stderr    │    │  (DaemonSet)│    │  (storage)  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
                                                                │
                                                                ▼
                                                         ┌─────────────┐
                                                         │   Grafana   │
                                                         │  (query/UI) │
                                                         └─────────────┘
```

### Logging Compliance Status

| Requirement | Status | Notes |
|-------------|--------|-------|
| All apps log to stdout/stderr | P | ~5 confirmed, ~115 unknown |
| Log retention >= 90 days | ? | Check Loki retention |
| Logs immutable | ? | Check storage config |
| API server audit logs | ? | Check kube-apiserver config |
| Auth events logged | ? | Check Zitadel/OAuth2-proxy |
| Security events alerting | N | Not configured |

### K8s API Server Audit

| Item | Status | Notes |
|------|--------|-------|
| Audit policy configured | ? | Check /etc/kubernetes/audit-policy.yaml |
| Audit backend (log/webhook) | ? | Check kube-apiserver flags |
| Audit log retention | ? | Check rotation config |

---

## Encryption Status

### At-Rest Encryption

| Component | Encrypted | Method | Notes |
|-----------|-----------|--------|-------|
| etcd (secrets) | ? | ? | Check encryptionConfig |
| Ceph RBD (PVCs) | ? | ? | Check Ceph config |
| Velero backups | ? | ? | Check backup encryption |

### In-Transit Encryption

| Communication Path | Encrypted | Method | Notes |
|-------------------|-----------|--------|-------|
| Client → Gateway | Y | TLS (cert-manager) | Let's Encrypt certs |
| Gateway → Services | P | Some HTTP, some HTTPS | Needs audit |
| Service → Database | ? | ? | App-dependent |
| Pod → Pod (same ns) | Y | mTLS (Istio Ambient) | All namespaces labeled |
| Pod → Pod (cross ns) | Y | mTLS (Istio Ambient) | All namespaces labeled |

**Istio Ambient Status:**
- ztunnel: Deployed
- Namespaces labeled: 18/18 (all except king-of-red-lions)
- mTLS mode: PERMISSIVE (allows both mTLS and plaintext)
- AuthorizationPolicies: Templates created, not deployed yet

### Certificate Management

| Item | Status | Notes |
|------|--------|-------|
| cert-manager deployed | Y | Let's Encrypt integration |
| Auto-renewal working | Y | Check cert-manager logs |
| Internal CA | N | Not implemented |
| mTLS (service mesh) | N | Not implemented |

---

## Network Policy Planning

> **Status**: Not yet implemented. Requires discussion of app-to-app communication patterns.

### Questions to Resolve

1. Which apps need to talk to which databases?
2. Which apps need external egress (internet access)?
3. Which apps need to communicate with each other?
4. Should VPN-routed apps (swift-sail) have different policies?
5. What about monitoring/observability traffic (Prometheus scraping)?

### Proposed Approach

1. Start with deny-all default policy per namespace
2. Explicitly allow required ingress (from Gateway/Traefik)
3. Explicitly allow required egress (DNS, specific services)
4. Document all allowed flows

### Communication Matrix (To Be Filled)

| Source App | Destination | Port | Purpose |
|------------|-------------|------|---------|
| * | kube-dns | 53 | DNS resolution |
| traefik | * (HTTPRoute targets) | varies | Ingress traffic |
| prometheus | * | varies | Metrics scraping |
| ... | ... | ... | ... |

---

## Audit Procedures

### Quick Audit (per app)

```bash
# Get security context
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.securityContext}' | jq
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.containers[*].securityContext}' | jq

# Get resources
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.containers[*].resources}' | jq

# Get probes
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.containers[*].livenessProbe}' | jq
kubectl get pod -n <ns> <pod> -o jsonpath='{.spec.containers[*].readinessProbe}' | jq

# Check if logging to files
kubectl exec -n <ns> <pod> -- ls -la /var/log/ 2>/dev/null || echo "No /var/log"
```

### Full Namespace Audit

```bash
# List all pods with their security contexts
kubectl get pods -n <ns> -o custom-columns=\
'NAME:.metadata.name,'\
'UID:.spec.securityContext.runAsUser,'\
'GID:.spec.securityContext.runAsGroup,'\
'FSGROUP:.spec.securityContext.fsGroup,'\
'READONLY:.spec.containers[0].securityContext.readOnlyRootFilesystem'
```

---

## Change Log

| Date | Changes |
|------|---------|
| 2026-02-05 | Initial manifest creation with ~120 workloads inventoried |
| 2026-02-05 | Added compliance framework mapping (CIS, SOC 2, NIST 800-53) |
| 2026-02-05 | Added PSA, RBAC, Secrets, Image Security, Backup/DR, Runtime, Audit, Encryption sections |
| 2026-02-05 | Added priority action list ranked by severity |

---

## Appendix: Implementation Checklists

### New App Onboarding Checklist

Before deploying any new app, verify:

- [ ] **SEC-1/2**: runAsNonRoot with explicit UID/GID (or documented exception)
- [ ] **SEC-5/6**: allowPrivilegeEscalation: false, capabilities drop ALL
- [ ] **SEC-8**: automountServiceAccountToken: false (unless needed)
- [ ] **RES-1-5**: CPU/memory requests and limits set
- [ ] **OBS-1**: Logs to stdout/stderr (no file logging)
- [ ] **OBS-2/3**: Liveness and readiness probes defined
- [ ] **IMG-1/2**: Pinned tag, fully qualified image name
- [ ] **SECRETS-1**: No plaintext secrets in manifests
- [ ] **BACKUP-1**: Velero schedule for stateful data
- [ ] **NET-1**: NetworkPolicy defined (when implemented)

### Namespace Security Checklist

For each namespace:

- [ ] PSA labels applied (enforce, audit, warn)
- [ ] Default deny NetworkPolicy deployed
- [ ] ServiceAccount with minimal RBAC
- [ ] Resource quotas defined
- [ ] Limit ranges defined

### Periodic Audit Checklist (Monthly)

- [ ] Review all apps with `?` status, update cells
- [ ] Run Trivy scan on all images
- [ ] Verify backup schedules running
- [ ] Test one restore procedure
- [ ] Review Falco alerts (when deployed)
- [ ] Check certificate expiration dates
- [ ] Review RBAC bindings for least privilege
- [ ] Update image tags for security patches
