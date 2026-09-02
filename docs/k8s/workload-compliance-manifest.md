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
| [Runtime Security](#runtime-security) | Detection stack (CrowdSec/Wazuh perimeter; pod-runtime pending) |
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
| 5.3.x | Network Policies | NET-* | Enforcing (ingress + egress default-deny) |
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
| SC (Sys/Comm Prot) | SC-7,8,13 | NET-*, ENCRYPT-* | Partial (NET enforced: istio ambient + Cilium ingress AND egress default-deny; ENCRYPT tracking) |
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

### Network (NET) - Implemented (istio ambient + Cilium)

Deployed as a two-layer, deny-by-default model across all app namespaces. Design specs: `fluxcd/infrastructure/configs/overlays/production/istio-policies/POLICY-SPEC.md` (identity/authz) and `.../cilium-policies/POLICY-SPEC.md` (L3/L4).

| ID | Requirement | Target | Status |
|----|-------------|--------|--------|
| NET-1 | NetworkPolicy exists | Yes | ✅ Cilium `default-deny-ingress` + CCNP contracts in every app namespace |
| NET-2 | Ingress rules defined | Minimal required | ✅ istio `default-deny` AuthorizationPolicy + explicit per-identity ALLOW rules |
| NET-3 | Egress rules defined | Minimal required | ✅ egress default-deny (`enableDefaultDeny.egress: true`) enforced in all 16 app namespaces with per-app `cnp-egress-*` allows |
| NET-4 | mTLS enabled | Yes (where possible) | ✅ istio ambient (ztunnel HBONE) — mTLS for all in-mesh traffic |

> **Verified 2026-08-14:** all 12 internet-exposed namespaces run istio ambient + `default-deny` AuthorizationPolicy + per-identity ALLOWs + Cilium `default-deny-ingress` (VALID). This is the strongest layer of the posture. Two Cilium default-deny policies were found invalid (empty `ingress: []`) and repaired to the `enableDefaultDeny` + anchor-rule shape. App-to-app authz is enforced at the istio layer (ztunnel); Cilium is L3/L4 defense-in-depth (HBONE-aware).

#### Egress default-deny campaign — COMPLETE 2026-09-01

Cilium L3/L4 egress default-deny is now enforced in **all 16 app namespaces**: `tingle-tuner, kokiri-forest, delivery-bag, compass, gossip-stone, shooting-gallery, pedestal-of-time, lost-woods, lens-of-truth, swift-sail, hookshot, temple-of-time, zeldas-lullaby, hyrule-castle, wallmaster, gerudo-crest`. Each namespace's `cnp-default-deny-ingress.yaml` now carries `enableDefaultDeny: {ingress: true, egress: true}` with a reserved-label egress anchor; per-app grants live in `cnp-egress-<app>.yaml` (inert `enableDefaultDeny: {ingress: false, egress: false}` = purely additive).

**Universal baseline (CCNPs, `endpointSelector: {}`, cover every pod):** `ccnp-allow-dns-egress` (CoreDNS :53), `ccnp-allow-istio-ambient` (in-mesh HBONE :15008 — covers app→DB and all meshed intra-cluster deps), `ccnp-allow-kube-apiserver-egress`. Per-app CNPs therefore only grant **external + non-meshed + LAN** egress.

**Rationalization tiers (per app, from what it DOES — not Hubble-derived):** no-egress · cluster-internal · DNS-only · specific RFC1918 (`toCIDR`) · specific-internet-FQDN (`toFQDNs` + paired L7-DNS rule) · documented-broad (`toEntities: world`/`world,cluster` for apps whose function is open-ended outbound — media metadata, archival/scrape, VPN tunnels, RMM/remote-desktop, LLM/AI, security CTI, admin integrations). VPN-sidecar pods (swift-sail) get `world`+`cluster` only — app traffic is inside the gluetun tunnel and invisible to Cilium.

**Gateway callback caveat:** `toEntities: cluster` does NOT match the non-meshed (`ambient=none`) cell-membrane/xylem gateway pods, so workloads reaching in-cluster services by their public URL need an explicit `toEndpoints` gateway allow (ports 443/80/15021) — same pattern as monitoring probes.

**Rollout method (per namespace):** write inert `cnp-egress-*` allows → set `PolicyAuditMode=Enabled` on all namespace endpoints (log-not-drop, survives policy regen) → commit the `egress: true` flip → watch AUDIT + exercise user-visible paths → disable audit = real enforcement. Every namespace verified with **0 egress drops**. Residual AUDIT/drops are cosmetic: cross-namespace gatus/uptime-kuma monitoring probes to app ports (pre-existing ingress artifact) and Redis-Sentinel retries to dead peer pod-IPs (live quorum rides HBONE).

### Pod Security Admission (PSA) — Enforcing

| ID | Requirement | Target | Status |
|----|-------------|--------|--------|
| PSA-1 | Namespace PSA `enforce` label | `baseline` (min) | ✅ `enforce=baseline` on 15 namespaces, `enforce=privileged` (deliberate exemption) on 7, `warn=restricted` on flux-system |
| PSA-2 | PSA audit mode | set | ✅ `audit=baseline` on most namespaces |
| PSA-3 | PSA warn mode | set | ✅ `warn=baseline` on most namespaces |

> **Verified 2026-09-01:** native PSA is enforced cluster-wide. 15 namespaces enforce `baseline`; the 7 on `enforce=privileged` are deliberate exemptions for workloads that genuinely need it — `gorons-bracelet` (rook/storage), `swift-sail` (gluetun VPN), `king-of-red-lions` (traefik/stunner gateways), `lens-of-truth` (frigate/IoT), `lakitu` (hostNetwork), `fairy-bottle` (velero/backup), `gerudo-crest` (reflector). PSA `baseline` is the admission floor; the finer-grained SEC-* hardening is enforced above it by Kyverno (below).

#### Kyverno pod-hardening — Enforcing (the SEC-* layer)

Kyverno is deployed and actively enforcing, not merely auditing. Key ClusterPolicies:

| Policy | Action | What it does |
|--------|--------|--------------|
| `enforce-pod-hardening` | **Enforce** | Blocks admission of pods violating the five SEC standards: SEC-7 seccompProfile RuntimeDefault/Localhost, SEC-6 drop ALL capabilities, SEC-3 allowPrivilegeEscalation=false, SEC-1/2 runAsNonRoot, SEC-4 readOnlyRootFilesystem — each with a per-workload exemption path |
| `audit-pod-hardening` | Audit | Same five rules in report-only mode — tracks residual violations among exempted/in-flight workloads (the SEC-4 remediation campaign) |
| `restrict-default-sa` | **Enforce** | Pods/controllers in ambient-mesh namespaces must set a non-default `serviceAccountName` (mesh identity hygiene) |
| `gate-breakglass-label` | **Enforce** | Three-gate break-glass: an exemption only holds when kube-system carries `zt.breakglass/active=true` + the workload's label + non-stale; auto-expires stale break-glass |
| `enforce-image-policy` | Audit | Image provenance/policy checks (report-only) |
| `mutate-*` (probes, SA-token, sidecar/vault/velero/stunner hardening, contract labels) | Audit/mutate | Auto-inject hardening + contract labels at admission |

`enforce-pod-hardening` matches `Pod` CREATE in ambient-mesh namespaces, excludes kyverno itself, and honors a `policy.prplanit.com/enforce-hardening: suspended` namespace kill-switch. Enforcement is at admission, so the compliant baseline lands as pods roll (existing pods grandfathered until restart).

**Fleet compliance snapshot (audit-pod-hardening PolicyReports, 2026-09-01):**

| SEC dimension | Compliant | Trend vs 2026-08-14 baseline |
|---------------|-----------|------------------------------|
| SEC-7 seccomp RuntimeDefault | ~97% | ▲ from 21% |
| SEC-6 drop ALL capabilities | ~89% | ▲ from 29% |
| SEC-3 no privilege escalation | ~85% | ▲ from 26% |
| SEC-1/2 run as non-root | ~77% | ▲ from 27% |
| SEC-4 readOnlyRootFilesystem | ~48% | ▲ from 16% — the active remaining campaign |

Query to refresh: `kubectl get policyreport -A -o json | jq -r '[.items[].results[]?|select(.policy=="audit-pod-hardening")]|group_by(.rule)[]|"\(.[0].rule): pass \([.[]|select(.result=="pass")]|length) fail \([.[]|select(.result=="fail")]|length)"'`. SEC-4 (writable-rootfs remediation via per-overlay emptyDir mounts) is the one laggard; the other four are effectively enforced fleet-wide.

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

| ID | Requirement | Target | Status |
|----|-------------|--------|--------|
| RUNTIME-1 | Perimeter/network detection | Deployed | ⚠️ Partial — CrowdSec (lens-of-truth) live at the edge: pfSense firewall log ingestion, the Cloudflare bouncer, and one Vaultwarden/Bitwarden scenario. Scaling planned |
| RUNTIME-2 | SIEM / host IDS | Deployed | ⚠️ Wazuh (lens-of-truth) deployed but not yet wired to agents/log sources — a shell today. Scaling planned |
| RUNTIME-3 | In-cluster pod-runtime detection | Enabled | ❌ Not covered — no eBPF syscall-level runtime tooling (Falco/Tetragon); CrowdSec/Wazuh cover perimeter/host, not pod runtime |

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
| librespeed-speedtest | librespeed-speedtest | X | N | Y | ? | ? | ? | Y | ? | Partial — apache-root (master root → www-data workers), :8080; drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID,NET_BIND_SERVICE] + seccomp |
| netbootxyz | netbootxyz | X | N | Y | ? | ? | ? | Y | ? | Partial — s6-overlay, binds :80 + :69 TFTP; drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID,NET_BIND_SERVICE] + seccomp |
| openspeedtest | openspeedtest | Y (101:101) | N | Y | ? | ? | ? | Y | ? | Full non-root — nginx uid 101 on :3000/3001; drop ALL + seccomp |
| adguard | adguard | X | N | Y | ? | ? | ? | Y | ? | Partial — AdGuardHome runs root throughout, binds privileged :53/:80/:443/:853/:784/:5443, DHCP disabled (no NET_RAW); drop ALL + NET_BIND_SERVICE + seccomp. HA 2/2 |
| adguardhome-sync | adguardhome-sync | X | N | Y | ? | ? | ? | Y | ? | Partial — LSIO s6-overlay, :8080; drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID] + seccomp |
| chrony | chrony | X | N | Y | ? | ? | ? | Y | ? | Partial — chronyd starts root (chowns /run/chrony, binds :123, drops to chrony user); drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID,NET_BIND_SERVICE] + seccomp; no SYS_TIME (serving-only) |

### delivery-bag (Mail Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| mailcow | multiple | ? | ? | ? | ? | ? | ? | ? | ? | Complex multi-container |

### fairy-bottle (Backup Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| urbackup-server | urbackup | X | X | Y | ? | ? | ? | Y | ? | X: uroni root backup server (stores arbitrary-owner client files) + hostNetwork → non-root/RO-root infeasible. seccomp + drop ALL / add [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID] + no-privesc. Undeployed/frozen |
| velero (repo-maintenance) | velero-repo-maintenance | Y (1000) | N | Y | ? | ? | ? | Y | ? | Full non-root via Kyverno mutate `mutate-velero-maintenance-hardening` on the `velero.io/repo-name` label (controller-generated: Velero spawns one Job per BackupRepository, PodSpec non-configurable upstream #7911 → no overlay to patch). Velero writes to two root-fs paths a non-root uid can't create — kopia config at `/udmrepo` (hardcoded) + cache at `$HOME/.cache` (HOME unset → `/.cache`); mutate injects a writable `/udmrepo` emptyDir (2Gi) + `fsGroup 1000` + `HOME=/udmrepo` (cache → `/udmrepo/.cache`), then runAsNonRoot + runAsUser/Group 1000 + allowPrivilegeEscalation:false + drop ALL + seccomp. SEC-4 (RO-fs) off — kopia writes the cache. Verified: maintenance succeeds exit 0 under uid 1000. |

### gossip-stone (Monitoring Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| beszel | beszel | Y (1000) | N | Y | ? | ? | ? | Y | ? | Full non-root — Go/distroless uid 1000, fsGroup 1000; drop ALL + seccomp |
| netalertx | netalertx | X | Y | Y | ? | ? | ? | Y | ? | X: root for raw-socket scanners (NET_RAW) + hostNetwork. seccomp + RO-root + no-privesc, drop ALL / add [NET_RAW,NET_ADMIN,NET_BIND_SERVICE]; arp-scan verified live |
| speedtest-tracker | speedtest-tracker | Y (1000:1000) | N | N | Y | Y | ? | Y | Y | LSIO non-root pattern |
| speedtest-tracker | postgres | ? | ? | ? | Y | ? | ? | Y | ? | |
| umami | umami | Y (1001) | ? | Y | ? | ? | ? | Y | ? | Hardened non-root 1001, fsGroup, drop ALL, seccomp |
| umami | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |

### gorons-bracelet (Storage Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| ceph-rgw | rgw | ? | ? | ? | ? | ? | ? | Y | ? | |
| minio | minio | ? | ? | ? | ? | ? | ? | Y | ? | |

### hookshot (RDP/Remote Control)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| boundary | controller | Y (65532:65532) | Y | Y | ? | ? | ? | Y | ? | full non-root + readOnlyRootFilesystem |
| boundary | worker | Y (65532:65532) | Y | Y | ? | ? | ? | Y | ? | full non-root + readOnlyRootFilesystem (mirrors controller) |
| guacamole | guacamole | Y (1001:1001) | N | Y | ? | ? | ? | Y | ? | full non-root (app + generate-initdb + init-db) |
| guacamole | guacd | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root |
| guacamole | postgres | Y (70:70) | N | Y | ? | ? | ? | Y | ? | full non-root |
| rustdesk-server | rustdesk (hbbs+hbbr) | Y (2000:2000) | N | Y | ? | ? | ? | Y | ? | full non-root, scratch image, all ports high |
| tacticalrmm | multiple (10+) | Y | N | Y | ? | ? | ? | Y | ? | full/partial non-root across the stack (already hardened) |

### hyrule-castle (Business/Work Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| bagisto-demo | bagisto | ? | ? | ? | ? | ? | ? | Y | ? | |
| bagisto-demo | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| bookstack | bookstack | X | X | Y | ? | ? | ? | Y | ? | Exception — LSIO/s6-overlay preinit requires root-owned /run; non-root fatal (exit 100). At Mode-A ceiling: seccomp + drop ALL + s6 caps + no-privesc |
| bookstack | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| calcom | calcom | Y (1001) | N | Y | ? | ? | ? | Y | ? | Full non-root — uid 1001, fsGroup 1001; drop ALL + seccomp; root fix-yarn-perms init (runAsNonRoot:false) |
| dolibarr | dolibarr | X | ? | ? | ? | ? | ? | Y | ? | Exception — root entrypoint (chown conf.php/install.lock); non-root needs vendor rebuild |
| dolibarr | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| erpnext | multiple (8+) | ? | ? | ? | ? | ? | ? | Y | ? | Complex multi-container |
| invoiceninja | invoiceninja | X | N | Y | ? | ? | ? | Y | ? | Partial — entrypoint chowns storage + copies assets as root (php-fpm), :9000; drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID] + seccomp. nginx sidecar non-root 101 |
| invoiceninja | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| invoiceninja | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| kimai | kimai | X | ? | ? | ? | ? | ? | Y | ? | No USER directive |
| netbox | netbox | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| opnform | multiple | Y (82) | N | Y | ? | ? | ? | Y | ? | Full non-root — api/scheduler/worker php-fpm run master directly as www-data 82 (drop ALL + seccomp, no root setuid); ingress nginx non-root 101 :8080 (RO rootfs) |
| orangehrm | orangehrm | ? | ? | ? | ? | ? | ? | Y | ? | |
| orangehrm | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| osticket | osticket | Y (1000) | Y | Y | ? | ? | ? | Y | ? | full non-root + readOnlyRootFilesystem (hlhd/osticket v1.18.4: ost-config.php symlinked to /run/osticket emptyDir; nginx+php-fpm rootless) |
| penpot | backend | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | frontend | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | exporter | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| penpot | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | reactive-resume | Y (1000) | ? | ? | ? | ? | ? | Y | ? | app container hardened non-root 1000, drop ALL, seccomp |
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
| astralfocal-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| enamorafoto-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| etherealclique-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| ferdium | ferdium | X | N | Y | ? | ? | ? | Y | ? | Partial — LSIO s6-overlay, :3000/3001; drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID] + seccomp |
| homarr | homarr | X | N | Y | ? | ? | ? | Y | ? | Partial — run.sh root supervisor (nginx master binds :80 + :7575, next-server), writes /appdata as root; drop ALL + [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID,NET_BIND_SERVICE] + seccomp |
| homarr | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| homelabhelpdesk-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| kai-hamilton-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| organizr | organizr | X | ? | ? | ? | ? | ? | Y | ? | Exception — LSIO/s6-overlay requires root init (same as bookstack) |
| precisionplanit-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| sofmeright-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |
| yesimvegan-site | nginx | Y (10001) | Y | Y | Y | Y | ? | Y | ? | Hardened non-root static-site base (uid 10001, RO rootfs, :8080) |

### pedestal-of-time (Restricted/Privileged)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| actualbudget | actualbudget | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root |
| dailytxt | dailytxt | Y (101:101) | N | Y | ? | ? | ? | Y | Y | full non-root; root init keeps CHOWN caps for its chown |
| homebox | homebox | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root |
| lubelogger | lubelogger | X | N | P | ? | ? | ? | Y | ? | /App/data root-owned 755, non-root can't write; root-partial (drop ALL + no-privesc) |
| monica | nginx | X | N | P | ? | ? | ? | Y | ? | binds :80; root-partial (drop ALL + caps + NET_BIND_SERVICE) |
| monica | monica | X | N | P | ? | ? | ? | Y | ? | php-fpm master root; root-partial (drop ALL + setuid/file caps) |
| monica | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| paperless-ngx | paperless | X | N | P | ? | ? | ? | Y | ? | s6-svscan PID 1, root→PUID; root-partial (drop ALL + s6 caps) |
| paperless-ngx | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| paperless-ngx | redis | ? | ? | ? | ? | ? | ? | Y | ? | |
| photoprism | photoprism | Y (2432:1000) | N | ? | ? | ? | ? | Y | Y | PHOTOPRISM_UID/GID |
| photoprism-x | photoprism | Y (2432:2432) | N | P | ? | ? | ? | Y | Y | full non-root; s6 needs allowPrivilegeEscalation:true; GPU via nvidia runtime |
| plex-ms-x | plex | X | X | Y | ? | ? | ? | Y | ? | plexinc s6-overlay root-required (documented); seccomp + drop ALL + s6 caps + no-privesc; NVIDIA via runtime |
| roundcube | roundcube | Y (82:82) | N | Y | ? | ? | ? | Y | ? | full non-root (fpm-nonroot image) |
| roundcube | nginx | Y (82:82) | N | Y | ? | ? | ? | Y | ? | nginx-unprivileged |
| roundcube | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |

### shooting-gallery (Game Servers)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| ark-sa | theisland | Y (7777:7777) | X | Y | ? | ? | ? | Y | ? | ASA via Proton/Wine; full non-root. SEC-4 X: Proton/steamcmd write the self-updating install + prefix across rootfs → RO-root infeasible |
| ark-sa | valguero | Y (7777:7777) | X | Y | ? | ? | ? | Y | ? | ASA via Proton/Wine; full non-root. SEC-4 X: Proton install/prefix on rootfs |
| ark-sa | admin-list nginx | X | N | P | ? | ? | ? | Y | ? | stock nginx :80; root-partial (drop ALL + caps + NET_BIND_SERVICE) |
| ark-se | theisland | X | X | N | ? | ? | ? | Y | ? | homelabhd fork (arkmanager v1.6.69, guarded install); root/sudo-required → non-root/RO-root need a rebuild. Added seccomp RuntimeDefault (the one axis it can take) |
| emulatorjs | emulatorjs | X | N | P | ? | ? | ? | Y | ? | LSIO s6 root→PUID; drop ALL + s6 caps + NET_BIND_SERVICE |
| minecraft-optcp | minecraft | Y (1000:1000) | Y | Y | ? | ? | ? | Y | ? | 5/5 — full non-root (itzg, HOME=/data PVC pre-owned 1000) + RO-root (/tmp emptyDir for JVM); verified live |
| romm | romm | X | N | P | ? | ? | ? | Y | ? | nginx+gunicorn+valkey supervisor, root-partial; Known bugs #1302,#1327,#1338 |
| romm | mysql | X | N | P | ? | ? | ? | Y | ? | LSIO mariadb s6, root-partial |

### swift-sail (Arr Apps & Downloaders)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| anirra | anirra | X | X | Y | ? | ? | ? | Y | ? | X: custom supervisord image — no baked non-root user + supervisord logs to the app dir on rootfs → non-root/RO-root need image changes. seccomp + drop ALL + no-privesc |
| bazarr | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar — root + NET_ADMIN caps, no-privesc + seccomp |
| bazarr | bazarr | X | N | P | ? | ? | ? | Y | ? | LSIO s6 root→PUID; drop ALL + s6 caps + seccomp |
| byparr | gluetun | X | N | P | Y | ? | ? | Y | Y | VPN sidecar |
| byparr | byparr | Y (1000:1000) | N | Y | Y | ? | ? | Y | Y | full non-root |
| downloadarrs | gluetun | X | N | P | Y | ? | ? | Y | Y | VPN sidecar |
| downloadarrs | qbittorrent | X | N | P | Y | ? | ? | Y | Y | LSIO s6 root→PUID |
| downloadarrs | radarr | X | N | P | Y | ? | ? | Y | Y | LSIO s6 root→PUID |
| downloadarrs | sonarr | X | N | P | Y | ? | ? | Y | Y | LSIO s6 root→PUID |
| downloadarrs | lidarr | X | N | P | Y | ? | ? | Y | Y | LSIO s6 root→PUID |
| downloadarrs | readarr | X | N | P | Y | ? | ? | Y | Y | LSIO s6 root→PUID |
| downloadarrs | cross-seed | Y (1000:1000) | N | Y | Y | ? | ? | Y | Y | full non-root |
| downloadarrs | port-manager | X | N | P | Y | ? | ? | Y | Y | start.sh root-only-executable; root-partial pending image rebuild |
| jellyseerr | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar |
| jellyseerr | jellyseerr | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root (config pre-owned 1000) |
| overseerr | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar |
| overseerr | overseerr | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root (config pre-owned 1000) |
| pinchflat | gluetun | X | N | P | ? | ? | ? | Y | Y | VPN sidecar |
| pinchflat | pinchflat | Y (3000:3141) | N | Y | ? | ? | ? | Y | Y | full non-root |
| prowlarr | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar |
| prowlarr | prowlarr | X | N | P | ? | ? | ? | Y | ? | hotio s6 root→PUID; drop ALL + s6 caps + seccomp |
| pyload-ng | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar |
| pyload-ng | pyload-ng | X | N | P | ? | ? | ? | Y | ? | LSIO s6 root→PUID; drop ALL + s6 caps + seccomp |
| sabnzbd | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar |
| sabnzbd | sabnzbd | X | N | P | ? | ? | ? | Y | ? | LSIO s6 root→PUID; init derooted to 1000 |
| thelounge | gluetun | X | N | P | ? | ? | ? | Y | ? | VPN sidecar |
| thelounge | thelounge | X | X | Y | ? | ? | ? | Y | ? | LSIO s6 root-start (not official node); config now persists on PVC (fixed mount path /var/opt/thelounge→/config). seccomp + drop ALL + CHOWN + no-privesc (Mode-A ceiling) |
| whisparr | whisparr | X | X | Y | ? | ? | ? | Y | ? | hotio s6 root-start; seccomp + drop ALL + s6 caps + NET_ADMIN + no-privesc. Undeployed/frozen |
| neko-vpn | gluetun | X | N | P | ? | ? | ? | Y | Y | VPN sidecar |
| neko-vpn | neko | X | N | P | ? | ? | ? | Y | Y | supervisord browser env, root-required partial |
| neko-gateway | stunner-daemon | X | N | ? | ? | ? | ? | Y | ? | STUNner-operator-generated pod — hardening deferred to Dataplane CR |
| py-kms | py-kms | Y (100:100) | N | Y | ? | ? | ? | Y | ? | full non-root (data pre-owned 100) |
| supermicro-license-generator | app | Y (100:100) | N | Y | ? | ? | ? | Y | ? | full non-root |
| vlmcsd | vlmcsd | Y (65534:65534) | N | ? | ? | ? | ? | Y | ? | nobody user |

### temple-of-time (Archival/Content Management & Media)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| appflowy | multiple (7+) | ? | ? | ? | ? | ? | ? | Y | ? | Complex multi-container |
| calibre-web | calibre-web | X | ? | ? | ? | ? | ? | Y | ? | Exception — LSIO/s6-overlay requires root init (same as bookstack) |
| ghost | ghost | ? | ? | ? | ? | ? | ? | Y | ? | |
| ghost | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| immich | immich | ? | ? | ? | ? | ? | ? | Y | ? | |
| jellyfin | jellyfin | ? | ? | ? | ? | ? | ? | Y | ? | |
| joplin | joplin | ? | ? | ? | ? | ? | ? | Y | ? | |
| joplin | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkwarden | linkwarden | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkwarden | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| linkwarden | meilisearch | X | ? | ? | ? | ? | ? | Y | ? | Non-root reverted v0.25.0 |
| mealie | mealie | X | ? | ? | ? | ? | ? | Y | ? | Deferred — non-LSIO PUID entrypoint; non-root needs careful in-cluster validation (docker test unreliable) |
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
| plex | plex | X | X | Y | ? | ? | ? | Y | ? | plexinc s6-overlay root-required (documented); seccomp + drop ALL + s6 caps + no-privesc; HW-transcode via /dev/dri |
| projectsend | projectsend | ? | ? | ? | ? | ? | ? | Y | ? | LSIO image |
| projectsend | mysql | ? | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | reactive-resume | Y (1000) | ? | ? | ? | ? | ? | Y | ? | app container hardened non-root 1000, drop ALL, seccomp |
| reactive-resume | chrome | Y (999:999) | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| reactive-resume | minio | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | shlink | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | mariadb | ? | ? | ? | ? | ? | ? | Y | ? | |
| shlink | web-client | ? | ? | ? | ? | ? | ? | Y | ? | |
| wikijs-vegan | wikijs | ? | ? | ? | ? | ? | ? | Y | ? | |
| wikijs-vegan | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| xbackbone | xbackbone | X | X | Y | ? | ? | ? | Y | ? | LSIO s6 root-start (:80/:443); seccomp + drop ALL + s6 caps + NET_BIND_SERVICE + no-privesc. Undeployed/frozen |

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
| ollama | ollama | Y (1000:1000) | Y | Y | ? | ? | ? | Y | ? | 5/5 — non-root (ubuntu) + seccomp + drop ALL + RO-root (~/.nv + /tmp emptyDirs). Fixed data-loss bug: PVC was at unreachable /root/.ollama, repointed to /home/ubuntu/.ollama; verified live |
| openwakeword | openwakeword | X | ? | ? | ? | ? | ? | Y | ? | Root, no USER |
| piper | piper | X | ? | ? | ? | ? | ? | Y | ? | Root, no USER |
| renovate | renovate | Y (1000:1000) | X | Y | ? | ? | N/A | Y | ? | CronJob; 4/5 — non-root + seccomp + drop ALL + no-privesc. SEC-4 X: containerbase installs language toolchains at runtime (writes /opt/containerbase) — RO-root FATALs; verified via test job |
| stable-diffusion-webui | sdwebui | X | X | P | ? | ? | ? | Y | ? | ai-dock root-start (init.sh useradd/sudoers + writes /etc,/root,/var → supervisord drops to user). Least-privilege cap set (drop ALL / add [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID,SETPCAP,KILL]) + seccomp; privEsc kept for sudoers provisioning; GPU verified |

### wallmaster (Bot Protection & Security)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| anubis | anubis | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root (Go proxy, ports 8080/9090 high) |

### zeldas-lullaby (Administrative Services)

| App | Container | SEC-1/2 | SEC-4 | SEC-5/6 | RES | OBS-1 | OBS-2/3 | IMG-1/2 | TZ | Notes |
|-----|-----------|---------|-------|---------|-----|-------|---------|---------|----|----|
| 2fauth | twofauth | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root, port 8000 |
| netbird | coturn | Y (65534) | N | Partial | ? | ? | ? | Y | ? | non-root; privesc+NET_BIND_SERVICE — turnserver has a cap_net_bind_service file capability |
| netbird | dashboard | N (root) | N | Partial | ? | ? | ? | Y | ? | supervisord+nginx:80, root-required; drop ALL + curated caps + seccomp |
| netbox | netbox | N (root) | N | Partial | ? | ? | ? | Y | ? | s6-overlay root-required (chowns /run, setuidgid-drops to PUID); drop ALL + curated caps + seccomp |
| netbox | postgres | ? | ? | ? | ? | ? | ? | Y | ? | |
| netbox | redis | Y (999:1000) | ? | ? | ? | ? | ? | Y | ? | |
| oauth2-proxy | oauth2-proxy | Y (65532:65532) | N | Y | ? | ? | ? | Y | ? | full non-root, distroless, port 4180 |
| semaphore | postgres | Y (999:999) | N | Y | ? | ? | ? | Y | ? | non-root sidecar — pgdata pre-owned 999, entrypoint skips root chown |
| semaphore | semaphore | Y (1000:1000) | N | Y | ? | ? | ? | Y | ? | full non-root (runs ansible over SSH, no in-container root needed) |
| unifi | unifi-app | N (root) | N | Partial | ? | ? | ? | Y | ? | LSIO s6-overlay root-required; drop ALL + curated caps + seccomp; import-cert init derooted |
| unifi | mongodb | Y (999:999) | N | Y | ? | ? | ? | Y | ? | non-root — /data/db pre-owned 999, entrypoint skips root gosu |

---

## Compliance Summary

### Container Security (Estimated)

_Re-estimated 2026-08-31 from an app-level scan: 74 of 111 deployed app overlays carry
`readOnlyRootFilesystem`; the remainder are documented exceptions (LSIO/s6, gluetun, ai-dock,
root-required vendor images) or external no-pod services. Counts are per deployed app, approximate._

| Category | Compliant | Non-Compliant | Exceptions | Unknown |
|----------|-----------|---------------|------------|---------|
| SEC-1/2 (Non-root) | ~68 | ~5 | ~37 | ~5 |
| SEC-4 (ReadOnlyRoot) | ~74 | ~8 | ~28 | ~5 |
| SEC-5/6 (Caps/PrivEsc) | ~85 | ~5 | ~10 | ~15 |
| RES (Resources) | ~15 | ~5 | ~0 | ~100 |
| OBS-1 (Logging) | ~5 | ~0 | ~0 | ~115 |
| OBS-2/3 (Probes) | ~0 | ~0 | ~0 | ~120 |
| IMG-1/2 (Images) | ~115 | ~5 | ~0 | ~0 |
| TZ (Timezone) | ~15 | ~0 | ~0 | ~105 |

### Infrastructure Security (Estimated)

| Category | Status | Notes |
|----------|--------|-------|
| PSA Enforcement | Enforcing | Native PSA `enforce=baseline` on 15 ns (privileged exemptions on 7); Kyverno `enforce-pod-hardening` (Enforce) applies the full SEC-* set above the baseline floor |
| Network Policies | 100% (ingress + egress) | istio ambient `default-deny` + per-identity ALLOWs AND Cilium ingress AND egress default-deny (`enableDefaultDeny.egress: true` + per-app `cnp-egress-*`) in all 16 app namespaces |
| RBAC Audit | 0% | Not audited |
| Secrets Hygiene | 80% | Vault ESO + SOPS, env vars |
| Image Scanning | 0% | No automated scanning |
| Backup Testing | 0% | No documented restore tests |
| Runtime Security | Perimeter-only | CrowdSec live at the edge (pfSense + Cloudflare bouncer + 1 Vaultwarden rule); Wazuh deployed-but-unwired; NO in-cluster pod-runtime detection (no Falco/Tetragon). Both planned to scale |
| Audit Logging | ? | K8s API audit unknown |
| Encryption at Rest | ? | Needs verification |
| mTLS | ~100% (mesh) | istio ambient (ztunnel HBONE) provides mTLS for all in-mesh traffic across app namespaces |

### Overall Compliance Score

> These estimates predate the 2026-09-01 verification of the network (ingress+egress deny) and PSA/Kyverno enforcement layers and are understated for the current state — the two strongest layers (network + pod-security admission) are now fully enforced. Re-scoring pending; the remaining drag is data-at-rest (etcd encryption), API audit logging, image vuln scanning, in-cluster pod-runtime detection, and RBAC review.

| Framework | Estimated Score | Target |
|-----------|-----------------|--------|
| CIS Kubernetes Benchmark | ~30% (understated) | 80%+ |
| SOC 2 Security Principle | ~40% (understated) | 90%+ |
| NIST 800-53 (subset) | ~35% (understated) | 80%+ |

### Priority Actions (Ranked)

> ✅ **Done since this list was written:** deny-all Network Policies (ingress + egress, all 16 app namespaces, 2026-09-01) and PSA labels + Kyverno pod-hardening enforcement (native `enforce=baseline` + `enforce-pod-hardening`). Remaining gaps below.

**Critical (Security Gaps)**:
1. Enable etcd encryption at rest (`--encryption-provider-config`) — native k8s Secrets are plaintext in etcd today (verified OFF 2026-09-01)
2. Enable K8s API server audit logging (`--audit-policy-file`) — verified OFF 2026-09-01
3. Deploy in-cluster pod-runtime detection (Falco/Tetragon) — perimeter (CrowdSec) is live, pod runtime is not

**High (Compliance Gaps)**:
4. Audit all apps for unknown states (`?` cells)
5. Implement automated image vulnerability scanning (Kyverno `enforce-image-policy` exists in Audit — pair with a scanner + move to Enforce)
6. Document and test backup restore procedures
7. RBAC audit (least-privilege review of ServiceAccounts/roles)

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
| Harbor pull-through cache | Y | `cr.pcfae.com` proxy-cache projects (docker/ghcr/quay/lscr); reduces external dependency + rate limits |
| Image signature verification | N | Not implemented |
| SBOM generation | N | Not implemented |
| Admission controller (image policy) | Partial | Kyverno deployed; `enforce-image-policy` runs in Audit — needs a scanner + move to Enforce |

**Recommended Tools**:
- Trivy for vulnerability scanning
- Cosign for image signing
- Syft for SBOM generation
- Kyverno for admission policies — ✅ deployed (pod-hardening in Enforce; image policy in Audit)

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

### Detection stack — perimeter live, pod-runtime absent

| Layer | Status | Notes |
|-------|--------|-------|
| CrowdSec (edge/behavioral) | Partial (live) | lens-of-truth: pfSense firewall log ingestion + Cloudflare bouncer + 1 Vaultwarden scenario. Scaling planned |
| Wazuh (SIEM / host IDS) | Deployed, unwired | lens-of-truth: 3 pods up, not yet connected to agents/log sources. Scaling planned |
| In-cluster pod-runtime (eBPF) | Not deployed | No Falco/Tetragon — no syscall-level runtime detection/enforcement for workloads |

### Security Monitoring Gaps

| Gap | Risk | Remediation |
|-----|------|-------------|
| No in-cluster pod-runtime detection | High | Deploy Falco or Tetragon (eBPF); CrowdSec/Wazuh cover perimeter/host, not pod runtime |
| No file integrity monitoring | Medium | Falco or AIDE |
| Network anomaly detection | Medium | Cilium Hubble deployed (flow visibility); no alerting wired |
| No process anomaly detection | High | Falco/Tetragon |
| Wazuh not ingesting | Medium | Wire agents/log sources to the deployed Wazuh stack |

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
| Security events alerting | P | CrowdSec edge alerting/response (pfSense+Cloudflare); no in-cluster workload alerting |

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

**Istio Ambient Status (verified 2026-09-02):**
- ztunnel: Deployed; HBONE mTLS for all in-mesh traffic
- Namespaces labeled `istio.io/dataplane-mode=ambient`: 21
- No PeerAuthentication resources (ambient default) — the deny-by-default posture is enforced by AuthorizationPolicies, not STRICT PeerAuth
- **AuthorizationPolicies: 417 deployed and enforcing** (`default-deny` + per-identity ALLOW across all app namespaces)

### Certificate Management

| Item | Status | Notes |
|------|--------|-------|
| cert-manager deployed | Y | Let's Encrypt integration |
| Auto-renewal working | Y | Check cert-manager logs |
| Internal CA (mesh identity) | Y | istiod issues SPIFFE workload identities for ambient mTLS |
| mTLS (service mesh) | Y | istio ambient (ztunnel HBONE) — mTLS for all in-mesh traffic |

---

## Network Policy Planning

> **Status**: Implemented (2026-09-01). Two-layer deny-by-default (istio ambient authz + Cilium L3/L4), ingress AND egress, across all 16 app namespaces. See the **Network (NET)** section above and the POLICY-SPECs (`istio-policies/POLICY-SPEC.md`, `cilium-policies/POLICY-SPEC.md`). The original planning questions are resolved as-built:

1. **App→database:** in-mesh over HBONE :15008 (universal `ccnp-allow-istio-ambient`); no per-backend egress rule needed for meshed deps.
2. **External egress:** per-app `cnp-egress-*` — `toFQDNs`/`toCIDR` where bounded, documented `toEntities: world` where open-ended.
3. **App→app:** istio per-identity ALLOWs (ingress) + Cilium `cluster` entity / explicit `toEndpoints` (egress).
4. **VPN-routed apps (swift-sail):** yes — gluetun-sidecar pods get `world`+`cluster` only; real app traffic is inside the tunnel (invisible to Cilium).
5. **Monitoring:** `ccnp-allow-prometheus-scrape` (contract, `policy.prplanit.com/metrics: "true"`) + `ccnp-allow-kubelet-probes` (universal).

### As-built Approach

1. Deny-all default (ingress + egress) per namespace via `enableDefaultDeny` + reserved-label anchors
2. Ingress: istio `default-deny` AuthorizationPolicy + per-identity ALLOWs; Cilium CCNP contracts (ingress-backend, probes, scrape)
3. Egress: universal CCNP baseline (DNS + HBONE + kube-apiserver) + per-app `cnp-egress-*`
4. Flows documented in each `cnp-egress-*` description and the POLICY-SPECs

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
| 2026-08-20 | Hardened all 8 lost-woods static sites to the non-root static-site base (uid 10001, readOnlyRootFilesystem, drop ALL, seccomp RuntimeDefault, :8080) |
| 2026-08-20 | Hardened public-facing workloads to non-root. Bucket A: netbird-relay, netbird-signal (high-port :10000), ntfy (:8080/:2525), boundary-controller, gatus, umami. Bucket B nginx frontends: erpnext-frontend (uid 1000), appflowy-nginx (101), opnform-ingress (101). Documented exceptions (root-required vendor images): netbird-dashboard (supervisord + startup auth-config injection), dolibarr-web (root entrypoint chown/install). Also moved netbird-dashboard AUTH_CLIENT_ID/AUTH_AUDIENCE off hardcoded values to secretKeyRef. |
| 2026-08-20 | Bucket C (LSIO/PUID) assessed: bookstack, calibre-web, organizr are non-root EXCEPTIONS — LSIO s6-overlay preinit fatally requires root-owned /run (confirmed via bookstack in-cluster crash, exit 100; fsGroup can't fix owner). mealie deferred (needs careful in-cluster validation). Remaining public work: high-care tier (vaultwarden, zitadel, nextcloud, mealie) + home-assistant exception. |
| 2026-08-20 | Bucket D: hardened reactive-resume-app (node, uid 1000) and jellyseerr (node uid 1000, gluetun sidecar keeps its VPN caps). Exceptions (root-required init): netbox-server (LSIO s6), plex (s6), nextcloud + orangehrm (apache root), mealie (root python init). DEFERRED to a dedicated careful session (criticality/blast-radius): vaultwarden + zitadel (auth crown jewels), netbird-management (VPN control-plane). Cleanup: removed dead netbird configmap-management.yaml (unused) + statefulset-dashboard.yaml (not in kustomization). |
| 2026-08-21 | High-care tier hardened (the deferred crown jewels): zitadel (image already uid 1000, formalized non-root + drop ALL + seccomp on init & main), vaultwarden (uid 1000, fsGroup 1000 fixes the root-written rsa_key.pem, ROCKET_PORT :8080, drop ALL — verified Ready 0 restarts), netbird-management (uid 65532, fsGroup 65532, --port 10000, drop ALL on init & main — StatefulSet r3 rolled clean; a few exit=1 restarts during the roll traced to a pre-existing SSO-dependency race, `TLS handshake timeout` fetching OIDC from sso.prplanit.com at boot, NOT the hardening). Services keep :80/public port, targetPort remapped to the high port. |
| 2026-08-21 | CORRECTION: mealie does NOT require root (earlier "root python init" note was wrong). The image's PUID/PGID root-init chown is simply skipped when the container starts as non-root — verified the server + full alembic migration set run cleanly as uid 1000. Hardened non-root (uid 1000, fsGroup 1000, drop ALL, seccomp; port 9000 already unprivileged). StatefulSet r1 rolled clean, Ready 0 restarts. |
| 2026-08-21 | Re-audited (empirically, `docker run --user`) the two lowest-confidence exceptions: BOTH confirmed genuine root-required s6 exceptions. netbox-server (`linuxserver/netbox`, LSIO): `/run/s6/basedir/bin/init: Permission denied` — same s6-overlay-v3 fatal as bookstack. plex (`plexinc/pms-docker`, official — NOT LSIO, but bundles s6-overlay v2): `s6-chown ... Operation not permitted` + `s6-setuidgid: Permission denied` (starts root → chowns cont-init → setuidgid-drops to PUID). Neither runs non-root without a vendor rebuild. Partial hardening still available staying-root: seccompProfile RuntimeDefault (safe) + curated cap drop-ALL/add-back [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID] (netbox low-risk; plex needs cap testing for /dev/dri HW-transcode + :1900 DLNA). |
| 2026-08-21 | CORRECTION + full non-root: orangehrm is NOT apache-root-required (earlier label wrong, like mealie). It's plain php:apache (docker-php-entrypoint → apache2-foreground, no s6), and its writable app dirs (src/cache,config,log; lib/confs) are already owned www-data (uid 33). Hardened to FULL non-root: runAsUser/Group/fsGroup 33, drop ALL caps (zero — no NET_BIND_SERVICE needed), seccomp, no-privesc. Apache moved off privileged :80 → :8080 via a mounted configmap (ports.conf + vhost), with /var/run/apache2 + /var/log/apache2 emptyDirs; Service targetPort 80→8080 (dropped the unused :443/ssl vhost). Verified in-cluster: uid 33, serving 302 on :8080, cell-membrane ingress already permits :8080. The only k8s blocker had been the privileged-port bind (CRI-O ignores ip_unprivileged_port_start — docker's :80 success was misleading). |
| 2026-08-21 | Extended partial-hardening (stays-root) to home-assistant + nextcloud. home-assistant (`ghcr.io/home-assistant/home-assistant`, s6-overlay): seccomp RuntimeDefault + drop ALL / add [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID] + no-privesc — CHOWN lets s6 preinit fix /run in-cluster (plain non-root fatals there); verified Ready, s6-rc all started. NET_RAW intentionally omitted (dhcp-discovery + mDNS/SSDP need hostNetwork to see the LAN, not a cap — casting works without it). nextcloud (`library/nextcloud:33.0.5-apache`, apache-root — binds :80 + entrypoint chowns /var/www/html; can't run non-root without the fpm+nginx flavor): main container seccomp + drop ALL / add [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID,NET_BIND_SERVICE] + no-privesc, cron sidecar same minus NET_BIND_SERVICE. Cap set pre-validated in docker (AH00163 + status.php 200), rolled clean across 3 replicas (maxUnavailable 1), verified serving in-cluster. Attack surface: full root caps → 6 (nextcloud) / 5 (HA). |
| 2026-08-21 | Applied FULL partial-hardening (stays-root) to all three s6 exceptions: netbox-server, plex, plex-ms-x — pod `seccompProfile: RuntimeDefault` + container `allowPrivilegeEscalation: false` + `drop:[ALL] add:[CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID]`. Cap set + no_new_privs pre-validated in docker (s6 init / first-run / HW-transcode cont-init all exit 0), then verified in-cluster: all three Ready 0 restarts, s6 `correct perms...exited 0` (was fatal under non-root). GPU intact on plex-ms-x — `nvidia-smi` returns GTX 980 Ti under the dropped caps, confirming GPU access is runtime/cgroup-based not cap-based. netbox init busybox waiters also locked to non-root 65532 + drop ALL. Attack surface cut from full root caps to 5. |
| 2026-08-21 | Gateway-sweep batch (cell-membrane + phloem routed workloads). FULL non-root: uptime-kuma (node uid 1000), ghost (node 1000), wikijs-vegan (node 1000, postgres-backed), echo-ip (Go 1000 + geoipupdate init, fsGroup for GeoIP PVC), shlink-app (RoadRunner/PHP 1001), calcom (Next.js 1001 + root fix-yarn-perms init keeping CHOWN/DAC_OVERRIDE/FOWNER), jellyfin (media, 1000 + root fix-permissions init; drop ALL — CPU transcode/ffmpeg subprocess unaffected; added fsGroupChangePolicy OnRootMismatch for the ~180k-file /config, and the root init needs explicit runAsNonRoot:false under a pod-level runAsNonRoot:true). fairer-pages: added seccomp (completes the fallback server, both gateways). linkstack: apache-root (regenerates /etc/apache2+/etc/php83 config as root, binds :443) → root+caps incl NET_BIND_SERVICE. invoiceninja: MIXED — nginx sidecar full non-root (uid 101, :8080 via full nginx.conf configmap, RO rootfs, /tmp emptyDir, drop ALL; Service targetPort→8080) + php-fpm app root+curated caps (entrypoint copies public assets/chowns storage as root) + inits hardened; verified curl / → 200 through nginx→fastcgi→app. Also: plex metadata "break" diagnosed to DNS rebinding (Unbound stripping private-IP *.plex.direct), NOT the hardening — fixed on the resolver (Unbound `private-domain: "plex.direct"`), plex securityContext retained. |
| 2026-08-21 | Root-exception tier (partial-caps, stays-root) — closes the cell-membrane/phloem sweep. LSIO/s6 + apache-root + supervisord images, each cap-set pre-validated in docker: bookstack (LSIO s6, :443 → +NET_BIND_SERVICE), calibre-web (LSIO s6, :8083), organizr (s6, :80 → +NET_BIND_SERVICE), dolibarr-web (chown-entrypoint apache, :80 → +NET_BIND_SERVICE), netbird-dashboard (supervisord, :80 → +NET_BIND_SERVICE) — all seccomp + drop ALL / add [CHOWN,DAC_OVERRIDE,FOWNER,SETUID,SETGID](+NET_BIND_SERVICE), busybox init waiters non-root 65532. Nextcloud sidecars: whiteboard (Node) FULL non-root uid 1000; talk-hpb signaling is root+su-exec (needs SETUID/SETGID — full non-root broke it with `su-exec: setgroups: Operation not permitted`), render-config init drop ALL; notify-push (Go) non-root applied but has a PRE-EXISTING crashloop (old pod 2953 restarts/8d) failing its self-test to ncloud.optcp.com — orthogonal to hardening, needs the notify_push↔nextcloud link fixed. collabora keeps its MKNOD/SYS_CHROOT sandbox caps (as-hardened-as-it-gets). Every cell-membrane + phloem workload is now non-root or partial-hardened. |
| 2026-08-31 | SEC-4 ro-rootfs tail closeout. Full 5/5: minecraft-optcp (RO-root + /tmp emptyDir), ollama (RO-root; also fixed a data-loss bug — PVC was mounted at unreachable /root/.ollama while the uid-1000 process used ephemeral /home/ubuntu/.ollama, repointed), netalertx (seccomp + RO-root + no-privesc, root kept for raw-socket scanners; arp-scan verified live). Partial/exception: stable-diffusion-webui (narrowed the ai-dock root container to a least-privilege cap set), renovate CronJob (4/5 — RO-root proven infeasible via a test job: containerbase installs toolchains to /opt at runtime), whisparr/xbackbone/urbackup-server (s6 ceiling by construction, undeployed), ark-se (+seccomp). Documented root-required exceptions: plex, plex-ms-x, ark-sa (Proton writes the self-updating install/prefix across rootfs), ark-se, anirra (custom supervisord, no baked non-root user), bookstack. thelounge fixed same PVC-path data bug + LSIO ceiling. Every deployed workload is now hardened to its ceiling or a documented exception. |

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
- [ ] **NET-1/3**: Cilium ingress + egress default-deny covered (universal CCNPs + any per-app `cnp-egress-*`)

### Namespace Security Checklist

For each namespace:

- [ ] PSA labels applied (enforce, audit, warn)
- [ ] Default deny NetworkPolicy deployed (ingress AND egress: `enableDefaultDeny: {ingress: true, egress: true}` + anchors)
- [ ] ServiceAccount with minimal RBAC
- [ ] Resource quotas defined
- [ ] Limit ranges defined

### Periodic Audit Checklist (Monthly)

- [ ] Review all apps with `?` status, update cells
- [ ] Run Trivy scan on all images
- [ ] Verify backup schedules running
- [ ] Test one restore procedure
- [ ] Review runtime/detection alerts (CrowdSec today; Falco/Tetragon when deployed)
- [ ] Check certificate expiration dates
- [ ] Review RBAC bindings for least privilege
- [ ] Update image tags for security patches
