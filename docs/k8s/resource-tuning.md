# Resource Tuning

Tuned 2026-01-10. Formula: request ~1.2x actual (4Mi multiples for mem), limit ~20% over request.

## tingle-tuner namespace

| Namespace | App | CPU Actual | CPU Request | CPU Limit | Mem Actual | Mem Request | Mem Limit | Notes |
|-----------|-----|------------|-------------|-----------|------------|-------------|-----------|-------|
| tingle-tuner | code-server | 1-47m | 2m | 50m | 44Mi | 24Mi | 48Mi | CPU spikes during active use |
| tingle-tuner | it-tools (x3) | 1m | 2m | 10m | 13Mi | 16Mi | 20Mi | |
| tingle-tuner | searxng (x3) | 1-2m | 150m | 200m | 200Mi | 256Mi | 512Mi | Needs 150m+ CPU for granian startup; 150m unstable, 140m fails |
| tingle-tuner | searxng-redis (x3) | 3-5m | 6m | 10m | 3-6Mi | 32Mi | 128Mi | |
| tingle-tuner | draw-io | 11-15m | 15m | 100m | 81Mi | 84Mi | 104Mi | Needs 100m CPU for RSA cert gen on startup (~99s at 100m, ~218s at 50m) |
| tingle-tuner | hrconvert2 | 1m | 2m | 10m | 9Mi | 12Mi | 16Mi | |
| tingle-tuner | google-webfonts-helper | 1m | 2m | 10m | 51Mi | 52Mi | 64Mi | |
| tingle-tuner | convertx | 1m | 2m | 10m | 24Mi | 64Mi | 96Mi | OOMKilled at 80Mi |
| tingle-tuner | neko-vpn/gluetun | 1m | 2m | 10m | 82Mi | 100Mi | 152Mi | VPN container |
| tingle-tuner | neko-vpn/neko | 85-92m | 102m | 500m | 488Mi | 586Mi | 1Gi | Browser workload, needs headroom |

## zeldas-lullaby namespace

| App | Rep | CPU Actual | CPU Req | CPU Lim | Mem Actual | Mem Req | Mem Lim | Notes |
|-----|-----|------------|---------|---------|------------|---------|---------|-------|
| netbird-coturn | 3 | 2-5m | 6m | 100m | 6-7Mi | 8Mi | 128Mi | TURN relay needs headroom |
| netbird-dashboard | 3 | 1-2m | 2m | 10m | 29-32Mi | 36Mi | 48Mi | |
| netbird-management | 3 | 0-1m | 2m | 10m | 22-26Mi | 32Mi | 40Mi | |
| netbird-relay | 3 | 0-1m | 2m | 10m | 2-3Mi | 12Mi | 16Mi | 8Mi failed: k8s min 12Mi for sandbox |
| netbird-signal | 3 | 0-1m | 2m | 10m | 3Mi | 12Mi | 16Mi | 8Mi failed: k8s min 12Mi for sandbox |
| zitadel | 3 | 12-15m | 60m | 200m | 82-106Mi | 128Mi | 256Mi | |
| zitadel-login-v2 | 3 | 0-1m | 2m | 50m | 68-107Mi | 100Mi | 128Mi | |
| zitadel-postgres | 3 | 15-43m | 35m | 100m | 46-175Mi | 256Mi | 512Mi | |
| vaultwarden | 3 | 1-2m | 2m | 50m | 10-18Mi | 20Mi | 64Mi | |
| vaultwarden-postgres | 3 | 8-9m | 25m | 100m | 43-82Mi | 128Mi | 256Mi | |
| vault | 3 | 23-58m | 70m | 150m | 97-251Mi | 144Mi | 256Mi | |
| vault-bank-vaults | 3 | 1m | 2m | 20m | 23Mi | 64Mi | 128Mi | sidecar |
| vault-prom-exporter | 3 | ~1m | 2m | 10m | ~16Mi | 16Mi | 32Mi | sidecar |
| netbox-server | 1 | 315m | 500m | 750m | 132Mi | 700Mi | 800Mi | OOMKilled at 600Mi |
| netbox-postgres | 1 | 20m | 2m | 50m | 31Mi | 24Mi | 64Mi | |
| netbox-redis | 1 | 15m | 20m | 50m | 3Mi | 8Mi | 16Mi | |
| oauth2-proxy | 1 | 0m | 2m | 10m | 5Mi | 12Mi | 24Mi | |
| semaphore | 1 | 1m | 2m | 100m | 27Mi | 32Mi | 64Mi | |
| semaphore-postgres | 1 | ~1m | 2m | 20m | ~24Mi | 24Mi | 64Mi | sidecar |
| twofauth | 1 | 1m | 2m | 10m | 13Mi | 48Mi | 64Mi | OOMKilled at 24Mi |
| bank-vaults-operator | 1 | 28m | 5m | 50m | 89Mi | 96Mi | 128Mi | |

**Savings:** CPU ~7.2 cores -> ~920m (87%), Memory ~11GiB -> ~2.4GiB (78%)

**Note:** Any pod requires >= 12Mi memory limit for k8s sandbox (CRI-O runtime overhead).
