#!/bin/sh
# Keeps a valid operator SSH certificate beside the key: signs a new one through OpenBao
# when fewer than OPTCP_CERT_MIN_LEFT seconds remain, and logs in to Zitadel only when
# the OpenBao token is gone. Run by ssh (Match exec in optcp.sshconfig) or by hand.
#   BAO_ADDR            OpenBao            (default https://secrets.optcp.com)
#   OPTCP_SSH_KEY       private key path   (default ~/.ssh/id_ed25519_sk)
#   OPTCP_CERT_MIN_LEFT seconds            (default 600)
set -eu
addr=${BAO_ADDR:-https://secrets.optcp.com}
key=${OPTCP_SSH_KEY:-$HOME/.ssh/id_ed25519_sk}
cert="${key}-cert.pub"
min_left=${OPTCP_CERT_MIN_LEFT:-600}

if [ -f "$cert" ]; then
  end=$(ssh-keygen -Lf "$cert" | sed -n 's/.*Valid: from [^ ]* to \([^ ]*\).*/\1/p')
  if [ -n "$end" ] && [ "$(date -d "$end" +%s)" -gt $(( $(date +%s) + min_left )) ]; then
    exit 0
  fi
fi
bao token lookup -address "$addr" >/dev/null 2>&1 \
  || bao login -address "$addr" -method=oidc role=operator >/dev/null
bao write -address "$addr" -field=signed_key optcp-ssh/sign/operator "public_key=@${key}.pub" > "${cert}.new"
mv "${cert}.new" "$cert"
