# GPU Node Setup Guide

This guide covers setting up NVIDIA GPU support on Kubernetes worker nodes in the dungeon cluster.

## Overview

There are two approaches for GPU drivers in Kubernetes:

| Approach | Pros | Cons |
|----------|------|------|
| **GPU Operator Managed** | Automatic driver updates, no host config | Requires precompiled drivers for your kernel |
| **Host-Installed (Ubuntu)** | Canonical-signed, Secure Boot compatible, any kernel | Manual updates, requires CRI-O configuration |

### Current Status

- **GPU Operator Version**: v25.10.1 (namespace: `gorons-bracelet`)
- **Driver Mode**: `driver.enabled: false` (host-installed drivers)
- **Reason**: Originally, precompiled drivers weren't available for Ubuntu 24.04 kernel 6.8

> **Note**: As of late 2025, NVIDIA now provides precompiled driver containers for Ubuntu 24.04 with kernel 6.8 (R580 branch). Consider testing GPU Operator managed drivers on new nodes.

## GPU Nodes

| Node | GPU | Driver Source |
|------|-----|---------------|
| dungeon-chest-001 | RTX A2000 12GB | Host-installed (Ubuntu) |
| dungeon-chest-004 | GTX 980 Ti | Host-installed (Ubuntu) |

## Option 1: Host-Installed Ubuntu Drivers (Current Approach)

### Prerequisites

- Ubuntu 24.04 LTS worker node
- GPU passed through from Proxmox
- SSH access to the node

### Step 1: Install NVIDIA Drivers

```bash
# SSH to the GPU node
ssh dungeon-chest-00X

# Update packages
sudo apt update

# Install kernel headers and NVIDIA driver
sudo apt install -y linux-image-generic linux-headers-generic nvidia-driver-580

# Reboot to load the driver
sudo reboot
```

### Step 2: Verify Driver Installation

```bash
# After reboot, verify the driver is loaded
ssh dungeon-chest-00X "nvidia-smi"
```

Expected output shows GPU name, driver version (580.x.x), and memory info.

### Step 3: Install Server/Headless Packages (for containers)

```bash
ssh dungeon-chest-00X "sudo apt-get install -y --no-install-recommends \
  nvidia-utils-580-server \
  nvidia-headless-no-dkms-580-server \
  libnvidia-decode-580-server \
  libnvidia-extra-580-server \
  libnvidia-encode-580-server \
  libnvidia-fbc1-580-server"
```

### Step 4: Install NVIDIA Kernel Module Meta-Package

Install the meta-package that automatically tracks kernel updates:

```bash
ssh dungeon-chest-00X "sudo apt-get install --no-install-recommends -y \
  linux-modules-nvidia-580-server-generic"
```

This installs `linux-modules-nvidia-580-server-<kernel-version>`, `linux-objects-nvidia-580-server-<kernel-version>`, and `linux-signatures-nvidia-<kernel-version>` for the current kernel AND automatically pulls matching packages when the kernel is updated via `apt upgrade`.

> **WARNING**: Do NOT install kernel-version-pinned packages (e.g. `linux-modules-nvidia-580-server-6.8.0-90-generic`) directly. These break on kernel updates — the nvidia module won't load for the new kernel, GPU pods will crash with `nvidia-smi: command not found`, and you'll need to manually install the correct version-pinned package for every kernel update.

### Step 5: Configure CRI-O for NVIDIA Runtime

Run the setup script on the GPU node:

```bash
# Copy the script to the node
scp /srv/dungeon/bash/_importing_from_sibling_repo/setup-gpu-node.sh dungeon-chest-00X:~/

# Execute on the node
ssh dungeon-chest-00X "chmod +x ~/setup-gpu-node.sh && sudo ~/setup-gpu-node.sh"
```

The script:
- Ensures `runc` is installed and accessible
- Fixes the nvidia-container-runtime script to use absolute paths
- Restarts CRI-O

### Step 6: Verify GPU in Kubernetes

Wait for the GPU Operator to detect the GPU (may take 1-2 minutes):

```bash
# Check node labels
kubectl get node dungeon-chest-00X -o jsonpath='{.metadata.labels}' | jq | grep nvidia

# Check allocatable GPU resources
kubectl get node dungeon-chest-00X -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'

# With time-slicing (8 replicas configured)
kubectl get node dungeon-chest-00X -o jsonpath='{.status.allocatable}' | jq
```

### Step 7: Delete and Recreate GPU Operator Pods

If the GPU isn't detected, restart the GPU operator components on that node:

```bash
# Delete GPU feature discovery pod to force re-detection
kubectl delete pod -n gorons-bracelet -l app=gpu-feature-discovery --field-selector spec.nodeName=dungeon-chest-00X

# Wait for new pod to become ready
kubectl get pods -n gorons-bracelet -l app=gpu-feature-discovery -o wide -w
```

## Option 2: GPU Operator Managed Drivers

> **Status**: Not currently in use, but may be viable now with kernel 6.8 support

To switch to GPU Operator managed drivers:

### Update ClusterPolicy

Edit the GPU operator helm values to enable driver management:

```yaml
driver:
  enabled: true
  version: "580.95.05"  # or latest supported version
  repository: nvcr.io/nvidia
```

### Remove Host Drivers

Before enabling operator-managed drivers, remove host-installed drivers:

```bash
ssh dungeon-chest-00X "sudo apt purge -y 'nvidia-*' 'libnvidia-*'"
sudo reboot
```

The GPU Operator will then install and manage drivers via container.

## Time-Slicing Configuration

GPU time-slicing is configured via ConfigMap in the `gorons-bracelet` namespace:

```bash
kubectl get configmap time-slicing-config -n gorons-bracelet -o yaml
```

Current profiles:
- **any** (default fallback): 16 replicas
- **gtx-980-ti**: 16 replicas (6GB Maxwell)
- **rtx-a2000**: 24 replicas (12GB Ampere)
- **rtx-3080-ti**: 96 replicas (12GB Ampere)

## Troubleshooting

### GPU Not Detected After Driver Install

1. Check if kernel modules are loaded:
   ```bash
   ssh dungeon-chest-00X "lsmod | grep nvidia"
   ```

2. Check dmesg for NVIDIA errors:
   ```bash
   ssh dungeon-chest-00X "dmesg | grep -i nvidia | tail -20"
   ```

3. Verify nvidia-container-runtime:
   ```bash
   ssh dungeon-chest-00X "cat /usr/local/nvidia/toolkit/nvidia-container-runtime"
   ```

### GPU Pods Crash After Kernel Update

If GPU operator pods enter `Init:CrashLoopBackOff` after a kernel update:

1. Check if nvidia module is loaded:
   ```bash
   ssh dungeon-chest-00X "lsmod | grep nvidia"
   ```

2. If not loaded, check if modules exist for current kernel:
   ```bash
   ssh dungeon-chest-00X "uname -r"
   ssh dungeon-chest-00X "dpkg -l | grep linux-modules-nvidia | grep \$(uname -r)"
   ```

3. If no matching modules, install the meta-package (prevents future occurrences):
   ```bash
   ssh dungeon-chest-00X "sudo apt install -y linux-modules-nvidia-580-server-generic && sudo modprobe nvidia"
   ```

4. Delete crashed GPU pods to trigger recreation:
   ```bash
   kubectl delete pods -n gorons-bracelet --field-selector spec.nodeName=dungeon-chest-00X \
     -l app.kubernetes.io/component=nvidia-container-toolkit-daemonset
   kubectl delete pods -n gorons-bracelet --field-selector spec.nodeName=dungeon-chest-00X \
     -l app=gpu-feature-discovery
   ```

### Pods Can't Access GPU

1. Check if device plugin is running:
   ```bash
   kubectl get pods -n gorons-bracelet -l app=nvidia-device-plugin-daemonset -o wide
   ```

2. Check pod events:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```

3. Verify GPU resource requests in pod spec:
   ```yaml
   resources:
     limits:
       nvidia.com/gpu: 1
   ```

## Maintenance

### Driver Updates

With the `linux-modules-nvidia-580-server-generic` meta-package installed, kernel module updates are handled automatically by `apt upgrade`:

```bash
ssh dungeon-chest-00X "sudo apt update && sudo apt upgrade -y"
# Reboot required after kernel or driver upgrades
ssh dungeon-chest-00X "sudo reboot"
# After reboot, verify driver loaded
ssh dungeon-chest-00X "nvidia-smi"
```

If `nvidia-smi` fails after a kernel update, verify the meta-package is installed:

```bash
ssh dungeon-chest-00X "dpkg -l | grep linux-modules-nvidia-580-server-generic"
# If missing, install it:
ssh dungeon-chest-00X "sudo apt install -y linux-modules-nvidia-580-server-generic"
ssh dungeon-chest-00X "sudo modprobe nvidia"
```

### Verify GPU Health

```bash
ssh dungeon-chest-00X "nvidia-smi"
```

## Related Files

- Setup script: `/srv/dungeon/bash/_importing_from_sibling_repo/setup-gpu-node.sh`
- GPU Operator Helm release: `/srv/dungeon/fluxcd/infrastructure/operators/overlays/production/gpu-operator/`
- Time-slicing ConfigMap: `gorons-bracelet/time-slicing-config`

## References

- [GPU Operator with Pre-installed Drivers](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#considerations-for-pre-installed-drivers)
- [GPU Operator Platform Support](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/platform-support.html)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/overview.html)

---
*Last Updated: 2026-02-06*
