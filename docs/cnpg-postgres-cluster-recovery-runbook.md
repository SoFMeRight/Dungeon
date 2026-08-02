# CloudNativePG Cluster Recovery After a Node / Power Outage (HASteward)

## Overview

After a mass node event — Proxmox VE updates, power loss, an unclean reboot of
multiple workers — CloudNativePG (`cnpg`) Postgres clusters frequently come back
**wedged**, reporting phases that are *misleading about the actual problem*. This
runbook covers how to diagnose them correctly with **HASteward** and heal them by
re-cloning the bad replicas from the canonical primary — **without** wrongly
expanding PVCs or risking data.

> Engine here is CloudNativePG. HASteward also handles Galera/MariaDB (`-e galera`).

## The misleading signals (and what they really mean)

| Cluster phase / pod state | What it usually actually is |
|---|---|
| `Not enough disk space` | **Often FALSE.** A stuck or diverged replica makes CNPG's `ensure_sufficient_disk_space` check misfire. The DB may be tiny with 95%+ free. |
| `Instance Status Extraction Error: HTTP communication issue` | The operator can't reach the instance managers — usually ambient-mesh enrollment gaps after reboot, or instances cycling. |
| `Waiting for the instances to become active` | Replicas haven't reached a consistent state (stuck startup / behind). |
| Replica `CrashLoopBackOff` or `FATAL: the database system is starting up` | Replica can't complete recovery — needs a re-clone if it diverged or lost WAL. |

**Key principle:** trust HASteward `triage`, not the CNPG phase string. Triage
reports the **canonical primary** (`dataComparison.mostAdvanced`) and whether the
cluster is **`safeToHeal`**. If `safeToHeal: true` and the *primary* (not a
replica) holds the most recent timeline/LSN, re-cloning the unhealthy replicas
from it is safe and lossless.

## Step 0 — Confirm it is NOT actually disk-full (do not blind-expand)

Before expanding any PVC, verify real usage from a reachable instance:

```bash
kubectl -n <ns> exec <cluster>-<n> -c postgres -- bash -c \
  'df -h /var/lib/postgresql/data; \
   du -sh /var/lib/postgresql/data/pgdata/base /var/lib/postgresql/data/pgdata/pg_wal'
```

- `base` = real data, `pg_wal` = WAL.
- If `base` is small but `pg_wal` is large (or the volume shows lots free yet CNPG
  says "Not enough disk space") → it's **WAL accumulation from a stuck/diverged
  replica**, not real fullness. **Do not expand the PVC** — re-clone instead.
- Expanding a falsely-"full" cluster wastes Ceph capacity and fixes nothing.

## Step 1 — Triage (read-only, always first)

HASteward runs as a one-shot container against the cluster via your kubeconfig:

```bash
docker run --rm --network host \
  -e KUBECONFIG=/kube/config \
  -v "$HOME/.kube:/kube:ro" \
  prplanit/hasteward:latest \
  triage -e cnpg -c <cluster> -n <ns>          # add --output json for scripting
```

Read from the output:
- `dataComparison.safeToHeal` — must be `true` to proceed.
- `dataComparison.mostAdvanced` — the canonical primary. **It must be the primary**,
  not a replica.
- per-instance `needsHeal`, `timeline`, `lsn`, `notes`, `recommendation`.

A `0/3 ready` count does **not** necessarily mean the primary is gone — triage can
still read the primary's data and name it canonical. `safeToHeal: true` is the gate.

### Sweep all clusters at once

```bash
for nc in <ns>/<cluster> <ns>/<cluster> ...; do
  ns="${nc%%/*}"; c="${nc##*/}"
  docker run --rm --network host -e KUBECONFIG=/kube/config -v "$HOME/.kube:/kube:ro" \
    prplanit/hasteward:latest triage -e cnpg -c "$c" -n "$ns" --output json
done
```

## Step 2 — Repair (re-clone unhealthy replicas from the canonical primary)

Only when **`safeToHeal: true`** and the **primary** is `mostAdvanced`:

```bash
docker run --rm --network host \
  -e KUBECONFIG=/kube/config \
  -v "$HOME/.kube:/kube:ro" \
  prplanit/hasteward:latest \
  repair -e cnpg -c <cluster> -n <ns> --instance <N> [--force] [--no-escrow]
```

- **Escrow:** by default repair takes a pre-repair backup and wants
  `--backups-path <restic-repo>`. Use `--no-escrow` only when the primary is
  canonical and the replica's data is being discarded anyway (it usually is, on a
  re-clone). Otherwise pass the restic repo (see `ContainerUsage.md` in HASteward).
- **`--force`:** needed when a replica is on the *same* timeline as the primary but
  stuck. HASteward conservatively skips it otherwise — you'll see `success: true`
  with `healedInstances: null` and the replica unchanged. `--force` makes it
  re-clone anyway (safe when `safeToHeal: true`).
- Repeat per unhealthy instance.

Verify:

```bash
kubectl -n <ns> get cluster <cluster> \
  -o jsonpath='{.status.phase} {.status.readyInstances}/{.status.instances}{"\n"}'
# want: "Cluster in healthy state" 3/3
```

## Critical safety rules

- **STOP if `safeToHeal` is false, or if `mostAdvanced` is a *replica* / split-brain
  is reported.** Re-cloning then would overwrite the newest data. Investigate first;
  you may need to promote the most-advanced instance before healing the rest.
- Restarting the **CNPG operator alone does not fix a stuck/diverged replica** — it
  clears operator state but the replica still needs the re-clone.
- **Image-pull trap:** HASteward is itself `prplanit/hasteward`. During a registry
  outage or Docker Hub rate-limit event, run it from a host that already has the
  image cached (or local docker), or it will stall pulling *itself*.
- These false phases often coincide with an **ambient-mesh enrollment gap** after a
  reboot (the operator can't reach instance managers — `connection reset`/`refused`
  on `:8000`/`:15008`). The re-clone fixes the wedged cluster; the broader mesh gap
  is fixed by re-enrolling rescheduled pods (restart `istio-cni-node`, then bounce
  the affected pods).

## Worked example — 2026-06-07 outage

Trigger: Proxmox VE updates + a DNS/internet/cert outage rebooted the worker VMs.
Pods mass-rescheduled; **10 CNPG clusters** came back wedged.

`harbor-postgres` reported `Not enough disk space` (1/3), but **Step 0 proved it
false**: `df` showed 20G / 650M used / **19G free (4%)**, `base` 73M, `pg_wal` 577M
— a ~70MB database. Triage: `safeToHeal: true`, primary `harbor-postgres-3`
canonical (timeline 21); `harbor-postgres-1` had **diverged** (timeline 19 < 21)
with WAL accumulation, `harbor-postgres-2` was crash-looping behind by LSN.

Fix:

```bash
# instance 1: diverged → straight re-clone
repair -e cnpg -c harbor-postgres -n hyrule-castle --instance 1 --no-escrow
# instance 2: same timeline but stuck → needed --force (first attempt no-op'd)
repair -e cnpg -c harbor-postgres -n hyrule-castle --instance 2 --force --no-escrow
# result: "Cluster in healthy state" 3/3
```

A triage sweep of the remaining clusters confirmed **all `safeToHeal: true`** with a
canonical primary, all recoverable by the same procedure:

```
CLUSTER                            READY  safeHeal  canonical-primary
gossip-stone/grafana-postgres      3/3    true      grafana-postgres-3 (tl4)
hookshot/boundary-postgres         2/3    true      boundary-postgres-1 (tl3)
hyrule-castle/calcom-postgres      0/3    true      calcom-postgres-3 (tl17)
hyrule-castle/gitlab-postgresql    2/3    true      gitlab-postgresql-3 (tl12)
lost-woods/homarr-postgres         2/3    true      homarr-postgres-1 (tl7)
temple-of-time/appflowy-postgres   2/3    true      appflowy-postgres-2 (tl25)
temple-of-time/nextcloud-postgres  1/3    true      nextcloud-postgres-3 (tl7)
temple-of-time/open-webui-postgres 1/3    true      open-webui-postgres-1 (tl30)
zeldas-lullaby/zitadel-postgres    2/3    true      zitadel-postgres-2 (tl52)
```

> Note: the disk-full and "HTTP communication issue" phases were the *same*
> false-cascade. None of these clusters were actually out of disk.

## Related

- [PV/PVC Recovery Guide](pv-pvc-recovery-guide.md)
- [StatefulSet Standards](statefulset-standards.md)
- [Ceph PV Data Migration](ceph-pv-data-migration.md)
- HASteward: `docs/ContainerUsage.md`, `docs/SafetyGates.md`, `docs/reference/CLI.md`
