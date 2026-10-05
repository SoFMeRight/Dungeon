# gpu-operator — why it's version-pinned

Two things in `helmrelease.yaml` are deliberately held back, **both because of the GTX 980 Ti in `dungeon-chest-004`** (Maxwell, CUDA compute capability 5.2 — the oldest card in the fleet). Do not let Renovate or a well-meaning bump move either one.

## 1. Chart pinned to `v26.7.0` (`spec.chart.spec.version`)
Renovate bumped the chart to **v26.7.1** (commit `ba3f9b86`) and it does **not** work here: the upgrade's `ClusterPolicy/cluster-policy` never reaches `Ready` — it sits `InProgress` until the Helm `--wait` times out, the HelmRelease retries, exhausts its retries, and auto-rolls-back to v26.7.0. Net effect when unpinned: the HelmRelease is permanently `Stalled`/`UpgradeFailed` even though the cluster is actually running the (working) v26.7.0 release.

`v26.7.0` is the last chart version whose ClusterPolicy reconciles cleanly alongside the pinned v25.10.1 validator (below) on this hardware. Pinned here, it's what's running, so the HelmRelease stays green.

## 2. Validator image pinned to `v25.10.1` (`spec.values...validator.version`)
The validator image from v26.x is built against a CUDA that no longer supports Maxwell/5.2 — its `vectorAdd` segfaults (exit 139) on the 980 Ti, while the **same binary from v25.10.1 passes on the same card and host driver**. This is load-bearing, not cosmetic: a failed cuda-validation never writes `/run/nvidia/validations/cuda-ready`, so the node would advertise GPU capacity the operator never confirmed. Only this image is held; device-plugin, toolkit, DCGM and NFD track the chart. (It stops receiving CVE fixes while pinned.)

## Lifting the pins
**Both lift when the 980 Ti is replaced — nothing else does.** When that card is gone:
1. Un-pin the validator (`validator.version`) so it tracks the chart again.
2. Un-pin the chart (`spec.chart.spec.version`) and remove the Renovate `allowedVersions` hold for `gpu-operator`.
3. Let Renovate resume; verify `ClusterPolicy` reaches `Ready` and `nvidia-cuda-validator` completes `0/1 Completed` on every GPU node.

Renovate is constrained to `< 26.7.1` for the `gpu-operator` chart (see `apps/base/renovate/configmap.yaml`) so it stops re-proposing the broken bump until then.
