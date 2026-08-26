#!/usr/bin/env bash
# Make ALL standbys genuinely fall behind the primary, so a deadlock-recover of the primary must
# GUARD (keep it fenced + surface repair --promote) rather than release it. This must create a
# REAL data-loss risk: pausing replay is NOT enough — a replay-paused standby still RECEIVES the
# WAL (walreceiver runs ahead of the startup replayer) and would apply it on promotion, so it is
# actually caught up. To make a standby unable to promote to the primary's position we stop it
# RECEIVING: SIGSTOP its walreceiver, then write a burst to the primary. The standbys'
# pg_last_wal_receive_lsn (what safeToReleaseRecoveredPrimary compares) then lags the primary.
#   ./behind-replicas.sh -c training-dummy-postgres -n training-dummy          # induce receive-lag
#   ./behind-replicas.sh -c training-dummy-postgres -n training-dummy --resume # undo (resume receiving)
set -euo pipefail

CLUSTER=""; NS=""; RESUME=0
while [ $# -gt 0 ]; do
  case "$1" in
    -c) CLUSTER="$2"; shift 2 ;;
    -n) NS="$2"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
: "${CLUSTER:?-c <cluster> required}"
: "${NS:?-n <namespace> required}"

gvr="clusters.postgresql.cnpg.io"
primary=$(kubectl get "$gvr" "$CLUSTER" -n "$NS" -o jsonpath='{.status.currentPrimary}')
standbys=$(kubectl get pods -n "$NS" -l cnpg.io/cluster="$CLUSTER" -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v "^${primary}$")
echo "primary=$primary  standbys=$(echo "$standbys" | tr '\n' ' ')"

# SIGSTOP/SIGCONT the standby's walreceiver by its pid (from pg_stat_wal_receiver). kill is a
# shell builtin so no procps needed in the postgres image.
signal_walreceiver() {
  local pod="$1" sig="$2"
  kubectl exec -n "$NS" "$pod" -c postgres -- sh -c '
    pid=$(psql -U postgres -tAqc "SELECT pid FROM pg_stat_wal_receiver;" 2>/dev/null | tr -d "[:space:]")
    if [ -n "$pid" ]; then kill -'"$sig"' "$pid" && echo "walreceiver pid=$pid '"$sig"'"; else echo "no walreceiver found"; fi' 2>&1 | tail -1
}

if [ "$RESUME" = 1 ]; then
  for p in $standbys; do
    echo "resuming receive on $p"
    signal_walreceiver "$p" CONT
  done
  exit 0
fi

for p in $standbys; do
  echo "stopping receive on $p"
  signal_walreceiver "$p" STOP
done

echo "writing a burst to $primary so the receive-stopped standbys fall behind"
kubectl exec -n "$NS" "$primary" -c postgres -- psql -U postgres -tAc "
  CREATE TABLE IF NOT EXISTS sim_lag(id serial primary key, v text);
  INSERT INTO sim_lag(v) SELECT repeat('x',512) FROM generate_series(1,50000);
  CHECKPOINT;" 2>/dev/null || true

echo "=== positions now (primary current_lsn vs standby received_lsn) ==="
plsn=$(kubectl exec -n "$NS" "$primary" -c postgres -- psql -U postgres -tAc "SELECT pg_current_wal_lsn();" 2>/dev/null | tr -d '\r')
echo "  $primary (primary) current_lsn=$plsn"
for p in $standbys; do
  rlsn=$(kubectl exec -n "$NS" "$p" -c postgres -- psql -U postgres -tAc "SELECT COALESCE(pg_last_wal_receive_lsn()::text,'null');" 2>/dev/null | tr -d '\r')
  echo "  $p (standby) received_lsn=$rlsn  <- behind, receive stopped"
done
