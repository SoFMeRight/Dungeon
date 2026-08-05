#!/bin/bash
set -euxo pipefail

# Kubernetes Variables
KUBERNETES_VERSION="v1.35"
CRIO_VERSION="v1.35"

echo "==================================="
echo "Kubernetes Dependencies Installation"
echo "Node: $(hostname)"
echo "==================================="

# ===================================================================
# COMPREHENSIVE SWAP DISABLE (prevents all swap-related issues)
# ===================================================================
echo ""
echo "Step 1: Disabling swap completely and permanently..."

# Disable swap immediately
sudo swapoff -a

# Comment out ALL swap entries in /etc/fstab (not just lines with " swap ")
sudo sed -i '/swap/s/^/#/' /etc/fstab

# Remove swap files that commonly cause issues
sudo rm -f /swap.img /swapfile

# Also disable any systemd swap targets
sudo systemctl mask swap.target 2>/dev/null || true

# Verify swap is off
if [ "$(swapon -s | wc -l)" -gt 1 ]; then
    echo "ERROR: Swap is still enabled!"
    swapon -s
    exit 1
fi
echo "✓ Swap disabled permanently"

# ===================================================================
# KERNEL MODULES
# ===================================================================
echo ""
echo "Step 2: Loading required kernel modules..."

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
echo "✓ Kernel modules loaded"

# ===================================================================
# SYSCTL CONFIGURATION (includes IPv6 for dual-stack)
# ===================================================================
echo ""
echo "Step 3: Configuring sysctl params (IPv4 + IPv6 dual-stack)..."

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
# IPv4 settings
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1

# IPv6 settings for dual-stack
net.ipv6.conf.all.forwarding        = 1
net.ipv6.conf.default.forwarding    = 1

# inotify limits for Kubernetes workloads (Istio CNI, file watchers, etc.)
# Default max_user_instances=128 is too low and causes "too many open files" errors
fs.inotify.max_user_instances       = 8192
fs.inotify.max_user_watches         = 1048576
EOF

# Apply sysctl params without reboot
sudo sysctl --system
echo "✓ Sysctl params configured"

# ===================================================================
# INSTALL PREREQUISITES
# ===================================================================
echo ""
echo "Step 4: Installing prerequisites..."
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common jq
echo "✓ Prerequisites installed"

# ===================================================================
# INSTALL CRI-O RUNTIME
# ===================================================================
echo ""
echo "Step 5: Installing CRI-O runtime..."

# Install CRI-O Runtime (using new repository location)
curl -fsSL https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

# Install required CRI-O dependencies
# DO NOT install crun - CRI-O comes with its own bundled compatible version
sudo apt-get install -y conmon containernetworking-plugins

# Create containers policy.json (required for pulling images)
sudo mkdir -p /etc/containers
cat <<EOF | sudo tee /etc/containers/policy.json
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports": {
        "docker": {
            "registry.k8s.io": [
                {
                    "type": "insecureAcceptAnything"
                }
            ],
            "docker.io": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        }
    }
}
EOF

# Create temporary CNI configuration for CRI-O to start
# This will be replaced by Cilium when the control plane is initialized
sudo mkdir -p /etc/cni/net.d
cat <<EOF | sudo tee /etc/cni/net.d/10-crio-bridge.conf
{
    "cniVersion": "1.0.0",
    "name": "crio",
    "type": "bridge",
    "bridge": "cni0",
    "isGateway": true,
    "ipMasq": true,
    "hairpinMode": true,
    "ipam": {
        "type": "host-local",
        "routes": [
            { "dst": "0.0.0.0/0" }
        ],
        "ranges": [
            [{ "subnet": "192.168.144.0/20" }]
        ]
    }
}
EOF

# Configure CRI-O to use its bundled crun runtime
sudo mkdir -p /etc/crio/crio.conf.d/
cat <<EOF | sudo tee /etc/crio/crio.conf.d/10-runtime.conf
[crio.runtime]
default_runtime = "crun"

[crio.runtime.runtimes.crun]
runtime_path = "/usr/libexec/crio/crun"
runtime_type = "oci"
EOF

sudo systemctl daemon-reload
sudo systemctl enable crio --now
echo "CRI-O runtime installed successfully"

# ===================================================================
# INSTALL KUBERNETES COMPONENTS
# ===================================================================
echo ""
echo "Step 6: Installing Kubernetes components (kubelet, kubeadm, kubectl)..."

# Install Kubernetes components
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent automatic updates
sudo apt-mark hold kubelet kubeadm kubectl cri-o

# ===================================================================
# KUBELET CONFIGURATION (with CRI-O socket)
# ===================================================================
echo ""
echo "Step 7: Configuring kubelet..."

# Get the local IP (first non-loopback IP)
local_ip=$(hostname -I | awk '{print $1}')
echo "  Node IP: $local_ip"

# Configure kubelet with local IP AND CRI-O socket
# This prevents issues where kubelet can't find the container runtime
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--node-ip=$local_ip --container-runtime-endpoint=unix:///var/run/crio/crio.sock
EOF

# Ensure kubelet service is enabled
sudo systemctl enable kubelet

# Restart kubelet to apply configuration
sudo systemctl daemon-reload
sudo systemctl restart kubelet
echo "✓ Kubelet configured with CRI-O socket"

# ===================================================================
# INSTALL HELM
# ===================================================================
echo ""
echo "Step 8: Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
echo "✓ Helm installed"

# ===================================================================
# PRE-PULL IMAGES
# ===================================================================
echo ""
echo "Step 9: Pre-pulling common images..."
sudo crictl pull registry.k8s.io/pause:3.10
echo "✓ Images pre-pulled"

# ===================================================================
# FINAL VERIFICATION
# ===================================================================
echo ""
echo "==================================="
echo "Installation Complete!"
echo "==================================="
echo "Node: $(hostname)"
echo "Node IP: $local_ip"
echo ""
echo "Versions:"
echo "  CRI-O: $(crio --version | head -1)"
echo "  Kubelet: $(kubelet --version)"
echo "  Kubeadm: $(kubeadm version -o short)"
echo "  Helm: $(helm version --short)"
echo ""
echo "Status:"
echo "  ✓ Swap disabled permanently"
echo "  ✓ IPv6 forwarding enabled"
echo "  ✓ Kernel modules loaded"
echo "  ✓ CRI-O runtime configured"
echo "  ✓ Kubelet configured with CRI-O socket"
echo ""
echo "Ready for cluster initialization!"
echo "==================================="
