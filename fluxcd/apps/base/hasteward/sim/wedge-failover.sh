#!/usr/bin/env bash
# Inject the exact "stuck failover" wedge into a CNPG cluster: the current primary's pod is
# gone while a failover is open against a replica, so the operator loops "Failing over" (it
# cannot demote the vanished old primary) and will NOT recreate the primary. This is the
# state deadlock-recover leaves behind on a disk-full primary — reproduced in seconds,
# without filling a disk, so the SETTLE fix can be iterated deterministically.
#   ./wedge-failover.sh -c training-dummy-postgres -n training-dummy
set -euo pipefail

CLUSTER=""; NS=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c) CLUSTER="$2"; shift 2 ;;
    -n) NS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
: "${CLUSTER:?-c <cluster> required}"
: "${NS:?-n <namespace> required}"

gvr="clusters.postgresql.cnpg.io"
cur=$(kubectl get "$gvr" "$CLUSTER" -n "$NS" -o jsonpath='{.status.currentPrimary}')
target=$(kubectl get "$gvr" "$CLUSTER" -n "$NS" -o jsonpath='{.status.instanceNames}' \
  | tr -d '[]"' | tr ',' '\n' | grep -v "^${cur}$" | head -1)
[ -n "$cur" ] && [ -n "$target" ] || { echo "could not resolve primary/target — is the cluster healthy?"; exit 1; }
echo "current primary=$cur   failover target=$target"

echo "1) disable reconcile (operator won't recreate the primary pod)"
kubectl annotate "$gvr" "$CLUSTER" -n "$NS" cnpg.io/reconciliationLoop=disabled --overwrite
echo "2) delete the primary pod $cur"
kubectl delete pod "$cur" -n "$NS" --grace-period=0 --wait=false 2>/dev/null || true
kubectl wait --for=delete "pod/$cur" -n "$NS" --timeout=60s 2>/dev/null || true
echo "3) open a failover: targetPrimary=$target (currentPrimary stays $cur, whose pod is now gone)"
kubectl patch "$gvr" "$CLUSTER" -n "$NS" --subresource status --type merge \
  -p "{\"status\":{\"targetPrimary\":\"$target\"}}"
echo "4) re-enable reconcile — operator now loops 'Failing over', unable to demote the vanished $cur"
kubectl annotate "$gvr" "$CLUSTER" -n "$NS" cnpg.io/reconciliationLoop-
sleep 5
echo "=== resulting state (want: phase=Failing over, currentPrimary=$cur with no pod) ==="
kubectl get "$gvr" "$CLUSTER" -n "$NS" \
  -o jsonpath='phase={.status.phase} currentPrimary={.status.currentPrimary} targetPrimary={.status.targetPrimary}{"\n"}'
kubectl get pods -n "$NS" -l cnpg.io/cluster="$CLUSTER" --no-headers 2>/dev/null | awk '{print "  "$1, $2, $3}'
