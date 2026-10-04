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
#        --image <ref> (default docker.io/prplanit/hasteward:latest-dev; a tag is resolved
#                    to a digest at submit time, and the digest is what the Job runs)
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

# --- pin the image to a digest ------------------------------------------------------
# The Job is submitted against a DIGEST, not the moving latest-dev tag, so what ran is
# knowable after the fact and two runs of "the same" tag can never be different code.
#
# Resolution happens HERE, on the operator's machine, rather than being left to the
# kubelet: a registry that is unreachable or rate-limited then fails visibly at submit
# time, with the cached image still usable, instead of leaving the Job in ErrImagePull.
# That matters because the moment this tool is needed is the moment the cluster — and
# anything pulling through it — is least healthy.
#
# Prints sha256:... on stdout. Returns 1 when the registry could not be reached, and 2
# when it answered that the tag does not exist — a typo must not quietly fall through to
# whatever unrelated image the node happens to have cached.
resolve_digest() {
  local ref="$1" name tag first reg repo host accept hdr realm service token code
  case "$ref" in *@sha256:*) echo "${ref##*@}"; return 0 ;; esac

  # Split off the tag, but only if the colon is in the LAST path segment — a registry
  # host may carry a port (host:5000/repo).
  case "${ref##*/}" in
    *:*) tag="${ref##*:}"; name="${ref%:*}" ;;
    *)   tag="latest";     name="$ref" ;;
  esac

  # A first segment containing a dot, a colon, or equal to localhost is a registry host;
  # otherwise the ref is an implicit Docker Hub name.
  first="${name%%/*}"
  case "$first" in
    *.*|*:*|localhost) reg="$first"; repo="${name#*/}" ;;
    *)                 reg="docker.io"; repo="$name" ;;
  esac
  if [ "$reg" = "docker.io" ]; then
    host="registry-1.docker.io"
    case "$repo" in */*) ;; *) repo="library/$repo" ;; esac
  else
    host="$reg"
  fi

  accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

  # HEAD the manifest: Docker-Content-Digest is the answer, and a HEAD does not transfer
  # the image. A 401 carries the token endpoint to use, so anonymous pulls work without
  # any credential handling here.
  hdr=$(curl -sS -I --max-time 10 -H "Accept: $accept" \
          "https://$host/v2/$repo/manifests/$tag" 2>/dev/null) || return 1
  code=$(printf '%s' "$hdr" | sed -n '1s/.* \([0-9][0-9][0-9]\).*/\1/p')
  if [ "$code" = "401" ]; then
    realm=$(printf '%s' "$hdr"   | sed -n 's/.*[Bb]earer realm="\([^"]*\)".*/\1/p')
    service=$(printf '%s' "$hdr" | sed -n 's/.*service="\([^"]*\)".*/\1/p')
    [ -n "$realm" ] || return 1
    token=$(curl -sS --max-time 10 \
              "$realm?service=$service&scope=repository:$repo:pull" 2>/dev/null \
            | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
    [ -n "$token" ] || return 1
    hdr=$(curl -sS -I --max-time 10 -H "Accept: $accept" -H "Authorization: Bearer $token" \
            "https://$host/v2/$repo/manifests/$tag" 2>/dev/null) || return 1
    code=$(printf '%s' "$hdr" | sed -n '1s/.* \([0-9][0-9][0-9]\).*/\1/p')
  fi
  [ "$code" != "404" ] || return 2
  printf '%s' "$hdr" | sed -n 's/^[Dd]ocker-[Cc]ontent-[Dd]igest: *\(sha256:[0-9a-f]*\).*/\1/p' | head -1 | grep . || return 1
}

# IfNotPresent in BOTH branches, for opposite reasons: against a digest there is nothing
# newer a re-pull could find, and against a bare tag the local layer is the only thing
# left to run.
PULL_POLICY=IfNotPresent
IMAGE_REQUESTED="$IMAGE"
RC=0
DIGEST="$(resolve_digest "$IMAGE")" || RC=$?
if [ "$RC" = 2 ]; then
  echo "no such image in the registry: $IMAGE_REQUESTED" >&2
  echo "  The registry answered — the tag does not exist. Check --image for a typo." >&2
  exit 2
fi
if [ -n "$DIGEST" ]; then
  case "$IMAGE" in
    *@sha256:*) ;;
    *) IMAGE="${IMAGE%:*}@$DIGEST" ;;
  esac
  # What the last run of this tool actually executed, for an at-a-glance "is this new?".
  # Jobs linger for ttlSecondsAfterFinished, so this needs no state file of its own.
  PREV="$(kubectl -n fairy-bottle get jobs -l app.kubernetes.io/name=hasteward \
            --sort-by=.metadata.creationTimestamp \
            -o jsonpath='{.items[-1:].spec.template.spec.containers[0].image}' 2>/dev/null || true)"
  PREV_DIGEST=""
  case "$PREV" in *@sha256:*) PREV_DIGEST="${PREV##*@}" ;; esac
  if [ -z "$PREV" ]; then
    echo "image: $IMAGE_REQUESTED -> $DIGEST (no previous run on record)"
  elif [ -z "$PREV_DIGEST" ]; then
    # Two digests can be compared; a tag cannot be compared with anything.
    echo "image: $IMAGE_REQUESTED -> $DIGEST (previous run was unpinned as $PREV, so what it executed is not recorded)"
  elif [ "$PREV_DIGEST" = "$DIGEST" ]; then
    echo "image: $IMAGE_REQUESTED -> $DIGEST (unchanged since the last run)"
  else
    # "changed", not "newer": digests carry no ordering, and a tag can move backwards.
    echo "image: $IMAGE_REQUESTED -> $DIGEST (CHANGED since the last run, which executed $PREV_DIGEST)"
  fi
else
  echo "WARNING: cannot reach the registry to resolve $IMAGE_REQUESTED." >&2
  echo "         Submitting the tag unpinned with imagePullPolicy=IfNotPresent, so this runs" >&2
  echo "         whatever layer the scheduling node already has — which may be OLD CODE, and" >&2
  echo "         which fails to start at all if that node has never pulled it." >&2
  echo "         Verify before trusting a result: kubectl -n fairy-bottle get job/<name> -o jsonpath='{.spec.template.spec.containers[0].image}'" >&2
fi

export ENGINE CLUSTER NAMESPACE INSTANCE IMAGE FORCE PULL_POLICY
# create (not apply): generateName gives each run a unique Job name, so repeated runs never
# collide and the history is auditable until ttlSecondsAfterFinished reaps it.
envsubst '${ENGINE} ${CLUSTER} ${NAMESPACE} ${INSTANCE} ${IMAGE} ${FORCE} ${PULL_POLICY}' < "$TEMPLATE" | kubectl create -f -
