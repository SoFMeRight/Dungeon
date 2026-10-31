# GitLab HA Setup on Kubernetes

## Architecture
- **Namespace**: optcp-supply-chain
- **Domain**: gitlab.prplanit.com
- **SSH Port**: 2424
- **Storage**: Ceph RBD (SSD-backed) + Ceph RGW S3 for objects

## High Availability Configuration
- **Gitaly Cluster**: 3 replicas (3×20Gi RBD)
- **PostgreSQL**: 1 master + 2 replicas (3×20Gi RBD)
- **Redis**: 1 master + 2 replicas with Sentinel (3×5Gi RBD)
- **Webservice**: 3 replicas (stateless)
- **Sidekiq**: 2 replicas (stateless)
- **GitLab Shell**: 2 replicas (stateless)

Total RBD Storage: ~135Gi on SSDs

## Vault Secrets Required

### 1. GitLab App Secrets
Path: `apps/gitlab`

Required keys:
```
root_password: <your existing root password from /mnt/app_data/Server/_docker_stack/gitlab/root_password.txt>
s3_access_key: <Ceph RGW access key>
s3_secret_key: <Ceph RGW secret key>
```

### 2. Create S3 Buckets in Ceph RGW

Run these commands on a node with RGW access:
```bash
# Install s3cmd or use radosgw-admin to create buckets
s3cmd mb s3://gitlab-lfs
s3cmd mb s3://gitlab-artifacts
s3cmd mb s3://gitlab-uploads
s3cmd mb s3://gitlab-packages
s3cmd mb s3://gitlab-backups
s3cmd mb s3://gitlab-tmp
s3cmd mb s3://gitlab-registry
```

## Deployment Steps

1. **Add secrets to Vault**:
   - Navigate to http://172.22.30.102:8200/ui/vault/secrets/operationtimecapsule/kv/list
   - Create secret at path `apps/gitlab` with the three keys above

2. **Create FluxCD Kustomization**:
   ```yaml
   # Add to fluxcd/clusters/production/apps.yaml
   - apiVersion: kustomize.toolkit.fluxcd.io/v1
     kind: Kustomization
     metadata:
       name: gitlab
       namespace: flux-system
     spec:
       interval: 10m
       path: ./fluxcd/apps/overlays/production/gitlab
       prune: true
       sourceRef:
         kind: GitRepository
         name: flux-system
   ```

3. **Commit and push changes**:
   ```bash
   git add fluxcd/apps/base/gitlab fluxcd/apps/overlays/production/gitlab
   git commit -m "Add GitLab HA deployment"
   git push
   ```

4. **Wait for deployment** (30+ minutes for initial deployment):
   ```bash
   # Watch HelmRelease
   flux get helmreleases -n optcp-supply-chain gitlab

   # Watch pods
   kubectl get pods -n optcp-supply-chain -w
   ```

## Migration from Docker Compose

### Current VM Data Location
```
/opt/docker/gitlab/
├── config/   -> /etc/gitlab
├── logs/     -> /var/log/gitlab
└── data/     -> /var/opt/gitlab
```

### Migration Steps

1. **Backup current data** (8.1GB total):
   ```bash
   sudo rsync -avz /opt/docker/gitlab/ kai@dungeon-map-002:/mnt/ceph-treasure-chest/gitlab-backup/
   ```

2. **Wait for GitLab to be running in K8s** (fresh install)

3. **Stop GitLab in K8s temporarily**:
   ```bash
   kubectl scale deployment -n optcp-supply-chain gitlab-webservice-default --replicas=0
   kubectl scale deployment -n optcp-supply-chain gitlab-sidekiq-all-in-1-v2 --replicas=0
   ```

4. **Restore data to Gitaly pods**:
   - Use a temporary pod to mount Gitaly PVCs
   - Rsync data from backup location
   - Restart GitLab

5. **Verify**:
   - Access https://gitlab.prplanit.com
   - Test SSH: `ssh -T git@gitlab.prplanit.com -p 2424`
   - Clone a repository
   - Verify all data is present

## Network Configuration

- **HTTPS**: Via cell-membrane-gateway (172.22.30.71) on port 443
- **SSH**: Via LoadBalancer (172.22.30.71) on port 2424
- Both share the same IP using Cilium LBIPAM sharing-key: hyrule-castle

## pfSense Port Forwards Required

Ensure these are forwarded to 172.22.30.71:
- TCP 443 (HTTPS) - Already configured for hyrule-castle gateway
- TCP 2424 (SSH) - New port forward needed
