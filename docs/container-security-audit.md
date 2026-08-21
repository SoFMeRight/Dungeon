# Container Security Audit

Living document tracking security posture of all containerized workloads. This is a permanent SBOM-style audit — update as apps are hardened.

## Security Criteria Checklist

| Criteria | Description | Target |
|----------|-------------|--------|
| `runAsNonRoot` | Pod cannot run as UID 0 | `true` for all apps where possible |
| `runAsUser/runAsGroup` | Explicit UID/GID set | Set for all apps where possible |
| `fsGroup` | Group ownership for mounted volumes | Set for all apps with PVCs |
| `readOnlyRootFilesystem` | Immutable root filesystem | `true` for all apps where possible |
| `allowPrivilegeEscalation` | Prevent setuid/setgid binaries | `false` for all apps |
| `capabilities.drop` | Remove unneeded Linux capabilities | `[ALL]` then add back minimums |
| `capabilities.add` | Only capabilities actually needed | Minimal set per app |
| `imagePullPolicy` | Ensure consistent image pulls | `IfNotPresent` (or `Always` for `:latest`) |
| `seccompProfile` | Syscall filtering | `RuntimeDefault` minimum |
| `resources` | CPU/memory limits set | All apps |
| Minimal images | No unnecessary tools (shells, package managers) | Flag bloated images |

## Legend

- **Y** = Implemented
- **N** = Not implemented
- **N/A** = Not applicable (legitimate reason documented)
- **P** = Partial (some containers in pod)
- **?** = Unknown / needs investigation

---

## Current Posture Snapshot (live sweep 2026-08-14)

Live measurement across 233 workloads in the 12 internet-exposed namespaces (behind the phloem + cell-membrane gateways):

| dimension | pass rate |
|-----------|-----------|
| non-root | 44% |
| no privilege-escalation | 19% |
| drop ALL caps | 22% |
| read-only root FS | 7% |
| seccomp | 17% |

**The network layer is the strong counterpart** — istio ambient + `default-deny` AuthorizationPolicy + per-identity ALLOWs + Cilium `default-deny-ingress` in every app namespace (see `k8s/workload-compliance-manifest.md` §Network and the istio/cilium `POLICY-SPEC.md`). East-west reach of a compromised pod is already gated; the remaining gap is **in-pod blast radius** — which is what this doc tracks.

### Harden exposed apps FIRST (internet-facing = highest priority)

The 52 front-ends behind the two internet-exposed gateways, prioritized. Root-required ones still get seccomp + no-privesc + drop-caps even where non-root/ro-fs can't happen.

- **Tier A — static/near-static (easy → 5/5):** astralfocal-site, enamorafoto-site, etherealclique-site, homelabhelpdesk-site, kai-hamilton-site, precisionplanit-site, sofmeright-site, yesimvegan-site *(all lost-woods — see [Custom Site Images](#custom-site-images-pending))*, linkstack, organizr.
- **Tier B — rootless-friendly (medium):** gatus, umami, uptime-kuma, boundary, calcom, jellyseerr, ghost, mealie, penpot-frontend, reactive-resume, shlink, wikijs-vegan, appflowy-nginx, netbird-*, netbox-server, **vaultwarden**, **zitadel**, ntfy, echo-ip.
- **Tier C — root-required/special (triage — see [Root Required](#root-required-cannot-change-without-upstream-fixes)):** bookstack, dolibarr, orangehrm, opnform, calibre-web, plex, nextcloud (+collabora/notify-push/talk-hpb/whiteboard), jellyfin, home-assistant.
- **Templates to copy (already ~4/5):** zitadel-login-v2, gitlab-webservice-default, osticket-app, tactical-nginx, fairer-pages, linkwarden.

**Scalable guardrail (do before the long tail):** Kyverno is installed but enforces nothing on pod security. Add a mutate policy (inject `seccompProfile: RuntimeDefault` + `allowPrivilegeEscalation: false` + `capabilities.drop:[ALL]`) fleet-wide in Audit→Enforce with per-workload exclusions — moves seccomp/privesc/caps toward ~100% by default instead of 200 hand-edits.

---

## Completed Apps

Apps that have been hardened and verified.

| App | Namespace | UID:GID | fsGroup | readOnlyRoot | noPrivEsc | capDrop | Last Audit | Notes |
|-----|-----------|---------|---------|--------------|-----------|---------|------------|-------|
| anubis | wallmaster | various | ? | ? | ? | ? | - | Multiple containers |
| wikijs-vegan | kokiri-forest | ? | ? | ? | ? | ? | - | |
| ghost | kokiri-forest | ? | ? | ? | ? | ? | - | |
| mosquitto | compass | ? | ? | ? | ? | ? | - | |
| joplin | temple-of-time | ? | ? | ? | ? | ? | - | |
| homarr (redis) | lost-woods | 999:1000 | ? | ? | ? | ? | - | |
| open-webui (redis) | tingle-tuner | 999:1000 | ? | ? | ? | ? | - | |
| twenty (redis) | hyrule-castle | 999:1000 | ? | ? | ? | ? | - | |
| penpot (redis) | hyrule-castle | 999:1000 | ? | ? | ? | ? | - | |
| netbox (redis) | hyrule-castle | 999:1000 | ? | ? | ? | ? | - | |
| invoiceninja (redis) | hyrule-castle | 999:1000 | ? | ? | ? | ? | - | |
| echo-ip | tingle-tuner | ? | ? | ? | ? | ? | - | |
| penpot (backend/frontend/exporter) | hyrule-castle | ? | ? | ? | ? | ? | - | |
| twenty (app/worker) | hyrule-castle | ? | ? | ? | ? | ? | - | |
| roundcube | delivery-bag | ? | ? | ? | ? | ? | - | |
| google-webfonts-helper | tingle-tuner | ? | ? | ? | ? | ? | - | |
| shlink | kokiri-forest | ? | ? | ? | ? | ? | - | |
| calcom | hyrule-castle | ? | ? | ? | ? | ? | - | |
| tactical-postgres | hookshot | 70:70 | 70 | N/A | Y | Y | 2026-02-06 | Alpine postgres |
| tactical-redis | hookshot | 999:999 | 999 | Y | Y | Y | 2026-02-06 | readOnlyRoot enabled |
| tactical-mongodb | hookshot | 999:999 | 999 | N | Y | Y | 2026-02-06 | Writes to /tmp, /data/configdb |
| tactical-backend | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | Init stays root (chown/rsync/su), main as UID 1000 |
| tactical-frontend | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | nginx UID 1000 |
| tactical-celery | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | Same pattern as backend main |
| tactical-celerybeat | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | Same pattern as backend main |
| tactical-websockets | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | Same pattern as backend main |
| tactical-nats | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | Already UID 1000 in image |
| tactical-meshcentral | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | wget/tar/sed in startup, TLS init hardened |
| tactical-nginx | hookshot | 1000:1000 | 1000 | N | Y | Y | 2026-02-06 | nginx UID 1000 |
| guacamole / guacd | hookshot | ? | ? | ? | ? | ? | - | |
| oauth2-proxy | zeldas-lullaby | ? | ? | ? | ? | ? | - | |
| rustdesk-server | hookshot | ? | ? | ? | ? | ? | - | |
| it-tools | tingle-tuner | 101:101 | 101 | N | ? | N | - | nginx ConfigMap override to port 8080 |
| linkwarden | temple-of-time | ? | ? | ? | ? | ? | - | |
| beszel | gossip-stone | ? | ? | ? | ? | ? | - | |
| filebrowser | tingle-tuner | ? | ? | ? | ? | ? | - | |
| homebox | temple-of-time | ? | ? | ? | ? | ? | - | |
| endlessh-go | wallmaster | ? | ? | ? | ? | ? | - | |
| lenpaste | tingle-tuner | 1000:1000 | ? | ? | ? | ? | - | |
| openspeedtest | tingle-tuner | 101:101 | ? | ? | ? | ? | - | nginx-unprivileged base |
| renovate | flux-system | 1000:1000 | ? | ? | ? | ? | - | CronJob |
| libretranslate | tingle-tuner | 1032:1032 | 1032 | N | ? | N | - | nvidia runtime |
| vlmcsd | tingle-tuner | 65534:65534 | N/A | N | ? | N | - | nobody user, simple KMS binary |
| reactive-resume (chrome) | hyrule-castle | 999:999 | ? | ? | ? | ? | - | browserless/chromium blessuser |
| supermicro-license-generator | tingle-tuner | 100:101 | ? | N | ? | N | - | Fixed image (sm-lickitung-oci v0.0.5), port 80->8080 |
| draw.io | tingle-tuner | 1001:999 | ? | N | ? | N | - | tomcat user, already non-root in image |
| semaphore | hyrule-castle | 1000:1000 | ? | N | ? | N | - | Container-level for semaphore, postgres runs as root |
| actualbudget | temple-of-time | 1000:1000 | 1000 | N | ? | N | - | |
| dailytxt | temple-of-time | 101:101 | 101 | N | ? | N | 2026-02-05 | nginx ConfigMap override, init container copies HTML to tmpfs |
| photoprism | temple-of-time | 2432:1000 | 1000 | N | ? | N | 2026-02-05 | PHOTOPRISM_UID/GID + DISABLE_CHOWN + DISABLE_TLS |
| photoprism-x | temple-of-time | 2432:1000 | 1000 | N | ? | N | 2026-02-05 | PHOTOPRISM_UID/GID + DISABLE_CHOWN + DISABLE_TLS |
| byparr | swift-sail | 1000:1000 | 1000 | N | ? | N | 2026-02-05 | UV cache/venv as emptyDir, gluetun sidecar needs caps |
| downloadarrs (cross-seed) | swift-sail | 1000:1000 | 1000 | N | ? | N | 2026-02-05 | Runs non-root |
| pinchflat | swift-sail | 3000:3141 | ? | N | ? | N | 2026-02-05 | Already non-root in image |
| speedtest-tracker | gossip-stone | 1000:1000 | 1000 | N | N | N | 2026-02-05 | LSIO non-root pattern (see below) |

---

## LSIO Non-Root Pattern

LinuxServer.io images can run as true non-root using this pattern (tested on speedtest-tracker):

```yaml
spec:
  template:
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      initContainers:
        - name: init-storage
          image: docker.io/alpine/k8s:1.34.0
          command: ["sh", "-c", "mkdir -p /storage/app/public /storage/framework/cache /storage/framework/sessions /storage/framework/views /storage/logs"]
          volumeMounts:
            - name: app-storage
              mountPath: /storage
      containers:
        - name: app
          env:
            - name: PUID
              value: "1000"
            - name: PGID
              value: "1000"
            - name: LOG_CHANNEL
              value: "stderr"  # Logs to k8s/Loki instead of files
          volumeMounts:
            - name: run
              mountPath: /run
            - name: app-storage
              mountPath: /app/www/storage
            - name: nginx-config
              mountPath: /config/nginx/site-confs/default.conf
              subPath: default.conf
      volumes:
        - name: run
          emptyDir:
            sizeLimit: 10Mi
        - name: app-storage
          emptyDir:
            sizeLimit: 50Mi
        - name: nginx-config
          configMap:
            name: app-nginx  # Override to use port 8080
```

**Key requirements:**
- `/run` emptyDir for s6 runtime (pids, sockets)
- `/app/www/storage` emptyDir with init container for Laravel dirs
- nginx ConfigMap override to listen on port 8080 instead of 80
- Service targetPort updated to 8080
- `LOG_CHANNEL=stderr` to avoid file-based logging
- `sizeLimit` on emptyDirs to prevent unbounded growth
- PUID/PGID still set (s6 recognizes but doesn't try to switch)

**Limitations:**
- Some s6 warnings about supplementary groups (harmless)
- Docker Mods won't work
- Not all LSIO images tested

---

## Gluetun Sidecars

All 12 gluetun VPN sidecars have been hardened with minimum required capabilities.

| App | Namespace | Caps Added | Last Audit |
|-----|-----------|------------|------------|
| downloadarrs | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| byparr | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| prowlarr | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| bazarr | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| sabnzbd | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| pyload-ng | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| jellyseerr | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| overseerr | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| thelounge | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| pinchflat | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| cross-seed | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |
| neko-vpn | swift-sail | NET_ADMIN,CHOWN,DAC_OVERRIDE,FOWNER,MKNOD,SETUID,SETGID | 2026-02-05 |

**Standard gluetun securityContext:**
```yaml
securityContext:
  capabilities:
    add:
      - NET_ADMIN    # iptables, routing, tun interface
      - CHOWN        # /etc/unbound ownership
      - DAC_OVERRIDE # bypass file permission checks
      - FOWNER       # bypass ownership checks
      - MKNOD        # create /dev/net/tun device node
      - SETUID       # internal privilege management
      - SETGID       # internal privilege management
    drop:
      - ALL
```

---

## Custom Site Images (Pending)

All use `cr.pcfae.com/prplanit/` nginx-based images serving static sites. Each image repo needs non-root treatment:
- Remove `user nginx;` directive
- Set pid to `/tmp/nginx.pid`
- Set temp paths to `/tmp`
- Add `LISTEN_PORT` env support
- Set `USER nginx` (UID 100:101)
- Use port 8080

Then update overlay with `runAsUser: 100, runAsGroup: 101` and containerPort 8080.

| App | Image | Status | Last Audit |
|-----|-------|--------|------------|
| astralfocal-site | cr.pcfae.com/prplanit/astralfocal.com:v0.0.2 | Pending | - |
| enamorafoto-site | cr.pcfae.com/prplanit/enamorafoto.com:v0.0.2 | Pending | - |
| etherealclique-site | cr.pcfae.com/prplanit/etherealclique.com:v0.0.2 | Pending | - |
| homelabhelpdesk-site | cr.pcfae.com/prplanit/homelabhelpdesk.com:v0.0.2 | Pending | - |
| kai-hamilton-site | cr.pcfae.com/prplanit/kai-hamilton.com:v0.0.2 | Pending | - |
| precisionplanit-site | cr.pcfae.com/prplanit/precisionplanit.com:v0.0.2 | Pending | - |
| sofmeright-site | cr.pcfae.com/prplanit/sofmeright.com:v0.0.5 | Pending | - |
| yesimvegan-site | cr.pcfae.com/prplanit/yesimvegan.com:v0.0.2 | Pending | - |
| fairer-pages | docker.io/prplanit/fairer-pages:v0.0.11 | Pending | - |

---

## LinuxServer.io Images

These use s6-overlay init system. Two approaches are supported:

**Option A: Traditional (root start, PUID/PGID drop)**
- Container starts as root, s6-overlay drops to PUID/PGID
- Simpler setup but container technically runs as root initially
- Required if using Docker Mods

**Option B: True non-root (RECOMMENDED)**
- Use `runAsUser/runAsGroup/fsGroup` in securityContext
- Keep PUID/PGID env vars (s6 recognizes but doesn't switch)
- Requires nginx ConfigMap override for port 8080
- Requires emptyDir for /run and app-specific writable paths
- See [LSIO Non-Root Pattern](#lsio-non-root-pattern) section above

| App | Namespace | Image | Mode | PUID/PGID | fsGroup | Last Audit |
|-----|-----------|-------|------|-----------|---------|------------|
| speedtest-tracker | gossip-stone | linuxserver/speedtest-tracker | B (non-root) | 1000/1000 | 1000 | 2026-02-05 |
| qbittorrent | swift-sail | linuxserver/qbittorrent | A (root→drop) | 1000/1000 | 1000 | 2026-02-05 |
| radarr | swift-sail | linuxserver/radarr | A (root→drop) | 1000/1000 | 1000 | 2026-02-05 |
| sonarr | swift-sail | linuxserver/sonarr | A (root→drop) | 1000/1000 | 1000 | 2026-02-05 |
| lidarr | swift-sail | linuxserver/lidarr | A (root→drop) | 1000/1000 | 1000 | 2026-02-05 |
| readarr | swift-sail | linuxserver/readarr | A (root→drop) | 1000/1000 | 1000 | 2026-02-05 |
| bazarr | swift-sail | linuxserver/bazarr | ? | ? | ? | - |
| bookstack | temple-of-time | linuxserver/bookstack | ? | ? | ? | - |
| calibre-web | temple-of-time | linuxserver/calibre-web | ? | ? | 1000 | - |
| code-server | tingle-tuner | linuxserver/code-server | ? | ? | ? | - |
| emulatorjs | shooting-gallery | linuxserver/emulatorjs | ? | ? | ? | - |
| ferdium | tingle-tuner | linuxserver/ferdium | ? | ? | ? | - |
| faster-whisper | tingle-tuner | linuxserver/faster-whisper | ? | ? | ? | - |
| netbootxyz | pedestal-of-time | linuxserver/netbootxyz | ? | ? | ? | - |
| organizr | lost-woods | linuxserver/organizr | ? | ? | ? | - |
| projectsend | temple-of-time | linuxserver/projectsend | ? | ? | ? | - |
| prowlarr | swift-sail | linuxserver/prowlarr | ? | ? | ? | - |
| pyload-ng | swift-sail | linuxserver/pyload-ng | ? | ? | ? | - |
| sabnzbd | swift-sail | linuxserver/sabnzbd | ? | ? | ? | - |
| thelounge | swift-sail | linuxserver/thelounge | ? | ? | ? | - |
| unifi | compass | linuxserver/unifi-network-application | ? | ? | ? | - |
| whisparr | swift-sail | linuxserver/whisparr | ? | ? | ? | - |
| xbackbone | temple-of-time | linuxserver/xbackbone | ? | ? | ? | - |

---

## TacticalRMM Documented Exceptions

| Component | Exception | Reason |
|-----------|-----------|--------|
| tactical-init (init container) | SEC-1/2 (runs as root) | Entrypoint does chown -R, rsync, su, mkdir — upstream design |
| tactical-init | SEC-6 (needs CHOWN,FOWNER,DAC_OVERRIDE,SETUID,SETGID) | Required for ownership and user switching |
| mongo:4.4 | SEC-4 (no readOnlyRoot) | Writes to /tmp, /data/configdb |
| meshcentral main | SEC-4 (no readOnlyRoot) | wget/tar/sed in startup command |
| tactical backend/celery/celerybeat/websockets | SEC-4 (no readOnlyRoot) | Write to /opt/tactical |
| tactical-frontend | SEC-4 (no readOnlyRoot) | nginx writes to /var/cache/nginx, /var/run |
| tactical-nginx | SEC-4 (no readOnlyRoot) | nginx writes to /var/cache/nginx, /var/run |
| tactical-postgres | SEC-4 (no readOnlyRoot) | Writes to PGDATA |
| tactical-nats | SEC-4 (no readOnlyRoot) | Writes to /opt/tactical |

---

## Root Required (Cannot Change Without Upstream Fixes)

These apps require root for legitimate technical reasons.

| App | Namespace | Image | Reason | Last Audit |
|-----|-----------|-------|--------|------------|
| ollama | tingle-tuner | ollama/ollama | Stores data in /root/.ollama | - |
| romm | temple-of-time | rommapp/romm | Known bugs (#1302, #1327, #1338, #2432) | - |
| lubelogger | temple-of-time | hargata/lubelogger | Mounts /root/.aspnet/DataProtection-Keys | - |
| jellyseerr | swift-sail | fallenbagel/jellyseerr | Root (UID 0), no USER directive | - |
| overseerr | swift-sail | sctx/overseerr | Root (UID 0), no USER directive | - |
| mealie | temple-of-time | hkotel/mealie | Uses PUID/PGID mechanism, starts as root | - |
| home-assistant | pedestal-of-time | homeassistant/home-assistant | Needs host access for devices | - |
| zigbee2mqtt | pedestal-of-time | koenkk/zigbee2mqtt | Needs device access | - |
| frigate | lens-of-truth | blakeblackshear/frigate | Needs device/GPU access, privileged | - |
| kasm | tingle-tuner | kasmweb/core | Needs privileged for DinD | - |
| osticket | hyrule-castle | osticket/osticket | No USER, Apache root pattern | - |
| dolibarr | hyrule-castle | dolibarr/dolibarr | No USER directive | - |
| kimai | hyrule-castle | kimai/kimai2 | No USER directive | - |
| monica | hyrule-castle | monica | No USER directive | - |
| opnform | hyrule-castle | opnform | Complex multi-container, no USER | - |
| hrconvert2 | tingle-tuner | zelon88/hrconvert2 | Apache needs root to bind port 80 | - |
| piper | pedestal-of-time | rhasspy/wyoming-piper | Root, no USER | - |
| openwakeword | pedestal-of-time | rhasspy/wyoming-openwakeword | Root, no USER | - |
| reactive-resume (app) | hyrule-castle | amruthpillai/reactive-resume | No USER, untested upstream | - |
| meilisearch | temple-of-time | getmeili/meilisearch | Non-root reverted in v0.25.0 | - |

---

## Needs Investigation

Apps requiring further research before hardening.

| App | Namespace | Image | Notes | Last Audit |
|-----|-----------|-------|-------|------------|
| anirra | swift-sail | jpyles0524/anirra | Custom image, no public docs, UID unknown | - |
| convertx | tingle-tuner | c4illin/convertx | No USER, uncertain with SQLite permissions | - |
| mazanoke | tingle-tuner | civilblur/mazanoke | nginx:alpine port 80, needs ConfigMap override | - |
| py-kms | tingle-tuner | py-kms-organization/py-kms | Likely has non-root user, UID unknown | - |
| librespeed-speedtest | tingle-tuner | librespeed/speedtest | Maintainers say unprivileged, runs as root | - |
| netalertx | gossip-stone | jokob-sk/netalertx | Has fsGroup: 20211 + NET_RAW/NET_ADMIN caps, complex | - |
| linkstack | kokiri-forest | linkstackorg/linkstack | Partial: fsGroup: 101, Apache on 8080, init needs root | - |

---

## Post-Postgres-Upgrade

After upgrading Debian postgres images to `postgres:18.1-alpine3.23`, add:
```yaml
securityContext:
  runAsUser: 70
  runAsGroup: 70
  fsGroup: 70
```
(Alpine postgres UID is 70)

See postgres upgrade plan at `~/.claude/plans/goofy-baking-shamir.md`.

---

## Database Workload Hardening (per-engine recipe)

The ~72 database/cache workloads (redis, postgres, mariadb, mongo) are the highest-leverage
hardening target: they run a handful of shared upstream images, so a per-engine recipe
hardens many workloads at once. Every DB splits into two delivery populations:

- **Operator-managed** — the CRD carries the securityContext. `mariadb.spec` and
  `redisreplication.spec` / `redissentinel.spec` each expose **both** `podSecurityContext`
  (pod-level) and `securityContext` (container-level), so no operator fork is needed. **CNPG
  postgres self-hardens to full 5/5 already** (`ownerRef: Cluster`, ~15 workloads — nothing to do).
- **Plain StatefulSets/Deployments** — hand-written manifests, edit the overlay patch (or base)
  directly.

### Recipe: plain redis — full 5/5

Official redis/valkey writes only to `/data` (the PVC), so `readOnlyRootFilesystem` needs **no**
emptyDir. Keep the workload's existing uid/gid.
```yaml
# pod securityContext:   runAsNonRoot: true; seccompProfile: {type: RuntimeDefault}   (+ existing runAsUser/Group/fsGroup)
# redis container securityContext:
#   allowPrivilegeEscalation: false
#   readOnlyRootFilesystem: true
#   capabilities: {drop: [ALL]}
```

### Recipe: plain postgres — full 5/5

Postgres writes PGDATA to the PVC, but under a read-only rootfs it also needs the unix-socket
dir and scratch space as emptyDirs. uid is image-specific: **alpine = 70, debian/official = 999**.
```yaml
# pod securityContext:   runAsUser/Group/fsGroup: <70|999>; runAsNonRoot: true; seccompProfile: {type: RuntimeDefault}
# postgres container securityContext:  allowPrivilegeEscalation: false; readOnlyRootFilesystem: true; capabilities: {drop: [ALL]}
# extra volumeMounts + emptyDir volumes:
#   - /var/run/postgresql   (unix socket)   -> emptyDir
#   - /tmp                  (scratch)        -> emptyDir
```
Harmless startup warning `chmod: /var/run/postgresql: Operation not permitted` — the entrypoint
can't chmod the emptyDir as non-root, but postgres still creates the socket there and starts
normally. Do not try to suppress it.

### Documented exception: operator redis (opstree) caps at 4/5

`quay.io/opstree/redis[-sentinel]` writes `/etc/redis/redis.conf` **and** its PID file to the
**rootfs**, and the operator exposes no emptyDir for those paths, so `readOnlyRootFilesystem: true`
crash-loops it (`/etc/redis/redis.conf: Read-only file system`, `Failed to write PID file`).
Apply the other four dimensions only (`securityContext: {allowPrivilegeEscalation: false,
capabilities: {drop: [ALL]}}` + `podSecurityContext.runAsNonRoot: true`; seccomp already present).
**RO-rootfs is N/A here — this is an upstream-image constraint, not a gap.**

### Rollout status (2026-08-21)

| Engine / population | Target | Status |
|---|---|---|
| Postgres — CNPG (`ownerRef: Cluster`) | 5/5 | **Done** (self-hardened, ~15) |
| Redis — plain (official image) | 5/5 | **Done** — 9 workloads (netbox, erpnext cache+queue, invoiceninja, appflowy, paperless, penpot, opnform, searxng) |
| Redis — operator (opstree) | 4/5 (RO N/A) | **Done** — 8 CRs (homarr, nextcloud, gitlab, zitadel × RedisReplication+RedisSentinel) |
| Postgres — plain | 5/5 | **Done** — 13 workloads: 7 alpine (umami, guacamole, paperless, reactive-resume, wikijs-vegan, netbox, tactical) + 5 debian (linkwarden, mealie, joplin, penpot, opnform) at full 5/5; speedtest-tracker's postgres container is 5/5 but the pod keeps a root `init-permissions` chown-init (documented exception — postgres needs the data dir chowned + chmod 700, so the pod can't be fully non-root). uid: alpine 70, debian 999. |
| MariaDB — plain (~16) + galera CRs | 5/5 / TBD | **Pending** — galera already pod-level (999+seccomp); RO needs `/run/mysqld` + `/tmp` emptyDirs (highest risk: entrypoint init/chown) |
| Redis — harbor (Helm), immich/semaphore (multi-container) | — | **Deferred** — harbor via chart values; multi-ctr pods need per-container review |

Notes: seccomp is also auto-injected fleet-wide on next roll by the `mutate-pod-hardening`
Kyverno policy; the DB recipe carries it explicitly so the posture is visible in git. When an
operator-managed pod crash-loops on a bad securityContext, the `apps`/phase kustomization
health-gates and won't advance to the fix revision — break the deadlock by `kubectl patch`-ing
the live CR to remove the bad field, then `kubectl delete pod` so the StatefulSet recreates from
the corrected template (git stays source-of-truth; the patch only matches the fix commit).

---

## Hardening Phases

### Phase 1: Non-root where possible (In Progress)
- [x] Gluetun sidecars: minimum capabilities with drop ALL (12 apps)
- [x] dailytxt: nginx non-root with ConfigMap
- [x] photoprism/photoprism-x: runAsUser 2432
- [x] byparr: runAsUser 1000 with emptyDir for venv
- [x] downloadarrs: StatefulSet with fsGroup 1000
- [ ] All LSIO images: verify PUID/PGID set
- [ ] Custom site images: fix nginx configs

### Phase 2: Read-only root filesystem
- [ ] Audit all apps for writable paths
- [ ] Add emptyDir mounts for /tmp, /var/run, app-specific paths
- [ ] Enable `readOnlyRootFilesystem: true`

### Phase 3: Privilege escalation prevention
- [ ] Add `allowPrivilegeEscalation: false` to all containers
- [ ] Audit for setuid/setgid binaries in images

### Phase 4: Seccomp profiles
- [ ] Enable RuntimeDefault seccomp profile cluster-wide
- [ ] Create custom profiles for apps needing specific syscalls

### Phase 5: Minimal images
- [ ] Flag images with unnecessary tools (shells, package managers)
- [ ] Consider distroless alternatives where available

---

## Audit Log

| Date | Auditor | Changes |
|------|---------|---------|
| 2026-02-05 | Claude | Initial audit creation, gluetun caps (12 apps), downloadarrs→StatefulSet, byparr non-root, photoprism non-root, dailytxt non-root, TZ fix to America/Los_Angeles |
| 2026-02-05 | Claude | speedtest-tracker LSIO non-root pattern (pioneer), updated LSIO section with Mode column, created workload-compliance-manifest.md |
| 2026-02-06 | Claude | TacticalRMM full hardening: all 11 components in hookshot namespace (SEC-1 through SEC-8). Redis/MongoDB init chown removed (fsGroup handles ownership), wait-for-* init containers hardened as nobody, tactical-init documented exception for root with minimal caps |
| 2026-08-14 | Claude | Live posture sweep (233 workloads, 12 exposed namespaces): non-root 44% / no-privesc 19% / drop-caps 22% / ro-fs 7% / seccomp 17%. Added Current Posture Snapshot + exposed-first priority (52 front-ends, tiered). Network layer verified strong (istio ambient + Cilium default-deny everywhere) and corrected the stale "0%/Planning" NET entries in workload-compliance-manifest.md. Repaired 2 invalid Cilium default-deny-ingress policies (temple-of-time, hyrule-castle → VALID). |
| 2026-08-21 | Claude | Database-workload hardening pass (see Database Workload Hardening section). Redis: 9 plain redis → 5/5, 8 opstree operator CRs → 4/5 (RO-rootfs N/A — image writes conf+PID to rootfs). Postgres: all 13 plain-postgres → 5/5 (socket/tmp emptyDirs; alpine uid 70, debian uid 999; speedtest-tracker keeps a root chown-init exception); CNPG already 5/5. Established per-engine recipes + operator-vs-plain split. Zitadel SSO redis rolled clean (no repeat of the master-label incident). |

## Related Documents

- **[Workload Compliance Manifest](workload-compliance-manifest.md)** - Comprehensive tracking of all ~120 workloads against all production standards (security, resources, observability, reliability, images, network)
