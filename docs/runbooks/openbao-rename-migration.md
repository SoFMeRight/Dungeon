# Runbook — Rename `vault` → `openbao` (bank-vaults CR, zero data loss)

**Status:** planned — schedule a maintenance window. Not for live improv.
**Goal:** every generated resource reads `openbao-*` (StatefulSet, pods, services, PVCs)
and the repo folders are `**/openbao/**`, so inventory scrapers / docs / freelens make it
obvious this is **OpenBao**, not HashiCorp Vault.
**Stay on bank-vaults** — keep auto-unseal (k8s secret) and config-as-code (`externalConfig`).

## What this does and does NOT change

| Changes | Stays the same |
|---|---|
| CR name `vault`→`openbao`; `StatefulSet/openbao`, `Pod/openbao-0/1/2`, `Service/openbao`, PVCs `*-openbao-*` | `kind: Vault` (`vault.banzaicloud.com`) — one CR object, unavoidable on bank-vaults |
| repo folders `configs/{base,overlays/production}/vault` → `.../openbao` | The OpenBao software/image (already OpenBao) |
| labels `app.kubernetes.io/name`, `vault_cr` → `openbao` | The unseal keys + root token themselves (carried across) |
| every ref to `http://vault.zeldas-lullaby.svc:8200` → `openbao.` | Domain `vault.pcfae.com` (kept per decision; can be revisited separately) |

## Why a simple rename can't work (read once)

- bank-vaults derives all resource names from the **CR name**, so the names only change if the CR is renamed → a **new StatefulSet → new PVCs → new raft node IDs**.
- Raft node IDs **are the pod names** (`node_id: "${ env POD_NAME }"`). Attaching `vault-0`'s
  volume to a pod calling itself `openbao-0` corrupts raft consensus. So the data **must**
  come across via **snapshot → restore**, which re-inits raft cleanly with the new IDs.
- After `snapshot restore -force`, the barrier is re-encrypted with the **OLD** keys, so the
  new cluster must be unsealed with the **OLD** Shamir shares. This "unseal hand-off" is the
  one delicate step; the rehearsal in Phase 1 exists to prove it.

## Blast radius (every touchpoint — verify none added since)

- `configs/base/vault/` (CR, statefulset base, configmap, service, SA, keyring secret ref)
- `configs/overlays/production/vault/` — CR patch, **5 ClusterSecretStores** (`great-sea`,
  `precisionplanit`, `pedestal-of-time`, `operationtimecapsule`, `zeldas-letter`) each with
  `server: http://vault.zeldas-lullaby.svc.cluster.local:8200`, `vault-unseal-keys.enc.yaml`,
  `vault-k8s-auth-setup.sh`, `README.md`
- `configs/overlays/production/cilium-policies/zeldas-lullaby/cnp-vault.yaml`
- `configs/overlays/production/istio-policies/zeldas-lullaby/allow-*-to-vault.yaml` (AuthZ)
- `configs/overlays/production/kyverno-policies/mutate-vault-sidecar-hardening.yaml` — **selector**
  `app.kubernetes.io/name: vault` / `vault-configurator` must become `openbao` / `openbao-configurator`
- `services/base/zitadel-jobs/admin-sa-provision-job.yaml` — `http://vault.zeldas-lullaby.svc:8200`
- The `vault` HTTPRoute (backend service → `openbao`; hostname `vault.pcfae.com` unchanged)
- Grep gate before starting:
  `grep -rniE "vault" fluxcd/ | grep -viE "vaultwarden|bank-vaults|openbao"` — reconcile the list.

## Prerequisites

- Tools: `bao` (OpenBao CLI), `kubectl`, `velero`, `flux`, `sops`.
- A **scratch namespace** (`openbao-rehearsal`) for the Phase-1 gate.
- Current root token + all 5 Shamir shares (from `vault-unseal-keys`, sops-decrypted).
- A window: Vault is **down during cutover** → external-secrets syncs, zitadel provisioning,
  and OIDC logins that hit it will fail until Phase 4.

---

## Phase 1 — BACKUPS + GATE (do not skip; do not proceed unless the gate passes)

1. **Raft snapshot** (primary data backup):
   ```
   export VAULT_ADDR=http://127.0.0.1:8200   # via kubectl port-forward svc/vault 8200
   export VAULT_TOKEN=<root>                  # from vault-unseal-keys .data.vault-root
   bao operator raft snapshot save vault-$(date +%Y%m%d).snap
   ```
2. **Export unseal material** (the OLD 5 shares + root) — keep OFFLINE, encrypted:
   ```
   kubectl -n zeldas-lullaby get secret vault-unseal-keys -o yaml > vault-unseal-keys.backup.yaml
   ```
3. **Velero backup** of the namespace incl. PVCs (belt-and-suspenders, second recovery path):
   ```
   velero backup create openbao-premigrate --include-namespaces zeldas-lullaby --wait
   velero backup describe openbao-premigrate --details   # confirm PVCs + Completed
   ```
4. **Confirm PV Retain** (already true — data survives PVC deletion):
   ```
   for p in 0 1 2; do kubectl get pv $(kubectl -n zeldas-lullaby get pvc vault-data-vault-$p \
     -o jsonpath='{.spec.volumeName}') -o jsonpath='{.metadata.name} {.spec.persistentVolumeReclaimPolicy}{"\n"}'; done
   # expect all "Retain"
   ```
5. **GATE — rehearse the whole cutover in the scratch namespace and PROVE it:**
   - Deploy a throwaway 1-node `openbao` CR (bank-vaults) into `openbao-rehearsal`.
   - Let it init (temp keys) + unseal.
   - `bao operator raft snapshot restore -force vault-YYYYMMDD.snap`.
   - Swap the rehearsal unseal secret to the **OLD** shares; restart; confirm it **unseals with the old keys**.
   - Verify data: `bao secrets list`, `bao policy list`, `bao auth list`, read one key from each KV engine.
   - **Only if this rehearsal fully succeeds do you proceed.** If it fails, stop — the real
     cutover would fail the same way, and you've lost nothing.

---

## Phase 2 — Prepare renamed manifests (git branch; NOT applied)

Do this on a branch; nothing hits the cluster yet.

1. `git mv` the two folders `vault` → `openbao` (base + overlay). Rename files
   (`vault-cr.yaml`→`openbao-cr.yaml`, etc.) and fix `kustomization.yaml` resource lists.
2. In the CR: `metadata.name: vault` → `openbao`. Leave `kind: Vault` (immutable).
3. Update the **5 ClusterSecretStores** + the zitadel job: `vault.` → `openbao.` in the server address.
4. Update the **mutate policy selector** to `openbao` / `openbao-configurator` (else the pods
   lose their 5/5 hardening on recreate).
5. Rename the unseal secret to `openbao-unseal-keys` **keeping the OLD encrypted values**, and
   point the CR's `unsealConfig.kubernetes.secretName` at it. (Keeping the OLD shares is what
   makes the hand-off work.)
6. Point the HTTPRoute backend at `service/openbao` (hostname stays `vault.pcfae.com`).
7. Rename CNP/AuthZ policy files + their selectors.
8. `kustomize build` every changed overlay clean; do NOT push yet.

---

## Phase 3 — Cutover (maintenance window)

1. **Freeze** so you control the sequence:
   ```
   flux suspend kustomization infra-configs        # and the phase that carries vault
   kubectl -n zeldas-lullaby scale deploy external-secrets --replicas=0   # stop secret syncs
   ```
2. **Fresh final snapshot** (data may have changed since Phase 1) — repeat Phase 1 step 1.
3. **Tear down old vault** (PVs are Retain → data safe):
   ```
   kubectl -n zeldas-lullaby delete vault vault      # operator removes sts/pods
   # confirm PVs for vault-data-vault-0/1/2 go Released, NOT deleted
   ```
4. **Bring up openbao** — merge/push the Phase-2 branch, `flux resume` + reconcile. bank-vaults
   creates `openbao-0/1/2` (empty), inits (temp keys), applies `externalConfig` to empty data.
5. **Restore** into the new cluster:
   ```
   export VAULT_ADDR=http://127.0.0.1:8200   # port-forward svc/openbao
   export VAULT_TOKEN=<temp root from the fresh openbao-unseal secret>
   bao operator raft snapshot restore -force vault-YYYYMMDD.snap
   # cluster now seals — it wants the OLD keys
   ```
6. **Unseal hand-off:** set `openbao-unseal-keys` back to the **OLD** shares (from the
   Phase-1 backup), then restart pods so bank-vaults auto-unseals with them:
   ```
   kubectl -n zeldas-lullaby apply -f vault-unseal-keys.backup.yaml  # renamed to openbao-unseal-keys, OLD values
   kubectl -n zeldas-lullaby delete pod openbao-0 openbao-1 openbao-2
   # confirm all three come back Unsealed with old keys
   ```
7. **Unfreeze consumers:** re-point + scale external-secrets back up; re-run/allow the zitadel job.

---

## Phase 4 — Verify (all must pass)

- `kubectl -n zeldas-lullaby get sts,pods,svc,pvc | grep openbao` — all `openbao-*`, no `vault-*`.
- Raft healthy: `bao operator raft list-peers` → `openbao-0/1/2`, all `voter`, one `leader`.
- Data intact: each KV engine lists + reads (`operationtimecapsule`, `precisionplanit`,
  `zeldas-letter`, `great-sea`, `pedestal-of-time`); `bao policy list`; `bao auth list` (kubernetes + oidc).
- **external-secrets** ClusterSecretStores `Valid` and ExternalSecrets syncing.
- **zitadel** vault sync + **OIDC login** at `vault.pcfae.com` work.
- Mutate policy hardens `openbao-*`: re-check the audit report shows **5/5**.
- Soak: watch external-secrets + OIDC for a day.

---

## Phase 5 — Cleanup (after a stable soak, e.g. 3–7 days)

- Delete the **Released** old PVs `vault-data-vault-0/1/2` (this destroys the old RBD data —
  only after openbao is trusted).
- Remove leftover `vault*` manifests/files; final `grep -rniE "vault" fluxcd/ | grep -viE "vaultwarden|bank-vaults|openbao"` should be ~empty (bar the `kind: Vault` line + the `vault.pcfae.com` domain).
- Delete `openbao-premigrate` Velero backup + snapshot once confident.

---

## Rollback (any Phase-3/4 failure)

You have three independent recovery paths — prefer the earliest that works:
1. **Old cluster back via git:** re-apply the OLD `vault` CR from git. The old PVs are
   **Retain/Released**; re-create `vault-data-vault-0/1/2` PVCs bound to them (set `volumeName`
   to the retained PVs, clear their `claimRef.uid`) → old `vault-0/1/2` reattach the original
   raft data. Re-point consumers to `vault.`.
2. **Snapshot restore** into the re-created old (or new) cluster from the fresh Phase-3 snapshot.
3. **Velero** restore of `openbao-premigrate`.

Do **not** run Phase 5 (PV deletion) until rollback is no longer needed.

---

## Appendix — the two things that make or break this

- **Unseal hand-off:** post-`restore -force` the barrier is the OLD Shamir key. bank-vaults
  will happily *init* an empty cluster with fresh keys, so the sequence is: let it init (temp),
  restore, then **overwrite the unseal secret with the OLD shares and restart**. Prove it in
  Phase 1 before touching prod.
- **Raft identity = pod name:** this is why PV-swap alone fails and snapshot/restore is
  mandatory. The restore rebuilds membership under `openbao-0/1/2`; the old `vault-0/1/2`
  peer identities simply don't come along.
