#!/bin/bash
set -euo pipefail

# ===================================================================
# CRI-O REGISTRY MIRROR CONFIGURATION
# ===================================================================
# This script configures CRI-O to use Harbor pull-through
# caches for docker.io, ghcr.io, lscr.io, and quay.io, reducing
# bandwidth and avoiding rate limits.
#
# Run from: Control plane node
# Target: All cluster nodes (control plane + workers)
# ===================================================================

echo "==================================="
echo "CRI-O Registry Mirror Configuration"
echo "Control Node: $(hostname)"
echo "==================================="

# Define cluster nodes
CONTROL_NODES=(
  "dungeon-map-001"
  "dungeon-map-002"
  "dungeon-map-003"
  "dungeon-map-004"
  "dungeon-map-005"
)

WORKER_NODES=(
  "dungeon-chest-001"
  "dungeon-chest-002"
  "dungeon-chest-003"
  "dungeon-chest-004"
  "dungeon-chest-005"
)

ALL_NODES=("${CONTROL_NODES[@]}" "${WORKER_NODES[@]}")

# ===================================================================
# CONFIGURE REGISTRY MIRRORS
# ===================================================================
echo ""
echo "Configuring registry mirrors on ${#ALL_NODES[@]} nodes..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for node in "${ALL_NODES[@]}"; do
  echo "==================================="
  echo "Configuring node: $node"
  echo "==================================="

  if ssh "$node" 'bash -s' <<'ENDSSH'
set -euo pipefail

# Create registries.conf.d directory if it doesn't exist
sudo mkdir -p /etc/containers/registries.conf.d

# Remove old JFrog mirror config if present
sudo rm -f /etc/containers/registries.conf.d/jcr-mirrors.conf

# Configure all Harbor pull-through cache mirrors
cat <<EOF | sudo tee /etc/containers/registries.conf.d/harbor-mirrors.conf >/dev/null
# Harbor pull-through caches
# This reduces bandwidth usage and avoids registry rate limits
# Falls back to upstream registry if Harbor is unavailable

# Docker Hub mirror
[[registry]]
prefix = "docker.io"
location = "docker.io"

[[registry.mirror]]
location = "docker.cr.optcp.com"

# GitHub Container Registry mirror
[[registry]]
prefix = "ghcr.io"
location = "ghcr.io"

[[registry.mirror]]
location = "ghcr.cr.optcp.com"

# LinuxServer.io mirror
[[registry]]
prefix = "lscr.io"
location = "lscr.io"

[[registry.mirror]]
location = "lscr.cr.optcp.com"

# Quay.io mirror
[[registry]]
prefix = "quay.io"
location = "quay.io"

[[registry.mirror]]
location = "quay.cr.optcp.com"
EOF

echo "✓ Registry mirror configuration created"

# Restart CRI-O to apply changes
sudo systemctl restart crio

echo "✓ CRI-O service restarted"

# Verify CRI-O is running
if systemctl is-active --quiet crio; then
  echo "✓ CRI-O is running"
  exit 0
else
  echo "✗ CRI-O failed to start"
  exit 1
fi
ENDSSH
  then
    echo "✓ Successfully configured $node"
    SUCCESS_COUNT=$((SUCCESS_COUNT+1))
  else
    echo "✗ Failed to configure $node"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
  echo ""
done

# ===================================================================
# FINAL SUMMARY
# ===================================================================
echo "==================================="
echo "Configuration Summary"
echo "==================================="
echo "Total nodes: ${#ALL_NODES[@]}"
echo "Successful: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✓ All nodes configured successfully!"
  echo ""
  echo "Registry mirror configuration:"
  echo "  docker.io → docker.cr.optcp.com"
  echo "  ghcr.io   → ghcr.cr.optcp.com"
  echo "  lscr.io   → lscr.cr.optcp.com"
  echo "  quay.io   → quay.cr.optcp.com"
  echo ""
  echo "Images will now be pulled through Harbor pull-through caches."
  echo "This reduces bandwidth and avoids rate limiting."
  echo "Automatically falls back to upstream if Harbor is unavailable."
  echo "==================================="
  exit 0
else
  echo "✗ Some nodes failed to configure"
  echo "==================================="
  exit 1
fi
