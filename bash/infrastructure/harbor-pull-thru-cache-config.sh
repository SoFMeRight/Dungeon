#!/bin/bash
set -euo pipefail

# ===================================================================
# HARBOR PROXY CACHE CONFIGURATION
# ===================================================================
# Creates proxy cache projects in Harbor for pull-through caching.
# Registers upstream registry endpoints, creates proxy cache projects,
# and creates a robot account for mirrors.
#
# Usage:
#   HARBOR_ADMIN_PASSWORD=xxx ./harbor-pull-thru-cache-config.sh
#   HARBOR_ADMIN_PASSWORD=xxx DOCKERHUB_USERNAME=xxx DOCKERHUB_PASSWORD=xxx ./harbor-pull-thru-cache-config.sh
# ===================================================================

# -------------------------------------------------------------------
# Configuration — edit these as needed
# -------------------------------------------------------------------
HARBOR_URL="${HARBOR_URL:-https://cr.pcfae.com}"
HARBOR_USER="${HARBOR_USER:-admin}"
HARBOR_API="${HARBOR_URL}/api/v2.0"

# Robot account name (Harbor prepends "robot$" automatically)
ROBOT_NAME="${ROBOT_NAME:-archivist}"
ROBOT_DESCRIPTION="${ROBOT_DESCRIPTION:-Pull-through cache mirror access for CRI-O nodes}"

# Docker Hub credentials (recommended to avoid 100 pulls/6hr anonymous limit)
# ghcr.io, quay.io, lscr.io have no meaningful anonymous rate limits
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
DOCKERHUB_PASSWORD="${DOCKERHUB_PASSWORD:-}"

# Proxy cache project definitions: project_name:registry_name:registry_type:registry_url
# lscr.io is hosted on Docker Hub, so it uses docker-hub type
CACHE_PROJECTS=(
  "docker-cache:docker-hub:docker-hub:https://hub.docker.com"
  "ghcr-cache:ghcr:github-ghcr:https://ghcr.io"
  "quay-cache:quay:quay:https://quay.io"
  "lscr-cache:docker-hub-lscr:docker-hub:https://hub.docker.com"
)

# Images to pre-warm after setup (optional, requires crane)
PREWARM_IMAGES=(
  "docker.io/library/alpine:latest"
  "docker.io/library/busybox:latest"
  "docker.io/library/redis:alpine"
)

# -------------------------------------------------------------------
# Validation
# -------------------------------------------------------------------
if [ -z "${HARBOR_ADMIN_PASSWORD:-}" ]; then
  echo "ERROR: HARBOR_ADMIN_PASSWORD environment variable is required"
  exit 1
fi

AUTH_HEADER="Authorization: Basic $(printf '%s:%s' "$HARBOR_USER" "$HARBOR_ADMIN_PASSWORD" | base64)"

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
api() {
  local method="$1" path="$2"
  shift 2
  curl -sk -X "$method" \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    "${HARBOR_API}${path}" \
    "$@"
}

get_registry_id() {
  api GET "/registries" -s | jq -r --arg name "$1" '.[] | select(.name == $name) | .id'
}

check_response() {
  local response="$1" action="$2"
  case "$response" in
    201) echo "created" ;;
    409) echo "already exists" ;;
    *)   echo "FAILED (HTTP $response)"; exit 1 ;;
  esac
}

echo "==================================="
echo "Harbor Proxy Cache Configuration"
echo "Target: ${HARBOR_URL}"
echo "==================================="
echo ""

# -------------------------------------------------------------------
# Step 1: Register upstream registry endpoints
# -------------------------------------------------------------------
echo "--- Step 1: Registering upstream registry endpoints ---"
echo ""

if [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_PASSWORD" ]; then
  echo "  Using authenticated Docker Hub access"
else
  echo "  WARNING: No DOCKERHUB_USERNAME/DOCKERHUB_PASSWORD — anonymous rate limit applies (100 pulls/6hr)"
fi

declare -A SEEN_REGISTRIES=()

for entry in "${CACHE_PROJECTS[@]}"; do
  IFS=: read -r _project reg_name reg_type reg_url <<< "$entry"

  # Skip duplicate registry names
  [ -n "${SEEN_REGISTRIES[$reg_name]:-}" ] && continue
  SEEN_REGISTRIES[$reg_name]=1

  payload="{\"name\":\"$reg_name\",\"type\":\"$reg_type\",\"url\":\"$reg_url\",\"insecure\":false}"

  # Add Docker Hub credentials for docker-hub type registries
  if [ "$reg_type" = "docker-hub" ] && [ -n "$DOCKERHUB_USERNAME" ] && [ -n "$DOCKERHUB_PASSWORD" ]; then
    payload=$(echo "$payload" | jq --arg u "$DOCKERHUB_USERNAME" --arg p "$DOCKERHUB_PASSWORD" \
      '. + {credential: {type: "basic", access_key: $u, access_secret: $p}}')
  fi

  echo -n "  $reg_name ($reg_type → $reg_url) ... "
  response=$(api POST "/registries" -d "$payload" -w "%{http_code}" -o /dev/null 2>/dev/null)
  check_response "$response" "register"
done
echo ""

# -------------------------------------------------------------------
# Step 2: Create proxy cache projects
# -------------------------------------------------------------------
echo "--- Step 2: Creating proxy cache projects ---"
echo ""

for entry in "${CACHE_PROJECTS[@]}"; do
  IFS=: read -r project_name reg_name _type _url <<< "$entry"
  registry_id=$(get_registry_id "$reg_name")

  if [ -z "$registry_id" ]; then
    echo "  ERROR: Registry endpoint '$reg_name' not found"
    exit 1
  fi

  echo -n "  $project_name (registry: $reg_name, id: $registry_id) ... "
  response=$(api POST "/projects" -d "{
    \"project_name\": \"$project_name\",
    \"registry_id\": $registry_id,
    \"public\": false,
    \"metadata\": {\"public\": \"false\"},
    \"storage_limit\": -1
  }" -w "%{http_code}" -o /dev/null 2>/dev/null)
  check_response "$response" "create"
done
echo ""

# -------------------------------------------------------------------
# Step 3: Create robot account
# -------------------------------------------------------------------
echo "--- Step 3: Creating robot account ---"
echo ""

ROBOT_PERMISSIONS='['
first=true
for entry in "${CACHE_PROJECTS[@]}"; do
  IFS=: read -r project_name _rest <<< "$entry"
  [ "$first" = true ] && first=false || ROBOT_PERMISSIONS+=","
  ROBOT_PERMISSIONS+="{
    \"kind\": \"project\",
    \"namespace\": \"$project_name\",
    \"access\": [
      {\"resource\": \"repository\", \"action\": \"pull\"},
      {\"resource\": \"artifact\", \"action\": \"read\"}
    ]
  }"
done
ROBOT_PERMISSIONS+=']'

echo -n "  robot\$$ROBOT_NAME ... "
robot_response=$(api POST "/robots" -d "{
  \"name\": \"$ROBOT_NAME\",
  \"duration\": -1,
  \"description\": \"$ROBOT_DESCRIPTION\",
  \"disable\": false,
  \"level\": \"system\",
  \"permissions\": $ROBOT_PERMISSIONS
}" -s 2>/dev/null)

robot_name=$(echo "$robot_response" | jq -r '.name // empty')
robot_secret=$(echo "$robot_response" | jq -r '.secret // empty')

if [ -n "$robot_name" ] && [ -n "$robot_secret" ]; then
  echo "created"
  echo ""
  echo "  ========================================="
  echo "  Username: $robot_name"
  echo "  Password: $robot_secret"
  echo "  ========================================="
  echo ""
  echo "  Store in Vault at: registries/cr.optcp.com"
  echo "    username = $robot_name"
  echo "    password = $robot_secret"
else
  echo "already exists or failed"
  echo "  Response: $robot_response"
fi
echo ""

# -------------------------------------------------------------------
# Step 4: Pre-warm cache (optional, requires crane)
# -------------------------------------------------------------------
if command -v crane &>/dev/null && [ ${#PREWARM_IMAGES[@]} -gt 0 ]; then
  echo "--- Step 5: Pre-warming cache ---"
  echo ""
  for image in "${PREWARM_IMAGES[@]}"; do
    echo -n "  Warming: $image ... "
    if crane pull "$image" /dev/null 2>/dev/null; then
      echo "ok"
    else
      echo "failed (non-fatal)"
    fi
  done
  echo ""
else
  echo "--- Step 5: Pre-warm skipped (crane not found or no images configured) ---"
  echo ""
fi

echo "==================================="
echo "Harbor Proxy Cache Configuration Complete"
echo "==================================="
