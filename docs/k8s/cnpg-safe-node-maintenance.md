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

So the roll must (a) move primaries itself and (b) repair anything that strands.

## The sequence (per node)

```
Cordon
  → Pre-drain guard   (switch CNPG primaries off this node, wait for the role to move;
                       fail-fast on genuine non-CNPG zero-disruption PDBs)
  → Drain
  → … upgrade, restart, wait Ready, bounce mesh dataplane …
  → Uncordon
  → Post-drain reconcile (re-clone any CNPG instance that stranded, via hasteward)
```

- **Pre-drain** — `ansible/k8s/files/pre-drain-guard.py` (run via `tasks/pre-drain-node.yml`):
  for each CNPG primary on the node it patches `status.targetPrimary` to a ready
  off-node replica (the same trigger as `kubectl cnpg promote`) and waits only until the
  primary *role* is off the node, so the drain can evict the node's now-replica. It does
  **not** wait for the demoted instance to rejoin — that's the reconcile's job. No
  ready off-node replica ⇒ it refuses (fail-open), because there's nowhere safe to
  promote.
- **Post-drain** — `ansible/k8s/files/post-drain-reconcile.py` (run via
  `tasks/post-drain-reconcile.yml`): after a short grace period (let CNPG re-attach what
  it can), any instance still not-ready is re-cloned by a **hasteward `repair` Job**.
  It waits until every CNPG cluster is back to full health before the roll moves to the
  next node. Idempotent — a healthy fleet is a no-op.

Both scripts run on the first control-plane host (they use `/etc/kubernetes/admin.conf`)
via `delegate_to: groups['k8s_master'][0]`.

## The reconcile Job

The reconcile shells out to the existing **hasteward** install — it does not
re-implement DB recovery in ansible. Per stranded instance it applies a Job in
`fairy-bottle` under the `hasteward` ServiceAccount + ClusterRole:

```
image:  docker.io/prplanit/hasteward:latest-dev   # latest-dev carries the reseed conninfo fix
args:   ["repair", "--donor", "<primary-ordinal>"]
env:    HASTEWARD_ENGINE=cnpg
        HASTEWARD_CLUSTER=<cluster>  HASTEWARD_NAMESPACE=<ns>
        HASTEWARD_INSTANCE=<ordinal> HASTEWARD_FORCE=true HASTEWARD_NO_ESCROW=true
```

`hasteward repair` fences the instance, clears its (diverged) pgdata, `pg_basebackup`s a
fresh copy from the primary, and yields `primary_conninfo` back to CNPG so the replica
streams — the one heal that works every time. `--force` overrides hasteward's
split-brain refusal, which is a false positive after a *graceful* switchover (the new
primary provably holds everything the demoted one had). RBAC/SA/PVC come from
`ansible/k8s/recovery/hasteward-job.yaml`.

## Caveats

- **`latest-dev`, not `latest`.** The reseed-conninfo fix ships on `latest-dev`; a
  stable-tagged `:latest` older than that will re-strand replicas on `/tmp/certs`.
- The reconcile reconciles **every** CNPG cluster to full health, not only the drained
  node's — it is a fleet health gate. A cluster with **no** primary (fully down) is left
  for manual attention rather than guessed at.
- A failed repair Job fails the converge for that node (fail-open: the node stays
  schedulable); check the Job logs in `fairy-bottle` and the runbook
  (`docs/k8s/cnpg-postgres-cluster-recovery-runbook.md`).
