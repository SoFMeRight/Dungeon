# FluxCD Graveyard

This directory contains legacy/superseded apps and infrastructure that are no longer
deployed but are preserved for reference. Nothing here is referenced by an active
kustomization, so Flux does not reconcile any of it.

## Components

### mimir (`infrastructure/services/mimir`)

- **Superseded by**: VictoriaMetrics — `vminsert` / `vmselect` / `vmstorage` in `gossip-stone`
- **Reason**: metrics storage consolidated onto VictoriaMetrics; Mimir's Kafka-based
  ingest path was retired with it (`strimzi-kafka-operator`, 2026-10-09, 80b3c820c)
- **Removed from Flux**: 2026-02-01 (a7a5d3dc1)
- **Moved here**: 2026-09-30 (d3ab48af4, bucket provisioning)
- **Cluster cleanup**: 2026-10-10

The Helm release was never uninstalled, only unreferenced, so Helm went on holding
`sh.helm.release.v1.mimir.v1` as `deployed` and 23 of its resources were abandoned in
`gossip-stone` for ~8 months — 10 PDBs, 4 ConfigMaps, 2 ServiceAccounts, 2 Roles, 2
RoleBindings, 1 ClusterRole, 1 ClusterRoleBinding, plus the release secret. Flux
inventoried none of them, so nothing would ever have pruned them. They were deleted
2026-10-10 along with the last references in active config: two Alloy scrape-drop
rules, an Alloy Loki drop for `err-mimir-sample-timestamp-too-old`, the
`mimir-rollout-operator` entry in `mutate-automount-sa-token`, and the parked
`mimir.pcfae.com` hostname on the fairer-pages route.

### Reason not recorded

Retired before this file existed; kept for reference only.

| Component | Path | Moved |
| --- | --- | --- |
| quay | `infrastructure/services/quay` | 2026-02-07 |
| jfrog-artifactory | `infrastructure/services/jfrog-artifactory` | 2026-03-15 |
| code-server | `apps/base/code-server` | 2026-07-02 |
| filebrowser | `apps/base/filebrowser` | 2026-07-02 |

## Retiring a HelmRelease

Deleting or unreferencing a `HelmRelease` does **not** remove what Helm installed. Run
the uninstall (or let Flux's `uninstall` remediation run) *before* moving the manifests
here, then confirm no `sh.helm.release.v1.<name>.*` secret and no objects carrying the
release's labels survive in the namespace. Otherwise the resources are abandoned:
unmanaged, unpruned, and invisible to `flux` — which is exactly how Mimir's PDBs went on
shaping drain behaviour eight months after the app was gone.

## Usage

These components are **NOT deployed** and must not be referenced in active
kustomizations. They are kept as reference material for configuration patterns and as a
historical record. Before restoring anything, consider whether the superseding
technology is the better answer.
