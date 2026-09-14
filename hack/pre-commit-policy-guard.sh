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

IMAGE="docker.io/prplanit/polysieve:v0.0.3"

if ! command -v docker >/dev/null 2>&1; then
  echo "policy guard: docker unavailable — skipping (install docker to enable the PolySieve check)"
  exit 0
fi

# Run as the invoking user so any files the container writes are owned by the caller,
# not root (HOME=/tmp keeps kubectl/kustomize caches writable under a non-root uid).
user_args=(--user "$(id -u):$(id -g)" -e HOME=/tmp)

# Mount the kubeconfig (as a file, outside HOME) for best-effort cluster augmentation.
kube_conf="${KUBECONFIG:-$HOME/.kube/config}"
kube_args=()
if [ -f "$kube_conf" ]; then
  kube_args=(--network host -v "${kube_conf}:/tmp/kubeconfig:ro" -e KUBECONFIG=/tmp/kubeconfig)
fi

if docker run --rm "${user_args[@]}" "${kube_args[@]}" -v "$PWD:/repo" -w /repo "$IMAGE" \
    check --profile dungeon --cluster; then
  exit 0
fi

cat <<EOF

Generated network/security policy is stale.

Regenerate it, review the diff, stage the intended changes, and commit again
(runs as your uid so regenerated files are yours, not root):
  docker run --rm --network host \\
    --user "\$(id -u):\$(id -g)" -e HOME=/tmp \\
    -v "\$HOME/.kube/config:/tmp/kubeconfig:ro" -e KUBECONFIG=/tmp/kubeconfig \\
    -v "\$PWD:/repo" -w /repo $IMAGE generate --profile dungeon --cluster

Override:
  SKIP_GENERATED_POLICY_GUARD=1 git commit ...
EOF
exit 1
