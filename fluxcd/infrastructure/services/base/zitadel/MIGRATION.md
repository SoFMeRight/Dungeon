# Zitadel Docker to Kubernetes Migration Guide

## Prerequisites
1. Access to current Docker Zitadel instance
2. kubectl access to Kubernetes cluster
3. SOPS age key for encryption

## Migration Steps

### 1. Prepare Secrets
Before deploying, update and encrypt the secrets:

```bash
# Edit the secret files with actual values:
# - /srv/ant_parade-public/fluxcd/infrastructure/configs/base/zitadel/postgres-secrets.yaml
# - /srv/ant_parade-public/fluxcd/infrastructure/configs/base/zitadel/zitadel-masterkey.yaml (use your existing masterkey!)
# - /srv/ant_parade-public/fluxcd/infrastructure/configs/base/zitadel/zitadel-secrets.yaml

# Encrypt with SOPS
cd /srv/ant_parade-public/fluxcd/infrastructure/configs/base/zitadel/
for file in *.yaml; do
  if [[ ! "$file" =~ \.enc\.yaml$ ]]; then
    sops -e -i "$file"
    mv "$file" "${file%.yaml}.enc.yaml"
  fi
done

# Update kustomization.yaml to reference .enc.yaml files
```

### 2. Backup Docker Data
```bash
# On Docker host - backup PostgreSQL
docker exec zitadel_db_1 pg_dump -U postgres zitadel > zitadel_backup.sql

# Copy your masterkey (CRITICAL!)
echo $ZITADEL_MASTER_KEY > masterkey.txt
```

### 3. Deploy to Kubernetes
```bash
# Add to FluxCD
cd /srv/ant_parade-public
git add -A
git commit -m "Add Zitadel deployment"
git push

# Apply via Flux
flux reconcile source git flux-system -n optcp-gitops
flux reconcile kustomization infra-configs -n optcp-gitops
flux reconcile kustomization infra-controllers -n optcp-gitops
```

### 4. Wait for PostgreSQL
```bash
kubectl wait --for=condition=ready pod -l app=postgres -n zitadel --timeout=300s
```

### 5. Restore Database
```bash
# Copy backup to PostgreSQL pod
kubectl cp zitadel_backup.sql zitadel/postgres-0:/tmp/

# Restore database
kubectl exec -n zitadel postgres-0 -- psql -U postgres zitadel < /tmp/zitadel_backup.sql
```

### 6. Run Setup (if fresh install)
```bash
# For fresh install only:
kubectl apply -f /srv/ant_parade-public/fluxcd/infrastructure/controllers/base/zitadel/zitadel-initjob.yaml
kubectl apply -f /srv/ant_parade-public/fluxcd/infrastructure/controllers/base/zitadel/zitadel-setupjob.yaml

# Wait for jobs
kubectl wait --for=condition=complete job/zitadel-init -n zitadel --timeout=300s
kubectl wait --for=condition=complete job/zitadel-setup -n zitadel --timeout=300s
```

### 7. Start Zitadel
```bash
# Check deployment
kubectl get pods -n zitadel
kubectl logs -n zitadel -l app=zitadel

# Service should be available at:
# http://172.22.30.140:8080
```

### 8. Update DNS/Reverse Proxy
Point your domain to the new LoadBalancer IP (172.22.30.140)

### 9. Verify
- Login with existing credentials
- Check user data is intact
- Test authentication flows

### 10. Decommission Docker Instance
Once verified, stop and remove Docker containers.

## Rollback Plan
If issues occur:
1. Keep Docker instance running until verified
2. PostgreSQL data is on PVC - can restore from backup
3. Can quickly switch DNS back to Docker instance

## Important Files
- Masterkey: MUST be the same as Docker instance
- Database: Contains all user data, organizations, configs
- Domain: Must match for existing sessions to work
