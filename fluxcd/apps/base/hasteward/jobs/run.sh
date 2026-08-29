#!/usr/bin/env bash
# Run a named HASteward operation as a one-shot Job — no scratch YAML. Pick a verb file in
# this directory, fill the blanks, apply. The ServiceAccount + ClusterRole are flux-managed
# (../rbac.yaml); the Job runs in fairy-bottle and targets a cluster in any namespace.
#
#   ./run.sh triage           -c nextcloud-postgres -n temple-of-time
#   ./run.sh deadlock-recover -c nextcloud-postgres -n temple-of-time -i 2
#   ./run.sh repair           -c osticket-mariadb    -n hyrule-castle  -i 1 -e galera
#
# Flags: -c cluster (req)  -n namespace (req)  -i instance  -e engine (default cnpg)
#        --image <ref> (default docker.io/prplanit/hasteward:latest-dev)
#        -f|--force  carry out the operation HASteward refuses on its own. Triage withholds
#                    a donor when authority is ambiguous (split-brain) because picking the
#                    surviving lineage is unrecoverable and therefore a human's call; this
#                    flag is how that decision is handed back to the tool once made.
# Follow logs after it starts:  kubectl -n fairy-bottle logs -f job/<printed-name>
set -euo pipefail

VERB="${1:-}"
[ -n "$VERB" ] || { echo "usage: run.sh <verb> -c <cluster> -n <namespace> [-i <instance>] [-e <engine>] [--image <ref>] [-f|--force]"; exit 2; }
shift

ENGINE=cnpg
INSTANCE=""
IMAGE="docker.io/prplanit/hasteward:latest-dev"
CLUSTER=""
NAMESPACE=""
FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -c) CLUSTER="$2"; shift 2 ;;
    -n) NAMESPACE="$2"; shift 2 ;;
    -i) INSTANCE="$2"; shift 2 ;;
    -e) ENGINE="$2"; shift 2 ;;
    --image) IMAGE="$2"; shift 2 ;;
    -f|--force) FORCE=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$DIR/$VERB.yaml"
if [ ! -f "$TEMPLATE" ]; then
  echo "no template for verb '$VERB'. Available:" >&2
  for f in "$DIR"/*.yaml; do echo "  $(basename "$f" .yaml)"; done
  exit 2
fi
: "${CLUSTER:?-c <cluster> required}"
: "${NAMESPACE:?-n <namespace> required}"
if grep -q '\${INSTANCE}' "$TEMPLATE" && [ -z "$INSTANCE" ]; then
  echo "verb '$VERB' needs -i <instance>" >&2
  exit 2
fi
if [ -n "$FORCE" ] && ! grep -q '\${FORCE}' "$TEMPLATE"; then
  echo "verb '$VERB' does not accept --force" >&2
  exit 2
fi

export ENGINE CLUSTER NAMESPACE INSTANCE IMAGE FORCE
# create (not apply): generateName gives each run a unique Job name, so repeated runs never
# collide and the history is auditable until ttlSecondsAfterFinished reaps it.
envsubst '${ENGINE} ${CLUSTER} ${NAMESPACE} ${INSTANCE} ${IMAGE} ${FORCE}' < "$TEMPLATE" | kubectl create -f -
