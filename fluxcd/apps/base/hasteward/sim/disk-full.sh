#!/usr/bin/env bash
# Fill a CNPG instance's data PVC until postgres can't write WAL -> disk-full crash-loop:
# the exact deadlock `deadlock-recover` exists for (too full to start -> can't checkpoint to
# recycle its own WAL -> stays full). Targets the current primary by default.
#   ./disk-full.sh -c training-dummy-postgres -n training-dummy
set -euo pipefail

CLUSTER=""; NS=""; POD=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c) CLUSTER="$2"; shift 2 ;;
    -n) NS="$2"; shift 2 ;;
    -p) POD="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
: "${CLUSTER:?-c <cluster> required}"
: "${NS:?-n <namespace> required}"

[ -n "$POD" ] || POD=$(kubectl get clusters.postgresql.cnpg.io "$CLUSTER" -n "$NS" -o jsonpath='{.status.currentPrimary}')
echo "filling $POD's data PVC (until ENOSPC)..."
kubectl exec -n "$NS" "$POD" -c postgres -- sh -c '
  dd if=/dev/zero of=/var/lib/postgresql/data/pgdata/SIM_DISK_FILL bs=1M 2>&1 | tail -2
  echo "--- df ---"; df -h /var/lib/postgresql/data | tail -1
' 2>&1 || true

echo "forcing WAL writes so postgres hits the full disk..."
kubectl exec -n "$NS" "$POD" -c postgres -- psql -U postgres -tAc \
  "CREATE TABLE IF NOT EXISTS sim_fill(v text); INSERT INTO sim_fill SELECT repeat('x',1000) FROM generate_series(1,200000); CHECKPOINT;" 2>&1 | tail -2 \
  || echo "(writes failing — disk full, as intended)"

echo "=== watch $POD go NotReady / crash-loop, then run deadlock-recover on its ordinal ==="
