# OpenBao

OpenBao runs as a three-node raft cluster in `zeldas-lullaby`, managed by the bank-vaults operator from the `Vault` CR `openbao`: `../../../base/openbao/vault-cr.yaml`, patched by `vault-cr-patch.yaml` here.

## How it starts

- The operator creates the StatefulSet `openbao` and the configurer `openbao-configurer`. On first start the configurer initializes raft and unseals every node with the Shamir shares in the Secret `openbao-unseal-keys` (SOPS-encrypted here as `openbao-unseal-keys.enc.yaml`; keys `vault-unseal-N` and `vault-root`).
- The configurer applies `externalConfig` in `vault-cr-patch.yaml`: policies, auth methods and mounts.
- Followers join the leader through `retry_join`.

## A cold start depends on

A cold start is every node sealed at once. Three settings keep it from deadlocking:

- **The sealed-tolerant liveness probe** (`vaultContainerSpec.livenessProbe` in `vault-cr-patch.yaml`). The default probe returns 503 while sealed and kills the pod before it can be unsealed.
- **`publishNotReadyAddresses: true` on the Service `openbao`**, set by the Kyverno policy `mutate-openbao-service-not-ready`. A sealed node never reports ready; without it the configurer finds no endpoint at `http://openbao:8200`.
- **The istio policy `allow-vault-to-vault`** (`istio-policies/zeldas-lullaby/`), which allows 8200 (bootstrap and configurer) and 8201 (raft) between the OpenBao pods.

## Restoring from a raft snapshot

When the configurer can't initialize (no raft data left), bootstrap by hand and restore:

1. Initialize raft on `openbao-0` through a localhost exec: `bao operator init`. Keep its temporary key.
2. Unseal `openbao-0` with the temporary key.
3. Copy the snapshot into `/vault/data` on `openbao-0`, then `bao operator raft snapshot restore -force /vault/data/<snapshot>`.
4. Put the original Shamir shares back into the Secret `openbao-unseal-keys` (from `openbao-unseal-keys.enc.yaml`).
5. Unseal every node with the original shares; the followers join on their own.

## Names bank-vaults fixes

Whatever the CR is called: pod labels `app.kubernetes.io/name: vault` (raft) and `vault-configurator`, mounts `/vault/{data,config}`, the injected `vault-config` volume. Selectors use these names. `envsConfig` reaches the bank-vaults wrapper, not the openbao process; container env goes in `vaultContainerSpec.env`.

## Consuming secrets

One `ClusterSecretStore` per tenant (`clustersecretstore-*.yaml`), each bound to its own mount through Kubernetes auth. An app reads through an `ExternalSecret`; `example-externalsecret.yaml` is the template.
