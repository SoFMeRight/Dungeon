# CNPG-safe node maintenance (rolling drains as IaC)

How the node-convergence rolls (`ansible/k8s/tasks/crio-converge.yml`,
`kubelet-converge.yml`) drain a node **without breaking CloudNativePG clusters**. This
is the reusable pattern for any operation that drains nodes hosting CNPG instances.

## Why a naive `kubectl drain` breaks CNPG here

1. **The primary can't be evicted.** CNPG gives every cluster a `<cluster>-primary`
   PodDisruptionBudget that is always `disruptionsAllowed=0`. A drain retries the
   primary eviction until timeout and fails — CNPG does **not** switch the primary off
   a cordoned or draining node on its own (verified: a primary blocked a drain for the
   full 10 min).
2. **Evicted instances don't reliably rejoin.** After a demote or eviction, a CNPG
   instance can strand: postgres shut down, no `standby.signal`, instance-manager
   idling. Some rejoin, some don't. `wal_log_hints=on`, so `pg_rewind` *could* run —
   CNPG just doesn't reliably drive it after a disruption in this cluster.

So the roll must (a) move primaries itself before the drain, and (b) **notice** when an
instance strands — but it must **not** repair databases automatically (see the boxed
warning below).

## The sequence (per node)

```
Cordon
  → Pre-drain guard   (switch CNPG primaries off this node, wait for the role to move;
                       fail-fast on genuine non-CNPG zero-disruption PDBs)
  → Drain
  → … upgrade, restart, wait Ready, bounce mesh dataplane …
  → Uncordon
  → Post-drain health gate (fail loud naming any CNPG instance that stranded)
```

- **Pre-drain** — `ansible/k8s/files/pre-drain-guard.py` (via `tasks/pre-drain-node.yml`):
  for each CNPG primary on the node it patches `status.targetPrimary` to a ready
  off-node replica (the same trigger as `kubectl cnpg promote`) and waits only until the
  primary *role* is off the node, so the drain can evict the node's now-replica. It does
  **not** wait for the demoted instance to rejoin — that's checked after the drain. No
  ready off-node replica ⇒ it refuses (fail-open): there's nowhere safe to promote.
- **Post-drain** — `ansible/k8s/files/post-drain-reconcile.py` (via
  `tasks/post-drain-reconcile.yml`): after a grace window (let CNPG re-attach what it
  can), it **fails loud, naming** any CNPG instance still not-ready. It repairs nothing.
  A degraded cluster fails the node's converge (fail-open: the node stays schedulable)
  so an operator investigates and repairs it deliberately.

Both scripts run on the first control-plane host (they use `/etc/kubernetes/admin.conf`)
via `delegate_to: groups['k8s_master'][0]`.

## ⚠️ Database recovery is never automated from the pipeline

The post-drain step **detects and surfaces** strands; it does **not** run any repair.
This is deliberate. Re-cloning a CNPG instance (`hasteward repair`) destroys and rebuilds
a data directory, and forcing it past hasteward's split-brain safety gate on the wrong
lineage is **unrecoverable data loss**. hasteward is only ever run after a human has done
the authority analysis — never blindly, never on a schedule, never `--force` from CI.

When the gate fails, repair by hand: triage first, then repair, following
`docs/k8s/cnpg-postgres-cluster-recovery-runbook.md`. The reliable heal for a stranded
replica is a re-clone from the primary; do it only once you've confirmed the primary is
the authority.

## Caveats

- The roll is auto for everything it can do safely (switch primaries off, drain,
  converge), and it **stops for a human** the moment a database strands. That manual step
  is the honest ceiling — CNPG rejoin is unreliable here and DB recovery can't be
  unsupervised.
- The health gate checks **every** CNPG cluster, so a cluster left degraded by anything
  (not just this drain) will also block the roll until it's healthy — surfaced, never
  touched.
