# Kubernetes IPv6 Dual-Stack Migration

## Problem Statement

The dungeon Kubernetes cluster was initially deployed as IPv4-only. We encountered a requirement to connect to an external Ceph cluster whose monitors listen exclusively on IPv6 addresses (`fc00:f1:ada:104e:1ace::1:6789`).

When attempting to use Rook operator to connect to the external Ceph cluster, pods running in Kubernetes cannot reach the Ceph monitors because:
1. Kubernetes pods only receive IPv4 addresses
2. Pods have no IPv6 routes or addresses configured
3. The external Ceph monitors do not listen on IPv4

## Attempted Solutions

### 1. Enable IPv6 in Cilium CNI (Incomplete Solution)

We attempted to enable IPv6 in Cilium by configuring:

```yaml
# fluxcd/infrastructure/controllers/overlays/production/cilium/helmrelease-patch.yaml
ipv6:
  enabled: true
ipv6NativeRoutingCIDR: "fc00:f1:d759:3053:a573::/64"
```

**Result**: Cilium configuration accepted the IPv6 settings, but pods still did not receive IPv6 addresses.

**Root Cause**: Enabling IPv6 in Cilium alone is insufficient. Kubernetes requires dual-stack configuration at the control plane level.

### 2. Investigation of Kubernetes Control Plane

Inspection of the kube-controller-manager revealed IPv4-only configuration:

```bash
kubectl get pod -n kube-system -l component=kube-controller-manager -o yaml | grep cluster-cidr
```

Output:
```
- --cluster-cidr=192.168.144.0/20
- --service-cluster-ip-range=10.144.0.0/12
```

**Finding**: The cluster was initialized without IPv6 pod and service CIDRs, which is required for dual-stack networking.

## Requirements for Dual-Stack Kubernetes

To properly enable IPv6 dual-stack networking, the following components must be reconfigured:

### 1. kubeadm Configuration

The cluster must be initialized (or reconfigured) with dual-stack CIDRs:

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
networking:
  podSubnet: "192.168.144.0/20,fc00:f1:d759:3053:a573::/64"
  serviceSubnet: "10.144.0.0/12,fd00::/108"
```

### 2. kube-controller-manager

Must be updated with dual-stack CIDRs:

```
--cluster-cidr=192.168.144.0/20,fc00:f1:d759:3053:a573::/64
--service-cluster-ip-range=10.144.0.0/12,fd00::/108
--node-cidr-mask-size-ipv4=24
--node-cidr-mask-size-ipv6=80
```

### 3. kube-apiserver

Must include IPv6 service CIDR:

```
--service-cluster-ip-range=10.144.0.0/12,fd00::/108
```

### 4. Cilium CNI

Already configured correctly with:

```yaml
ipv6:
  enabled: true
ipv6NativeRoutingCIDR: "fc00:f1:d759:3053:a573::/64"
```

### 5. Node Configuration

Each node must have IPv6 connectivity and routing configured at the host level.

## Migration Options

### Option 1: In-Place Control Plane Reconfiguration (Recommended)

**Status**: Supported since Kubernetes 1.21+ (cluster is running v1.34.1)

**Pros:**
- No cluster downtime required
- Applications continue running during migration
- Officially supported approach for Kubernetes 1.21+
- Faster than full reinstall

**Cons:**
- Requires careful manual editing of control plane manifests
- Must be done on each control plane node sequentially
- Temporary API server disruption during manifest changes

**Process:**
1. Update kubeadm ConfigMap with dual-stack CIDRs
2. Edit `/etc/kubernetes/manifests/kube-controller-manager.yaml` on each control plane node
3. Edit `/etc/kubernetes/manifests/kube-apiserver.yaml` on each control plane node
4. Static pods automatically restart with new configuration
5. Cilium already configured for IPv6
6. Nodes gradually receive IPv6 pod CIDRs

**Current Cluster State:**
- Kubernetes version: v1.34.1 ✅
- Control plane nodes: 5 (dungeon-map-001 through dungeon-map-005)
- Current pod CIDR: 192.168.144.0/20
- Current service CIDR: 10.144.0.0/12

### Option 2: Full Cluster Reinstall

**Pros:**
- Cleanest approach
- Guaranteed to work correctly
- Good opportunity to update bootstrap scripts

**Cons:**
- Requires full cluster downtime
- Must redeploy all applications
- More time-consuming
- Unnecessary given in-place support in v1.34.1

**Process:**
1. Update bootstrap scripts with dual-stack configuration
2. Tear down existing cluster
3. Reinitialize cluster with IPv6 enabled from the start
4. Redeploy all applications

**Recommendation**: Only use this if in-place migration fails.

### Option 3: Alternative Architecture (Not Acceptable)

The following alternatives were considered but rejected as they violate architectural principles:

- ❌ Configure Ceph monitors to listen on IPv4 (changes production Ceph cluster)
- ❌ Use a proxy pod with host networking (introduces single point of failure, complexity)
- ❌ Deploy separate IPv6-capable gateway (unnecessary complexity)

## Recommended Approach

**Option 1: In-Place Control Plane Reconfiguration** is recommended because:

1. Kubernetes v1.34.1 officially supports adding dual-stack to existing clusters
2. No application downtime required
3. Faster and less disruptive than full reinstall
4. Can be tested and rolled back if needed
5. Bootstrap scripts can still be updated for future cluster deployments

## Implementation Steps for In-Place Migration

### Prerequisites

1. Verify all control plane nodes have IPv6 connectivity
2. Verify all worker nodes have IPv6 connectivity
3. Backup `/etc/kubernetes/manifests/` on all control plane nodes
4. Backup kubeadm ConfigMap

### Step 1: Update kubeadm ConfigMap

```bash
kubectl edit cm -n kube-system kubeadm-config
```

Change:
```yaml
networking:
  podSubnet: 192.168.144.0/20
  serviceSubnet: 10.144.0.0/12
```

To:
```yaml
networking:
  podSubnet: 192.168.144.0/20,fc00:f1:d759:3053:a573::/64
  serviceSubnet: 10.144.0.0/12,fd00::/108
```

### Step 2: Update Control Plane Nodes (One at a Time)

For each control plane node (dungeon-map-001 through dungeon-map-005):

#### 2a. Edit kube-controller-manager manifest

```bash
ssh dungeon-map-001
sudo vi /etc/kubernetes/manifests/kube-controller-manager.yaml
```

Update the command section:
```yaml
spec:
  containers:
  - command:
    - kube-controller-manager
    - --cluster-cidr=192.168.144.0/20,fc00:f1:d759:3053:a573::/64
    - --service-cluster-ip-range=10.144.0.0/12,fd00::/108
    - --node-cidr-mask-size-ipv4=24
    - --node-cidr-mask-size-ipv6=80
    # ... rest of flags
```

#### 2b. Edit kube-apiserver manifest

```bash
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Update the command section:
```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --service-cluster-ip-range=10.144.0.0/12,fd00::/108
    # ... rest of flags
```

#### 2c. Wait for static pods to restart

```bash
# Watch for pods to restart (automatic when manifest changes)
kubectl get pods -n kube-system | grep -E 'kube-apiserver|kube-controller-manager'
```

#### 2d. Verify changes applied

```bash
kubectl get pod -n kube-system kube-controller-manager-dungeon-map-001 -o yaml | grep cluster-cidr
```

Should show both IPv4 and IPv6 CIDRs.

### Step 3: Repeat for All Control Plane Nodes

Complete Step 2 for dungeon-map-002, dungeon-map-003, dungeon-map-004, and dungeon-map-005.

### Step 4: Verify Dual-Stack Operation

```bash
# Check nodes have both IPv4 and IPv6 pod CIDRs
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDRs}{"\n"}{end}'

# Expected output: Each node should have two CIDRs (IPv4 and IPv6)
```

### Step 5: Restart Worker Nodes (Optional but Recommended)

Drain and reboot worker nodes to ensure they pick up IPv6 pod CIDRs:

```bash
kubectl drain dungeon-chest-001 --ignore-daemonsets --delete-emptydir-data
# Reboot the node
kubectl uncordon dungeon-chest-001
```

Repeat for all worker nodes.

### Step 6: Verify Pod IPv6 Connectivity

```bash
# Deploy test pod
kubectl run ipv6-test --image=nicolaka/netshoot --restart=Never -- sleep 3600

# Check pod has IPv6 address
kubectl exec ipv6-test -- ip -6 addr show

# Test IPv6 connectivity to Ceph monitors
kubectl exec ipv6-test -- ping6 -c 3 fc00:f1:ada:104e:1ace::1
```

## Alternative: Full Cluster Reinstall Steps

### 1. Update Bootstrap Configuration

Modify the kubeadm configuration in bootstrap scripts to include IPv6 CIDRs:

```yaml
networking:
  podSubnet: "192.168.144.0/20,fc00:f1:d759:3053:a573::/64"
  serviceSubnet: "10.144.0.0/12,fd00::/108"
```

### 2. Verify Node IPv6 Connectivity

Before cluster initialization, ensure all nodes have:
- IPv6 addresses configured
- IPv6 routing enabled
- Connectivity to external IPv6 networks

### 3. Reinitialize Cluster

Run the updated bootstrap scripts to create a dual-stack cluster.

### 4. Verify Dual-Stack Operation

After initialization, verify:

```bash
# Check nodes have IPv6 pod CIDRs
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDRs}'

# Check services can have IPv6 ClusterIPs
kubectl get svc kubernetes -o yaml

# Deploy test pod and verify IPv6 address
kubectl run test --image=busybox --restart=Never -- sleep 3600
kubectl exec test -- ip a
```

### 5. Redeploy Infrastructure

Use FluxCD to redeploy all infrastructure and applications.

## IPv6 Address Planning

| Component | IPv6 CIDR | Purpose |
|-----------|-----------|---------|
| Kubernetes Pods | `fc00:f1:d759:3053:a573::/64` | Pod network (internal) |
| Kubernetes Services | `fd00::/108` | Service ClusterIP range |
| External Ceph Cluster | `fc00:f1:ada:104e:1ace::/64` | External Ceph monitors |
| Node Network | `fc00:f1:ada:1043:1ac3::/64` | Node host networking |

Note: These ranges are non-overlapping to avoid routing conflicts.

## Current Status

- ✅ Rook operator deployed
- ✅ External Ceph RGW configured on Proxmox
- ✅ Cilium configured for IPv6 (awaiting cluster dual-stack support)
- ❌ CephCluster failing to connect (no IPv6 pod networking)
- ⏸️ Blocked on dual-stack cluster configuration

## Next Steps

1. Decision: Approve full cluster reinstall vs. attempt in-place migration
2. Update bootstrap scripts with dual-stack configuration
3. Schedule cluster downtime window
4. Execute cluster reinstall
5. Verify dual-stack operation
6. Resume Rook external Ceph integration
7. Complete Loki configuration with RGW S3 backend
