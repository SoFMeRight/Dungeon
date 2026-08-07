# Vault Setup Guide

## Architecture

This implements a three-layer secret management approach:
- **Layer 1**: Age-encrypted SOPS for Vault unseal keys
- **Layer 2**: Vault for centralized secret management
- **Layer 3**: External Secrets Operator to sync secrets to Kubernetes

## Initial Setup

### 1. Deploy Vault

The Vault deployment will be created by Flux. After deployment:

```bash
# Port-forward to access Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Or access via LoadBalancer
# http://172.22.30.102:8200
```

### 2. Initialize Vault

```bash
# Initialize Vault (do this only once!)
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3

# Save the output! You'll get:
# - 5 unseal keys
# - 1 root token
```

### 3. Store Unseal Keys in SOPS

Edit the vault-unseal-keys.enc.yaml file with the keys from initialization:

```bash
# Edit the file
vim vault-unseal-keys.enc.yaml

# Encrypt with SOPS
sops --encrypt --in-place vault-unseal-keys.enc.yaml
```

### 4. Unseal Vault

```bash
# Unseal Vault (need 3 of the 5 keys)
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-1>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-2>
kubectl exec -n vault vault-0 -- vault operator unseal <unseal-key-3>
```

### 5. Configure Vault

```bash
# Login with root token
export VAULT_TOKEN=<root-token>
export VAULT_ADDR=http://localhost:8200

# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Create a policy for External Secrets
vault policy write external-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF

# Create token for External Secrets
vault token create -policy=external-secrets -ttl=87600h
```

### 6. Configure External Secrets

Create the token secret for External Secrets:

```bash
kubectl create secret generic vault-token \
  -n external-secrets \
  --from-literal=token=<token-from-step-5>
```

### 7. Apply ClusterSecretStore

```bash
kubectl apply -f clustersecretstore.yaml
```

## Usage

### Creating Secrets in Vault

```bash
# Create a secret in Vault
vault kv put secret/database \
  username=myuser \
  password=mypassword
```

### Consuming Secrets in Kubernetes

Create an ExternalSecret resource:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-app-secret
  namespace: my-namespace
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-app-secret
  data:
  - secretKey: db-password
    remoteRef:
      key: secret/data/database
      property: password
```

## Auto-Unsealing (Future Enhancement)

For production, consider implementing auto-unsealing using:
- AWS KMS
- Azure Key Vault
- Google Cloud KMS
- Transit Secrets Engine

## Backup

Always backup:
1. The SOPS-encrypted unseal keys
2. Vault's persistent data (PVC)
3. Your age keys for SOPS

## Security Best Practices

1. Never commit unencrypted unseal keys or root tokens
2. Use separate tokens with minimal permissions for applications
3. Enable audit logging in Vault
4. Regularly rotate tokens
5. Use Kubernetes auth method instead of token auth for production
