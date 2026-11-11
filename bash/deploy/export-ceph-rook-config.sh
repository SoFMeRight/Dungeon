#!/bin/bash
set -e

echo "=== Export Ceph Configuration for Rook External Cluster ==="
echo ""
echo "This script runs the Rook create-external-cluster-resources.py script"
echo "Run this script on a Proxmox node with Ceph access"
echo ""

# Configuration
NAMESPACE="optcp-operators-privileged"
RBD_DATA_POOL="dungeon"
# Get the first IP address of the host
HOST_IP=$(hostname -I | awk '{print $1}')
RGW_ENDPOINT="http://${HOST_IP}:7480"

echo "Configuration:"
echo "  Kubernetes namespace: $NAMESPACE"
echo "  RBD data pool: $RBD_DATA_POOL"
echo "  RGW endpoint: $RGW_ENDPOINT"
echo ""

# Download the script
echo "Step 1: Download create-external-cluster-resources.py"
if [ ! -f "/tmp/create-external-cluster-resources.py" ]; then
    curl -sL https://raw.githubusercontent.com/rook/rook/release-1.18/deploy/examples/create-external-cluster-resources.py -o /tmp/create-external-cluster-resources.py
    chmod +x /tmp/create-external-cluster-resources.py
    echo "  Script downloaded"
else
    echo "  Script already exists"
fi
echo ""

# Enable Prometheus module
echo "Step 2: Enable Ceph Prometheus module"
if ceph mgr module ls | grep -q '"prometheus"'; then
    echo "  Prometheus module already enabled"
else
    echo "  Enabling Prometheus module..."
    ceph mgr module enable prometheus
    echo "  Waiting for Prometheus module to initialize..."
    sleep 5
    echo "  Prometheus module enabled"
fi

# Verify monitoring endpoint
echo "  Checking for monitoring endpoint..."
if ceph mgr services | grep -q prometheus; then
    echo "  Monitoring endpoint found"
else
    echo "  WARNING: Monitoring endpoint not found, waiting longer..."
    sleep 10
fi
echo ""

# Run the script
echo "Step 3: Run create-external-cluster-resources.py"
echo "  This will create users and generate configuration for Rook..."
echo ""

python3 /tmp/create-external-cluster-resources.py \
    --rbd-data-pool-name "$RBD_DATA_POOL" \
    --rgw-endpoint "$RGW_ENDPOINT" \
    --namespace "$NAMESPACE" \
    --format bash \
    --rgw-pool-prefix "default" > /tmp/rook-ceph-external-cluster-config.sh

echo ""
echo "=== Configuration Export Complete ==="
echo ""
echo "Generated configuration saved to: /tmp/rook-ceph-external-cluster-config.sh"
echo ""
echo "Next steps:"
echo "  1. Copy the configuration file to your workstation:"
echo "     scp root@$(hostname):/tmp/rook-ceph-external-cluster-config.sh ."
echo ""
echo "  2. Apply the configuration to your Kubernetes cluster"
echo ""
