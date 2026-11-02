#!/bin/sh
# Keeps a valid operator SSH certificate beside the key: signs a new one through OpenBao
# when fewer than OPTCP_CERT_MIN_LEFT seconds remain. Logs in to Zitadel only when run by
# hand; under ssh (--no-login, the Match exec in optcp.sshconfig) it says what to run instead.
#   BAO_ADDR            OpenBao            (default https://secrets.optcp.com)
#   OPTCP_SSH_KEY       private key path   (default ~/.ssh/id_ed25519)
#   OPTCP_CERT_MIN_LEFT seconds            (default 600)
set -eu
addr=${BAO_ADDR:-https://secrets.optcp.com}
key=${OPTCP_SSH_KEY:-$HOME/.ssh/id_ed25519}
cert="${key}-cert.pub"
min_left=${OPTCP_CERT_MIN_LEFT:-600}
no_login=${1:-}

valid() {
  [ -f "$cert" ] || return 1
  end=$(ssh-keygen -Lf "$cert" | sed -n 's/.*Valid: from [^ ]* to \([^ ]*\).*/\1/p')
  [ -n "$end" ] && [ "$(date -d "$end" +%s)" -gt $(( $(date +%s) + min_left )) ]
}
valid && exit 0

# ssh evaluates its config twice per connection; the second run waits for the first.
lock="${cert}.lock"
if ! mkdir "$lock" 2>/dev/null; then
  n=0; while [ -d "$lock" ] && [ $n -lt 60 ]; do n=$((n+1)); sleep 1; done
  valid && exit 0
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

if ! bao token lookup -address "$addr" >/dev/null 2>&1; then
  if [ "$no_login" = "--no-login" ]; then
    echo "optcp-cert: OpenBao login needed: bao login -address $addr -method=oidc role=operator" >&2
    exit 0
  fi
  bao login -address "$addr" -method=oidc role=operator >/dev/null
fi
bao write -address "$addr" -field=signed_key optcp-ssh/sign/operator "public_key=@${key}.pub" > "${cert}.new"
mv "${cert}.new" "$cert"
