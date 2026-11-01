# GitLab Complete Migration Guide

Migrating from external Docker GitLab CE 18.2.1 to Kubernetes GitLab with ALL data (repos, issues, MRs, CI/CD history, container registry, uploads, artifacts).

## Current State

- **External GitLab**: 18.2.1-ce (Docker Compose)
- **K8s GitLab**: 17.6.1-ce (Helm chart 8.6.1) - **NEEDS UPGRADE**
- **Target**: K8s GitLab 18.2.8+ (Helm chart 9.2.8+)

## Migration Overview

1. Upgrade K8s GitLab to 18.2.8+ (same major version as external)
2. Create full backup on external GitLab
3. Copy backup and secrets to K8s
4. Restore backup in K8s GitLab
5. Verify all data migrated correctly
6. Update DNS/configuration to point to K8s GitLab
7. Decommission external GitLab

**Estimated Downtime**: 30-60 minutes (for restore phase)

---

## Phase 1: Upgrade K8s GitLab (No Downtime)

### Step 1.1: Backup Current K8s GitLab (Safety)

```bash
# Create backup of current K8s GitLab (just in case)
TOOLBOX_POD=$(kubectl get pods -n hyrule-castle -l app=toolbox -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-backup create

# Download backup for safekeeping
kubectl exec -n hyrule-castle $TOOLBOX_POD -- ls -lh /var/opt/gitlab/backups/
kubectl cp hyrule-castle/$TOOLBOX_POD:/var/opt/gitlab/backups/<timestamp>_gitlab_backup.tar ./k8s-gitlab-backup-before-upgrade.tar
```

### Step 1.2: Update GitLab Helm Chart Version

```bash
cd /srv/dungeon

# Edit the HelmRelease to update chart version
# File: fluxcd/infrastructure/controllers/overlays/production/gitlab/helmrelease-patch.yaml
```

Update the chart version from `8.6.1` to `9.2.8`:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: gitlab
spec:
  chart:
    spec:
      version: 9.2.8  # Was 8.6.1
```

### Step 1.3: Commit and Deploy Upgrade

```bash
git add fluxcd/infrastructure/controllers/overlays/production/gitlab/helmrelease-patch.yaml
git commit -m "Upgrade GitLab to v18.2.8 (chart 9.2.8) for migration compatibility"
git push

# Reconcile FluxCD to trigger upgrade
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-controllers -n flux-system
```

### Step 1.4: Monitor Upgrade Progress

```bash
# Watch HelmRelease status (will take 15-30 minutes)
watch flux get helmreleases -n hyrule-castle gitlab

# Watch pods rolling out
kubectl get pods -n hyrule-castle -w

# Check for upgrade completion
kubectl exec -n hyrule-castle $(kubectl get pods -n hyrule-castle -l app=toolbox -o jsonpath='{.items[0].metadata.name}') -- cat /srv/gitlab/VERSION
# Should show: 18.2.8

# Verify GitLab is healthy after upgrade
kubectl get pods -n hyrule-castle | grep gitlab
# All pods should be Running
```

**WAIT** for upgrade to complete successfully before proceeding to Phase 2.

---

## Phase 2: Backup External GitLab

### Step 2.1: Create Full Backup

On your external GitLab server:

```bash
# Find GitLab container name
docker ps | grep gitlab

# Create backup (will take time proportional to data size)
docker exec -t <gitlab-container-name> gitlab-backup create STRATEGY=copy

# Check backup was created
docker exec -t <gitlab-container-name> ls -lh /var/opt/gitlab/backups/
# Should show: <timestamp>_gitlab_backup.tar
```

### Step 2.2: Extract Critical Secrets

```bash
# Copy gitlab-secrets.json (CRITICAL - contains encryption keys)
docker cp <gitlab-container-name>:/etc/gitlab/gitlab-secrets.json ./gitlab-secrets.json

# Copy gitlab.rb config (for reference)
docker cp <gitlab-container-name>:/etc/gitlab/gitlab.rb ./gitlab.rb

# Verify secrets file exists and is not empty
ls -lh gitlab-secrets.json
# Should be several KB, NOT empty
```

### Step 2.3: Copy Backup File to Local Machine

```bash
# Get backup filename
BACKUP_FILE=$(docker exec <gitlab-container-name> ls -t /var/opt/gitlab/backups/ | head -1)
echo "Backup file: $BACKUP_FILE"

# Copy backup from container
docker cp <gitlab-container-name>:/var/opt/gitlab/backups/$BACKUP_FILE ./$BACKUP_FILE

# Verify backup file integrity
ls -lh $BACKUP_FILE
# Should show actual size, not 0 bytes
```

### Step 2.4: Optional - Stop External GitLab

To ensure data consistency and prevent new data being created during migration:

```bash
# Stop external GitLab (makes it read-only)
docker stop <gitlab-container-name>

# Or just disable new signups/commits in GitLab UI:
# Admin → Settings → General → Sign-up restrictions → Sign-ups enabled: OFF
```

---

## Phase 3: Restore to K8s GitLab

### Step 3.1: Copy Backup to K8s GitLab Toolbox Pod

```bash
# Get toolbox pod name
TOOLBOX_POD=$(kubectl get pods -n hyrule-castle -l app=toolbox -o jsonpath='{.items[0].metadata.name}')
echo "Toolbox pod: $TOOLBOX_POD"

# Copy backup file (may take time depending on size)
kubectl cp ./$BACKUP_FILE hyrule-castle/$TOOLBOX_POD:/var/opt/gitlab/backups/

# Copy secrets file
kubectl cp ./gitlab-secrets.json hyrule-castle/$TOOLBOX_POD:/tmp/gitlab-secrets.json

# Verify files copied successfully
kubectl exec -n hyrule-castle $TOOLBOX_POD -- ls -lh /var/opt/gitlab/backups/
kubectl exec -n hyrule-castle $TOOLBOX_POD -- ls -lh /tmp/gitlab-secrets.json
```

### Step 3.2: Stop K8s GitLab Services

**DOWNTIME BEGINS HERE**

```bash
# Scale down all GitLab services (prevents conflicts during restore)
kubectl scale deployment -n hyrule-castle \
  gitlab-webservice-default \
  gitlab-sidekiq-all-in-1-v2 \
  gitlab-registry \
  gitlab-gitlab-shell \
  gitlab-kas \
  --replicas=0

# Verify all stopped
kubectl get pods -n hyrule-castle | grep -E "webservice|sidekiq|registry|shell|kas"
# Should show no running pods (or terminating)
```

### Step 3.3: Restore GitLab Secrets

```bash
# Backup current secrets (just in case)
kubectl exec -n hyrule-castle $TOOLBOX_POD -- cp /etc/gitlab/gitlab-secrets.json /tmp/gitlab-secrets.json.k8s-backup

# Restore external GitLab secrets
kubectl exec -n hyrule-castle $TOOLBOX_POD -- cp /tmp/gitlab-secrets.json /etc/gitlab/gitlab-secrets.json

# Verify secrets file is in place
kubectl exec -n hyrule-castle $TOOLBOX_POD -- cat /etc/gitlab/gitlab-secrets.json | jq .
# Should show JSON with db_key_base, secret_key_base, otp_key_base, etc.
```

### Step 3.4: Run Backup Restore

```bash
# Extract timestamp from backup filename
# Example: 1730486400_2024_11_01_18.2.1_gitlab_backup.tar
BACKUP_TIMESTAMP=$(echo $BACKUP_FILE | sed 's/_gitlab_backup.tar//')
echo "Backup timestamp: $BACKUP_TIMESTAMP"

# Restore backup (will take time - 15-45 minutes depending on size)
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-backup restore BACKUP=$BACKUP_TIMESTAMP force=yes

# Watch for restore progress in logs
kubectl logs -n hyrule-castle $TOOLBOX_POD -f
```

Expected output during restore:
```
Unpacking backup
Restoring database
Restoring repositories
Restoring uploads
Restoring builds
Restoring artifacts
Restoring lfs objects
Restoring container registry images
...
Restore task is done.
```

### Step 3.5: Reconfigure GitLab

```bash
# Run reconfigure to apply secrets and settings
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-ctl reconfigure

# Wait for reconfigure to complete (2-5 minutes)
```

### Step 3.6: Restart GitLab Services

```bash
# Scale up all services
kubectl scale deployment -n hyrule-castle \
  gitlab-webservice-default --replicas=3 \
  gitlab-sidekiq-all-in-1-v2 --replicas=3 \
  gitlab-registry --replicas=3 \
  gitlab-gitlab-shell --replicas=3 \
  gitlab-kas --replicas=3

# Wait for all pods to be ready (5-10 minutes)
kubectl wait --for=condition=ready pod -l app=webservice -n hyrule-castle --timeout=600s
kubectl wait --for=condition=ready pod -l app=sidekiq -n hyrule-castle --timeout=600s

# Check all pods are running
kubectl get pods -n hyrule-castle | grep gitlab
```

**DOWNTIME ENDS HERE** (if all pods are healthy)

---

## Phase 4: Verification

### Step 4.1: Check GitLab Version

```bash
kubectl exec -n hyrule-castle $TOOLBOX_POD -- cat /srv/gitlab/VERSION
# Should show: 18.2.8 (or the version you upgraded to)
```

### Step 4.2: Verify Database Connectivity

```bash
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-rake gitlab:check

# Should show:
# Checking GitLab ... Finished
# All checks passed
```

### Step 4.3: Verify Data via UI

Access https://git.optcp.com and verify:

1. **Login works** with existing credentials
2. **All projects** are visible
3. **Repositories** can be browsed
4. **Issues and Merge Requests** are present
5. **CI/CD pipelines** history is intact
6. **Container Registry** images are accessible
7. **Wiki pages** are available
8. **Uploads** (images in issues/comments) load correctly

### Step 4.4: Test Git Operations

```bash
# Test clone via HTTPS
git clone https://git.optcp.com/<group>/<project>.git
cd <project>
git log  # Should show full commit history

# Test clone via SSH (port 2424)
git clone ssh://git@git.optcp.com:2424/<group>/<project>.git
```

### Step 4.5: Verify Container Registry

```bash
# Login to registry
docker login registry.git.optcp.com

# Pull an existing image
docker pull registry.git.optcp.com/<group>/<project>/<image>:tag
```

### Step 4.6: Check Background Jobs

```bash
# Verify Sidekiq is processing jobs
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-rake gitlab:sidekiq:check

# Check for any stuck jobs
kubectl logs -n hyrule-castle -l app=sidekiq --tail=100
```

---

## Phase 5: Finalization

### Step 5.1: Update Application Configurations

If you have applications using GitLab OAuth/OIDC (like in Zitadel), update redirect URIs if needed.

### Step 5.2: Update CI/CD Runner Registrations

If using external GitLab Runners:

```bash
# Unregister runners from old GitLab
gitlab-runner unregister --all-runners

# Register to new K8s GitLab
gitlab-runner register \
  --url https://git.optcp.com \
  --registration-token <new-token>
```

K8s GitLab already has a built-in runner deployed.

### Step 5.3: Update DNS (if applicable)

If external GitLab was on a different domain/IP:

1. Update DNS records to point git.optcp.com to K8s LoadBalancer (172.22.30.71)
2. Wait for DNS propagation (5-60 minutes)

### Step 5.4: Monitor for Issues

```bash
# Watch logs for errors
kubectl logs -n hyrule-castle -l app=webservice --tail=100 -f
kubectl logs -n hyrule-castle -l app=sidekiq --tail=100 -f

# Check for failed background jobs
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-rails console
# In console:
# Sidekiq::DeadSet.new.size  # Should be 0 or low
```

---

## Phase 6: Decommission External GitLab

**ONLY after 7-14 days of successful K8s GitLab operation:**

### Step 6.1: Create Final Backup of External GitLab

```bash
# One last backup for archival
docker exec -t <gitlab-container-name> gitlab-backup create
docker cp <gitlab-container-name>:/var/opt/gitlab/backups/<timestamp>_gitlab_backup.tar ./final-external-gitlab-backup.tar

# Store in secure location (Ceph, off-site backup, etc.)
```

### Step 6.2: Stop External GitLab

```bash
docker stop <gitlab-container-name>
docker rm <gitlab-container-name>

# Optional: Keep data volume for 30 days
# docker volume ls | grep gitlab
# Don't delete volumes yet - wait 30 days for safety
```

---

## Rollback Procedure

If migration fails and you need to restore external GitLab:

```bash
# Start external GitLab container
docker start <gitlab-container-name>

# Or if deleted, recreate from docker-compose
cd /path/to/gitlab/docker-compose
docker-compose up -d

# Verify external GitLab is accessible
curl -I https://<external-gitlab-url>
```

---

## Troubleshooting

### Restore Fails: "Backup is from a different version"

**Cause**: K8s GitLab version doesn't match backup version closely enough

**Fix**:
```bash
# Check versions
kubectl exec -n hyrule-castle $TOOLBOX_POD -- cat /srv/gitlab/VERSION
# Compare to backup version in filename (e.g., 18.2.1)

# If K8s is older: Upgrade K8s GitLab (Phase 1)
# If K8s is newer: Should work (GitLab supports forward compatibility)
```

### Restore Fails: "Permissions denied"

**Cause**: Ownership issues on backup files

**Fix**:
```bash
kubectl exec -n hyrule-castle $TOOLBOX_POD -- chown -R git:git /var/opt/gitlab/backups/
kubectl exec -n hyrule-castle $TOOLBOX_POD -- chmod 0600 /var/opt/gitlab/backups/*.tar
```

### Secrets Not Applied

**Symptom**: Can't login, encryption errors, "500 Internal Server Error"

**Fix**:
```bash
# Verify secrets file is correct
kubectl exec -n hyrule-castle $TOOLBOX_POD -- cat /etc/gitlab/gitlab-secrets.json

# Ensure it has these keys: db_key_base, secret_key_base, otp_key_base, openid_connect_signing_key
# If missing or wrong, recopy from external GitLab

# Reconfigure after fixing secrets
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-ctl reconfigure
kubectl scale deployment -n hyrule-castle gitlab-webservice-default --replicas=0
kubectl scale deployment -n hyrule-castle gitlab-webservice-default --replicas=3
```

### Container Registry Images Missing

**Cause**: Registry data not in backup or restore failed

**Check**:
```bash
kubectl exec -n hyrule-castle $TOOLBOX_POD -- ls -la /var/opt/gitlab/gitlab-rails/shared/registry/

# If empty, registry wasn't backed up/restored properly
```

**Fix**: Re-run restore or manually migrate registry data

### Database Connection Errors

**Symptom**: GitLab won't start, shows DB connection errors

**Fix**:
```bash
# Check PostgreSQL is running
kubectl get pods -n hyrule-castle | grep postgresql
# All should be Running

# Check database credentials in secrets
kubectl get secret -n hyrule-castle gitlab-postgresql -o jsonpath='{.data.password}' | base64 -d

# Test connection from toolbox
kubectl exec -n hyrule-castle $TOOLBOX_POD -- gitlab-rake gitlab:db:check_config
```

---

## Important Notes

1. **gitlab-secrets.json is CRITICAL**: Without this file, you cannot decrypt data (passwords, tokens, encrypted variables). Keep multiple copies in secure locations.

2. **Version Matching**: GitLab is strict about version compatibility. Always upgrade K8s GitLab to match or exceed external GitLab version before restoring.

3. **Downtime**: Plan for 30-60 minute maintenance window during restore phase (Phase 3).

4. **Backup Size**: Restore time scales with backup size. 10GB backup ≈ 20-30 minutes restore time.

5. **Testing**: After migration, test ALL critical workflows:
   - Git push/pull
   - CI/CD pipelines
   - Container registry
   - Merge requests
   - Issue tracking
   - Wiki

6. **Keep External GitLab**: Don't delete external GitLab immediately. Keep it available (stopped) for at least 7-14 days in case you discover issues.

---

## Reference

- GitLab Backup Documentation: https://docs.gitlab.com/ee/administration/backup_restore/
- GitLab Upgrade Documentation: https://docs.gitlab.com/ee/update/
- GitLab Helm Chart: https://docs.gitlab.com/charts/
