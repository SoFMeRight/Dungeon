#!/bin/sh
# Keeps a valid operator SSH certificate beside the key and a live Boundary token in the
# keyring: signs a new certificate through OpenBao when fewer than OPTCP_CERT_MIN_LEFT seconds
# remain, and logs in to Zitadel (OpenBao or Boundary) when that login is gone. Run by ssh
# (the Match exec in optcp.sshconfig) or by hand; --no-login prints the login commands instead
# of running them.
#   BAO_ADDR            OpenBao            (default https://secrets.optcp.com)
#   BOUNDARY_ADDR       Boundary           (default https://access.optcp.com)
#   OPTCP_SSH_KEY       private key path   (default ~/.ssh/id_ed25519)
#   OPTCP_CERT_MIN_LEFT seconds            (default 600)
set -eu
addr=${BAO_ADDR:-https://secrets.optcp.com}
baddr=${BOUNDARY_ADDR:-https://access.optcp.com}
key=${OPTCP_SSH_KEY:-$HOME/.ssh/id_ed25519}
cert="${key}-cert.pub"
min_left=${OPTCP_CERT_MIN_LEFT:-600}
no_login=${1:-}

valid() {
  [ -f "$cert" ] || return 1
  end=$(ssh-keygen -Lf "$cert" | sed -n 's/.*Valid: from [^ ]* to \([^ ]*\).*/\1/p')
  [ -n "$end" ] && [ "$(date -d "$end" +%s)" -gt $(( $(date +%s) + min_left )) ]
}
# The stored token is at_<id>_<secret>; reading itself succeeds only while the controller still
# holds it, so a stale, expired or purged token fails here instead of at boundary connect.
boundary_valid() {
  t=$(boundary config get-token 2>/dev/null) && [ -n "$t" ] || return 1
  boundary auth-tokens read -addr "$baddr" -id "$(echo "$t" | cut -d_ -f1-2)" >/dev/null 2>&1
}
ready() { valid && boundary_valid; }
ready && exit 0

# ssh evaluates its config twice per connection; the second run waits for the first, which
# may be waiting on a browser login.
lock="${cert}.lock"
if ! mkdir "$lock" 2>/dev/null; then
  n=0; while [ -d "$lock" ] && [ $n -lt 300 ]; do n=$((n+1)); sleep 1; done
  ready && exit 0
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

if ! boundary_valid; then
  if [ "$no_login" = "--no-login" ]; then
    echo "optcp-cert: Boundary login needed: boundary authenticate oidc -addr $baddr" >&2
  else
    boundary authenticate oidc -addr "$baddr" >/dev/null
  fi
fi
valid && exit 0
if ! bao token lookup -address "$addr" >/dev/null 2>&1; then
  if [ "$no_login" = "--no-login" ]; then
    echo "optcp-cert: OpenBao login needed: bao login -address $addr -method=oidc role=operator" >&2
    exit 0
  fi
  bao login -address "$addr" -method=oidc role=operator >/dev/null
fi
bao write -address "$addr" -field=signed_key optcp-ssh/sign/operator "public_key=@${key}.pub" > "${cert}.new"
mv "${cert}.new" "$cert"
