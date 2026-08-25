# HASteward operation Jobs

Named, permanent templates for running a HASteward recovery/maintenance operation as a
one-shot Kubernetes Job — the GitOps-native replacement for hand-edited scratch YAML.

The ServiceAccount, ClusterRole, and ClusterRoleBinding are flux-managed in
[`../rbac.yaml`](../rbac.yaml). These Job templates are **not** in any kustomization on
purpose — they are operational runbooks applied on demand, never reconciled.

## Run one

```sh
# ALWAYS triage first — read-only diagnosis.
./run.sh triage           -c nextcloud-postgres -n temple-of-time

# Disk-full deadlock: replay + recycle WAL in place, then settle the primary back.
./run.sh deadlock-recover -c nextcloud-postgres -n temple-of-time -i 2

# Re-clone/heal one unhealthy instance from the primary (requires a running primary).
./run.sh repair           -c osticket-mariadb    -n hyrule-castle  -i 1 -e galera

# Promote the authority when it is not the primary (leader-not-primary / diverged).
./run.sh promote          -c some-postgres       -n some-ns        -i 3
```

Flags: `-c` cluster (required), `-n` namespace (required), `-i` instance, `-e` engine
(`cnpg` default, or `galera`), `--image` (default `docker.io/prplanit/hasteward:latest-dev`).

Each run gets a unique Job name via `generateName`. Follow it:

```sh
kubectl -n fairy-bottle get jobs -l hasteward.prplanit.com/target=<cluster>
kubectl -n fairy-bottle logs -f job/<printed-name>
```

## Verbs

| Verb | Command | Escrow | Notes |
|------|---------|--------|-------|
| `triage` | `triage` | — | Read-only. Run first; trust `safeToHeal`/`mostAdvanced`. |
| `deadlock-recover` | `prune-wal --deadlock-recover -i N` | VolumeSnapshot | In-place WAL replay+recycle for a disk-full-DEADLOCKED instance, then settles the primary (cancels a stuck failover). No PVC growth. |
| `repair` | `repair -i N` | restic | Re-clone/heal an unhealthy instance from the primary. |
| `promote` | `repair -i N --promote` | restic | Rebuild-around-authority when the authority is not the primary. `--dry-run` first (edit args). |

`deadlock-recover` escrows via a CSI VolumeSnapshot (no backups PVC needed); `repair` /
`promote` escrow to the restic repo on the `hasteward-backups` PVC using `RESTIC_PASSWORD`
from the `hasteward-restic` secret.
