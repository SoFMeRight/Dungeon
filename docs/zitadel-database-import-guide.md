# Zitadel Database Import Guide

This guide covers manually importing a Zitadel database dump into a Kubernetes-deployed Zitadel instance, including creating service account credentials and configuring Login-v2.

## Overview

This procedure is useful when:
- Migrating from Docker Zitadel to Kubernetes Zitadel
- Restoring from a backup
- Importing data from another Zitadel instance

**Important**: This is a destructive operation that will replace all existing data in the target Zitadel instance.

## Prerequisites

1. PostgreSQL database dump from source Zitadel instance
2. kubectl access to target Kubernetes cluster
3. Zitadel deployed via CloudNativePG in namespace `zeldas-lullaby`
4. Access to Zitadel UI for creating service account tokens

## Step 1: Prepare Database Dump

Export your source Zitadel database:

```bash
# Docker Zitadel
docker exec <postgres-container> pg_dump -U postgres zitadel > zitadel-dump.sql

# Kubernetes Zitadel (if backing up current)
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  pg_dump -U postgres zitadel > zitadel-backup.sql
```

Verify the dump file:
```bash
ls -lh zitadel-dump.sql
head -20 zitadel-dump.sql  # Should show PostgreSQL dump header
```

## Step 2: Scale Down Zitadel

Prevent data corruption by stopping all Zitadel processes:

```bash
# Scale down Zitadel StatefulSet
kubectl scale statefulset -n zeldas-lullaby zitadel --replicas=0

# Scale down Login-v2 (if deployed)
kubectl scale deployment -n zeldas-lullaby zitadel-login-v2 --replicas=0

# Verify pods are terminated
kubectl get pods -n zeldas-lullaby | grep zitadel
```

Wait until all Zitadel pods show `0/1` or are completely gone.

## Step 3: Drop and Recreate Database

**CRITICAL**: This step will permanently delete all existing Zitadel data. Ensure you have backups.

```bash
# Drop existing database (--force kills active connections)
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  dropdb -U postgres --force zitadel

# Recreate empty database with correct ownership
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  createdb -U postgres -O zitadel zitadel

# Verify database exists and is empty
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -c "\dt"
# Should show: "Did not find any relations."
```

## Step 4: Restore Database Dump

Import your database dump:

```bash
# Copy dump file to PostgreSQL pod
kubectl cp zitadel-dump.sql zeldas-lullaby/zitadel-postgres-1:/tmp/

# Restore dump (use postgres superuser to avoid permission issues)
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -f /tmp/zitadel-dump.sql

# Clean up dump file from pod
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  rm /tmp/zitadel-dump.sql
```

Common errors:
- `Peer authentication failed for user "zitadel"` → Use `-U postgres` instead
- `database "zitadel" is being accessed by other users` → Scale down Zitadel first (Step 2)

## Step 5: Verify Database Import

Check that critical data was imported:

```bash
# List instances
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -c \
  "SELECT id, name, creation_date FROM projections.instances;"

# List organizations
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -c \
  "SELECT id, name, resource_owner FROM projections.orgs1;"

# List users (human)
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -c \
  "SELECT u.id, u.username, h.email FROM projections.users14 u \
   JOIN projections.users14_humans h ON u.id = h.user_id LIMIT 10;"

# List service accounts (machine users)
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -c \
  "SELECT u.id, u.username, m.name, m.description FROM projections.users14 u \
   JOIN projections.users14_machines m ON u.id = m.user_id;"
```

Expected output:
- At least 1 instance
- Your organizations should be listed
- Your users should be present
- Service accounts may or may not exist depending on source

## Step 6: Scale Up Zitadel

Restart Zitadel with imported data:

```bash
# Scale up Zitadel StatefulSet
kubectl scale statefulset -n zeldas-lullaby zitadel --replicas=3

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zitadel \
  -n zeldas-lullaby --timeout=300s

# Check logs for errors
kubectl logs -n zeldas-lullaby -l app.kubernetes.io/name=zitadel --tail=50
```

Verify Zitadel is accessible:
```bash
# Get service endpoint
kubectl get svc -n zeldas-lullaby zitadel

# Test login at https://sso.optcp.com (or your domain)
```

## Step 7: Create Service Account PAT Tokens

After importing a database, service account Personal Access Tokens (PATs) will NOT be included in the dump. You must create new tokens.

### Required Service Accounts

1. **login-client** - Used by Login-v2 UI
2. **dungeon-k8s-admin** - Used for Kubernetes API integration

### Create PAT Tokens via Zitadel UI

1. Navigate to https://sso.optcp.com (your Zitadel domain)
2. Login with admin credentials
3. Go to **Organization** → **Service Users**
4. For each service account (`login-client` and `dungeon-k8s-admin`):
   - Click on the service account
   - Navigate to **Personal Access Tokens** tab
   - Click **New**
   - Set **Expiration Date**: `2029-01-01` (or appropriate date)
   - Click **Add**
   - **CRITICAL**: Copy the token immediately - it will only be shown once
   - Save token securely (password manager or temporary file)

### If Service Accounts Don't Exist

If the service accounts weren't in your imported database, create them:

1. Go to **Organization** → **Service Users** → **New**
2. Create `login-client`:
   - **User Name**: `login-client`
   - **Name**: `Login UI Client Service Account`
   - **Description**: `Service account for Login v2 UI client authentication`
   - **Access Token Type**: JWT
   - Click **Create**
3. Grant role **IAM_OWNER** (System Roles tab)
4. Create PAT token as described above
5. Repeat for `dungeon-k8s-admin`:
   - **User Name**: `dungeon-k8s-admin`
   - **Name**: `Dungeon K8s Admin SA`
   - **Description**: `Admin service account for Kubernetes integration and API management`
   - **Access Token Type**: JWT
   - Grant **IAM_OWNER** role
   - Create PAT token

## Step 8: Update Kubernetes Secrets

Update the secrets with the new PAT tokens:

```bash
# Delete old secrets (if they exist)
kubectl delete secret -n zeldas-lullaby \
  zitadel-login-client \
  zitadel-k8s-admin-sa \
  --ignore-not-found=true

# Create login-client secret
kubectl create secret generic zitadel-login-client -n zeldas-lullaby \
  --from-literal=pat='<LOGIN_CLIENT_PAT_TOKEN>'

# Create k8s-admin-sa secret
kubectl create secret generic zitadel-k8s-admin-sa -n zeldas-lullaby \
  --from-literal=pat='<K8S_ADMIN_PAT_TOKEN>'

# Verify secrets were created
kubectl get secrets -n zeldas-lullaby | grep zitadel
```

Replace `<LOGIN_CLIENT_PAT_TOKEN>` and `<K8S_ADMIN_PAT_TOKEN>` with the actual tokens from Step 7.

## Step 9: Enable and Configure Login-v2

### Verify Login-v2 Instance Feature

Check if Login-v2 is enabled in your imported instance:

```bash
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -c \
  "SELECT instance_id, key, value FROM projections.instance_features2 WHERE key = 'login_v2';"
```

If no results or `required: false`, enable Login-v2:

1. Login to Zitadel UI as admin
2. Navigate to **Instance Settings** → **Login Settings**
3. Find **Login V2** section
4. Set **Login V2 Base URI**: `http://zitadel-login-v2:3000`
5. Check **Required**
6. Click **Save**

### Deploy/Restart Login-v2

```bash
# Scale up Login-v2 deployment
kubectl scale deployment -n zeldas-lullaby zitadel-login-v2 --replicas=3

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=zitadel-login-v2 \
  -n zeldas-lullaby --timeout=120s

# Check logs for authentication errors
kubectl logs -n zeldas-lullaby -l app.kubernetes.io/name=zitadel-login-v2 --tail=50
```

Expected output: Clean startup with no `Errors.Token.Invalid` messages.

If you see authentication errors:
- Verify PAT token in secret matches the token created in Zitadel UI
- Verify service account has IAM_OWNER role
- Verify PAT token hasn't expired

## Step 10: Verification

### Test Login Flow

1. Navigate to https://sso.optcp.com
2. Should redirect to Login-v2 UI at `/ui/v2/login`
3. Login with user credentials from imported database
4. Verify successful login and correct organization

### Check Service Accounts

```bash
# Verify no authentication errors in login-v2 logs
kubectl logs -n zeldas-lullaby -l app.kubernetes.io/name=zitadel-login-v2 --tail=100 | grep -i error

# Should show no "Errors.Token.Invalid" messages
```

### Verify Data Integrity

1. Check all expected organizations exist
2. Verify users can login
3. Check applications and projects are present
4. Test authentication flows with connected applications

## Troubleshooting

### Login-v2 Shows 500 Error

**Symptoms**: Accessing `/ui/v2/login` shows "500 Internal Server Error"

**Cause**: Invalid or missing PAT token for `login-client` service account

**Fix**:
1. Check login-v2 logs for authentication errors:
   ```bash
   kubectl logs -n zeldas-lullaby -l app.kubernetes.io/name=zitadel-login-v2 --tail=200 | grep -i token
   ```
2. If you see `Errors.Token.Invalid (AUTH-7fs1e)`:
   - Create new PAT token in Zitadel UI (Step 7)
   - Update secret (Step 8)
   - Restart login-v2: `kubectl rollout restart deployment -n zeldas-lullaby zitadel-login-v2`

### "User not found in the system"

**Cause**: User exists in imported database but may be in different instance/organization

**Fix**:
1. Verify which instance is active:
   ```bash
   kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
     psql -U postgres -d zitadel -c \
     "SELECT id, name FROM projections.instances;"
   ```
2. Check user's instance:
   ```bash
   kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
     psql -U postgres -d zitadel -c \
     "SELECT id, username, instance_id FROM projections.users14 WHERE username = '<username>';"
   ```
3. Verify domain routing matches instance

### Database Restore Fails with Permission Errors

**Cause**: Using `zitadel` user instead of `postgres` superuser

**Fix**: Always use `-U postgres` for database operations:
```bash
kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
  psql -U postgres -d zitadel -f /tmp/dump.sql
```

### "Database is being accessed by other users"

**Cause**: Zitadel pods still running and connected to database

**Fix**: Scale down Zitadel completely before dropping database:
```bash
kubectl scale statefulset -n zeldas-lullaby zitadel --replicas=0
kubectl scale deployment -n zeldas-lullaby zitadel-login-v2 --replicas=0
kubectl get pods -n zeldas-lullaby | grep zitadel  # Verify no pods running
```

## Important Notes

1. **PAT Tokens Are Not Exported**: Database dumps do NOT include Personal Access Token values for security reasons. You must create new tokens after import.

2. **Instance vs Organization**: Zitadel has instances (top-level) and organizations (within instances). Service accounts with IAM_OWNER role work across all organizations in an instance.

3. **Login-v2 Requirement**: If your imported data has Login-v2 required but base URI not set, authentication will fail. Always configure Login-v2 settings after import.

4. **Masterkey Consistency**: The Zitadel masterkey in Kubernetes MUST match the masterkey from the source instance. Data is encrypted with this key.

5. **Clean Import**: Always drop and recreate the database before restore. Partial restores or merging with existing data causes conflicts and corruption.

6. **Backup Before Import**: Always backup the current database before importing. You can't undo a database restore.

## Recovery Procedure

If import fails or causes issues:

1. Scale down Zitadel:
   ```bash
   kubectl scale statefulset -n zeldas-lullaby zitadel --replicas=0
   ```

2. Drop and recreate database:
   ```bash
   kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- dropdb -U postgres --force zitadel
   kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- createdb -U postgres -O zitadel zitadel
   ```

3. Restore from backup:
   ```bash
   kubectl cp zitadel-backup.sql zeldas-lullaby/zitadel-postgres-1:/tmp/
   kubectl exec -n zeldas-lullaby zitadel-postgres-1 -- \
     psql -U postgres -d zitadel -f /tmp/zitadel-backup.sql
   ```

4. Scale up Zitadel:
   ```bash
   kubectl scale statefulset -n zeldas-lullaby zitadel --replicas=3
   ```

## References

- CloudNativePG Documentation: https://cloudnative-pg.io/
- Zitadel Service Accounts: https://zitadel.com/docs/guides/integrate/service-users
- Zitadel Login-v2: https://zitadel.com/docs/guides/integrate/login-ui
