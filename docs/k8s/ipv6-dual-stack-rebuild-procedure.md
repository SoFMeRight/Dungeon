# IPv6 Dual-Stack Cluster Rebuild Procedure

## Overview
This document outlines the procedure to rebuild the Kubernetes cluster with full dual-stack IPv4/IPv6 support.

## Pre-Rebuild Checklist

### 1. Velero Backup
- ✅ Backup created: `pre-ipv6-dual-stack-rebuild`
- ✅ Status: PartiallyFailed (1543/1543 items backed up)
- ✅ All 77 PVs have `reclaimPolicy: Retain` - data is safe on Ceph
- Location: MinIO backup storage

### 2. Network Prerequisites
Configure IPv6 addresses on all nodes via pfSense DHCP/static assignments:

**Control Plane Nodes:**
- dungeon-map-001: `172.22.144.150` / `fc00:f1:ada:1043:1ac3::150`
- dungeon-map-002: `172.22.144.151` / `fc00:f1:ada:1043:1ac3::151`
- dungeon-map-003: `172.22.144.152` / `fc00:f1:ada:1043:1ac3::152`
- dungeon-map-004: `172.22.144.153` / `fc00:f1:ada:1043:1ac3::153`
- dungeon-map-005: `172.22.144.154` / `fc00:f1:ada:1043:1ac3::154`

**Worker Nodes:**
- dungeon-chest-001: `172.22.144.170` / `fc00:f1:ada:1043:1ac3::170`
- dungeon-chest-002: `172.22.144.171` / `fc00:f1:ada:1043:1ac3::171`
- dungeon-chest-003: `172.22.144.172` / `fc00:f1:ada:1043:1ac3::172`
- dungeon-chest-004: `172.22.144.173` / `fc00:f1:ada:1043:1ac3::173`
- dungeon-chest-005: `172.22.144.174` / `fc00:f1:ada:1043:1ac3::174`

**Control Plane VIP:**
- IPv4: `172.22.144.105`
- IPv6: `fc00:f1:ada:1043:1ac3::105` (kube-vip will manage)

### 3. Dual-Stack Configuration
The bootstrap script now includes:
- Pod CIDR IPv4: `192.168.144.0/20`
- Pod CIDR IPv6: `fc00:f1:0ca4:15a0:7i3e::/64`
- Service CIDR IPv4: `10.144.0.0/12`
- Service CIDR IPv6: `fc00:f1:7105:5e1d:a007::/108`

## Rebuild Steps

### Phase 1: Teardown (On each node)
```bash
# On all nodes (control plane + workers):
sudo kubeadm reset --force
sudo rm -rf /etc/kubernetes/
sudo rm -rf /var/lib/etcd/
sudo rm -rf ~/.kube/

# Remove the temporary VIP from control plane nodes if present
sudo ip addr del 172.22.144.105/32 dev enp6s18 || true
```

### Phase 2: Bootstrap First Control Plane Node
```bash
# On dungeon-map-002 (or chosen first control plane node):
cd /srv/ant_parade-public/bash/_importing_from_sibling_repo/

# Run install dependencies (if needed)
sudo ./bootstrap-k8s-install-dependencies.sh

# Initialize control plane with dual-stack
sudo ./bootstrap-k8s-initialize-control-plane.sh

# This will:
# - Initialize kubeadm with dual-stack CIDRs
# - Install Cilium with IPv6 enabled
# - Create join command at /tmp/kubeadm_join_cmd.sh
```

### Phase 3: Join Additional Control Plane Nodes
```bash
# On each remaining control plane node (dungeon-map-001,003,004,005):

# Copy the join command from the first node
# Then run:
sudo /tmp/kubeadm_join_cmd.sh --control-plane

# Wait for node to be Ready
kubectl get nodes
```

### Phase 4: Join Worker Nodes
```bash
# On each worker node (dungeon-chest-001 through 005):

# Copy the join command from the first node
# Then run:
sudo /tmp/kubeadm_join_cmd.sh

# Wait for node to be Ready
kubectl get nodes
```

### Phase 5: Deploy FluxCD
```bash
# On a control plane node with kubectl configured:
cd /srv/ant_parade-public/

# Bootstrap FluxCD (follow existing procedure)
flux bootstrap git \
  --url=ssh://git@10.30.1.123:2424/precisionplanit/dungeon \
  --branch=main \
  --path=fluxcd

# Wait for all kustomizations to reconcile
flux get kustomizations
```

### Phase 6: Restore from Velero
```bash
# Verify Velero is running
kubectl -n fairy-bottle get pods

# Create restore from backup
kubectl -n fairy-bottle create -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-from-pre-ipv6-rebuild
  namespace: fairy-bottle
spec:
  backupName: pre-ipv6-dual-stack-rebuild
  includedNamespaces:
  - "*"
  restorePVs: true
EOF

# Monitor restore progress
kubectl -n fairy-bottle get restore restore-from-pre-ipv6-rebuild -w

# Check for errors
kubectl -n fairy-bottle describe restore restore-from-pre-ipv6-rebuild
```

### Phase 7: Verify Cluster

```bash
# Check all nodes are Ready
kubectl get nodes -o wide

# Verify dual-stack pod IPs
kubectl get pods -A -o wide | grep -E "fc00:"

# Check PVs restored
kubectl get pv | wc -l  # Should show 77 PVs

# Verify services
kubectl get svc -A

# Check FluxCD status
flux get all
```

## Post-Rebuild Tasks

### 1. Update kube-vip for IPv6 VIP (if needed)
The kube-vip DaemonSet may need updating to advertise the IPv6 VIP `fc00:f1:ada:1043:1ac3::105` via BGP or NDP.

### 2. Verify Ceph Connectivity
```bash
# Check Ceph CSI pods can reach IPv6 monitors
kubectl -n gorons-bracelet get pods -l app=ceph-csi-rbd
kubectl -n gorons-bracelet logs <ceph-csi-pod> | grep -i "fc00:f1:ada:104e:1ace"
```

### 3. Test Application Connectivity
- Verify all applications are running
- Test ingress/gateway routing
- Verify external services (Ceph, SMTP, etc.)

## Rollback Plan
If the rebuild fails:
1. All data remains safe on Ceph (Retain policy)
2. Velero backup contains all manifests
3. Can rebuild again with IPv4-only if needed
4. Original cluster state documented in git history

## Important Notes
- The Ceph RBD volumes live on external Proxmox Ceph cluster - they are NOT deleted during cluster teardown
- All PVs have `reclaimPolicy: Retain` - Kubernetes metadata is removed but Ceph data persists
- FluxCD will reconcile all infrastructure and apps after restore
- Secrets managed by SOPS and Vault External Secrets will be restored automatically
- BGP peering with pfSense will re-establish automatically via Cilium

## Estimated Downtime
- Teardown: 15 minutes
- Bootstrap: 30 minutes
- FluxCD reconciliation: 20 minutes
- Velero restore: 30-60 minutes
- **Total: ~2 hours**
