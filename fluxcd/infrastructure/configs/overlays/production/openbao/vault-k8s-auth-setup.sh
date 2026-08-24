#!/bin/bash
# Script to configure Vault's Kubernetes authentication
# This needs to be run after Vault is unsealed

VAULT_NAMESPACE="zeldas-lullaby"
VAULT_POD=$(kubectl get pod -n ${VAULT_NAMESPACE} -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].metadata.name}')
VAULT_SA_NAME="external-secrets-vault"

# Get the Vault root token
VAULT_ROOT_TOKEN=$(kubectl get secret vault-unseal-keys -n ${VAULT_NAMESPACE} -o jsonpath='{.data.vault-root}' | base64 -d)

# Get the JWT token and CA cert from the ServiceAccount token secret
SA_JWT_TOKEN=$(kubectl get secret external-secrets-vault-token -n ${VAULT_NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
K8S_CA_CERT=$(kubectl get secret external-secrets-vault-token -n ${VAULT_NAMESPACE} -o jsonpath='{.data.ca\.crt}' | base64 -d)

# Enable Kubernetes auth in Vault (skip if already enabled)
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault auth enable kubernetes" 2>/dev/null || echo "Kubernetes auth already enabled"

# Configure Kubernetes auth
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/config \
    token_reviewer_jwt='${SA_JWT_TOKEN}' \
    kubernetes_host='${K8S_HOST}' \
    kubernetes_ca_cert='${K8S_CA_CERT}' \
    disable_issuer_verification=true"

# Create a policy for external-secrets
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write external-secrets - <<EOF
path \"operationtimecapsule/data/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"operationtimecapsule/metadata/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"precisionplanit/data/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"precisionplanit/metadata/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"zeldas-letter/data/*\" {
  capabilities = [\"read\", \"list\"]
}
path \"zeldas-letter/metadata/*\" {
  capabilities = [\"read\", \"list\"]
}
EOF"

# Create role for external-secrets
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=${VAULT_SA_NAME} \
    bound_service_account_namespaces=${VAULT_NAMESPACE} \
    policies=external-secrets \
    ttl=24h"

# Create a policy for zitadel-provisioner with write access
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write zitadel-provisioner - <<EOF
path \"precisionplanit/data/apps/zitadel-login-v2\" {
  capabilities = [\"create\", \"update\", \"read\"]
}
path \"precisionplanit/metadata/apps/zitadel-login-v2\" {
  capabilities = [\"read\", \"list\"]
}
EOF"

# Create role for zitadel provisioner (write access to sync secrets to Vault)
kubectl exec -n ${VAULT_NAMESPACE} ${VAULT_POD} -- sh -c "VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/role/zitadel-vault-sync \
    bound_service_account_names=zitadel \
    bound_service_account_namespaces=${VAULT_NAMESPACE} \
    policies=zitadel-provisioner \
    ttl=1h"

echo "Vault Kubernetes authentication configured successfully!"
