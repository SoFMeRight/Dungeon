#!/usr/bin/env bash
# pre-commit-policy-guard.sh — verify generated network/security policy matches the repo.
#
# Derives policy from the repo's own manifests with PolySieve (the repo is the source of truth)
# and fails if the committed policy is stale. Best-effort --cluster augmentation resolves
# Helm/operator-rendered backends when the cluster is reachable; offline it degrades to repo-only
# and PolySieve's honesty gate preserves rather than prunes, so it never falsely reports drift for
# backends it cannot see.
#
# Override: SKIP_GENERATED_POLICY_GUARD=1 git commit ...
set -euo pipefail

if [ "${SKIP_GENERATED_POLICY_GUARD:-}" = "1" ]; then
  exit 0
fi

IMAGE="docker.io/prplanit/polysieve:v0.0.2"

if ! command -v docker >/dev/null 2>&1; then
  echo "policy guard: docker unavailable — skipping (install docker to enable the PolySieve check)"
  exit 0
fi

# Mount the kubeconfig for best-effort cluster augmentation when it exists.
kube_dir="$(dirname "${KUBECONFIG:-$HOME/.kube/config}")"
kube_args=()
if [ -d "$kube_dir" ]; then
  kube_args=(--network host -v "${kube_dir}:/root/.kube:ro")
fi

if docker run --rm "${kube_args[@]}" -v "$PWD:/repo" -w /repo "$IMAGE" \
    check --profile dungeon --cluster; then
  exit 0
fi

cat <<EOF

Generated network/security policy is stale.

Regenerate it, review the diff, stage the intended changes, and commit again:
  docker run --rm --network host -v "\$HOME/.kube:/root/.kube:ro" \\
    -v "\$PWD:/repo" -w /repo $IMAGE generate --profile dungeon --cluster

Override:
  SKIP_GENERATED_POLICY_GUARD=1 git commit ...
EOF
exit 1
