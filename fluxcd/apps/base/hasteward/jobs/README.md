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
(`cnpg` default, or `galera`), `--image` (default `docker.io/prplanit/hasteward:latest-dev`),
`-f`/`--force` (`repair` and `promote` only).

### Which image actually ran

`latest-dev` moves, so the submitted Job is pinned to a **digest**: `run.sh` resolves the
tag against the registry and substitutes `name@sha256:...`, with
`imagePullPolicy: IfNotPresent`. Two consequences worth knowing:

- **What ran is recoverable after the fact.** The digest is in the Job spec, so
  `kubectl -n fairy-bottle get job/<name> -o jsonpath='{.spec.template.spec.containers[0].image}'`
  answers "which build produced this diagnosis" months later. It also prints whether the
  digest changed since the previous run.
- **A registry outage degrades instead of blocking.** Resolution happens on the operator's
  machine, not in the kubelet, so an unreachable or rate-limited registry is visible at
  submit time. It then submits the bare tag and the node's **cached layer runs** — with a
  warning, because that may be old code and will not start at all on a node that has never
  pulled it. Verify with the jsonpath above before trusting a result. `Always` would
  instead leave the Job in `ErrImagePull`, which is the wrong failure for a tool you reach
  for while the cluster is unhealthy.

A tag the registry answers for but does not have is a **refusal**, not a fallback — a typo
in `--image` must not silently run some other cached image.

### `--force`, and how to earn it

Triage returns `safeToHeal: false` with `recommendedDonor: none` when authority is
**ambiguous** — committed WAL exists on more than one lineage past a shared fork. HASteward
refuses there on purpose: choosing the surviving lineage is unrecoverable, so it is a human's
call. `--force` is how that decision is handed back once it has been made.

Decide it on **content, not WAL volume**. The "N GB past fork" figure is LSN distance, so an
idle branch still accrues it from checkpoints and heartbeats. Snapshot the losing instance's
PVC (`VolumeSnapshotClass csi-rbdplugin-snapclass`), restore it to a scratch PVC, open it as a
standalone server — delete `standby.signal`, `chmod 0750` the pgdata, start with
`-c ssl=off -c archive_mode=off -c listen_addresses='' -c logging_collector=off` — and diff real
`count(*)` per table against the primary. `pg_stat_user_tables.n_live_tup` is useless here; a
recovered clone has reset statistics. Then force toward the branch you proved.

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
| `repair` | `repair -i N` | restic | Re-clone/heal an unhealthy instance from the primary. Accepts `-f`. |
| `promote` | `repair -i N --promote` | restic | Rebuild-around-authority when the authority is not the primary. `--dry-run` first (edit args). Accepts `-f`. |

`deadlock-recover` escrows via a CSI VolumeSnapshot (no backups PVC needed); `repair` /
`promote` escrow to the restic repo on the `hasteward-backups` PVC using `RESTIC_PASSWORD`
from the `hasteward-restic` secret.
