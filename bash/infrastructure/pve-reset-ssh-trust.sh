#!/usr/bin/env bash
# pve-reset-ssh-trust.sh — Repair PVE inter-node SSH host-key trust on THIS node.
#
# Run on EACH node. It fixes THIS node's entry in the shared (pmxcfs) trust file
# and restarts THIS node's PVE services. After running it on every node, the
# cluster's inter-node SSH (WebUI "Shell", migration, pvesh) works again.
#
# WHY THIS SCRIPT EXISTS (PVE limitation, confirmed in the PVE source):
#   * PVE::Cluster::Setup::ssh_create_node_known_hosts() writes ONLY the RSA host
#     key into /etc/pve/nodes/<node>/ssh_known_hosts, and only at node setup.
#     `pvecm updatecerts` does NOT refresh that file.
#   * PVE::SSHInfo verifies inter-node ssh against that exact file with
#     `-o HostKeyAlias=<node> -o GlobalKnownHostsFile=none` — so that per-node
#     file is the SOLE source of truth.
#   * Modern OpenSSH (9/10) negotiates ED25519. An RSA-only (or stale) per-node
#     file therefore can never match a regenerated ED25519 host key, and there is
#     no native command that fixes it. This script writes ALL current host-key
#     types into that file, which PVE itself does not do.
#
# pmxcfs (/etc/pve) has NO hardlink support, so `ssh-keygen -R` and `sed -i` FAIL
# with "Operation not permitted". Every edit below is read -> filter -> redirect.
set -euo pipefail

# --- Resolve THIS node's PVE name (must match the /etc/pve/nodes/<Name> dir) ---
NODE=$(hostname -s)
if [[ ! -d "/etc/pve/nodes/$NODE" ]]; then
  match=$(ls /etc/pve/nodes/ 2>/dev/null | grep -ix "$NODE" | head -1 || true)
  [[ -n "$match" ]] && NODE="$match"
fi
[[ -d "/etc/pve/nodes/$NODE" ]] || {
  echo "ERROR: /etc/pve/nodes/$NODE not found — is pmxcfs mounted and the nodename correct?" >&2
  exit 1
}
KH="/etc/pve/nodes/$NODE/ssh_known_hosts"

echo "=== PVE SSH trust repair on: $NODE ==="

# --- 1. Restore the native /root/.ssh/known_hosts symlink (undo flat-file tamper) ---
#        On stock PVE this is a symlink into pmxcfs; a flat file here means it was
#        clobbered and will drift. SSHInfo doesn't use it, but manual `ssh` does.
if [[ ! -L /root/.ssh/known_hosts ]]; then
  rm -f /root/.ssh/known_hosts
  ln -s /etc/pve/priv/known_hosts /root/.ssh/known_hosts
  echo "  restored /root/.ssh/known_hosts -> /etc/pve/priv/known_hosts"
fi

# --- 2. Native cert / authorized_keys refresh (do PVE's part first) ---
echo "  pvecm updatecerts -f ..."
pvecm updatecerts -f || echo "  WARN: pvecm updatecerts returned non-zero" >&2

# --- 3. Fill PVE's gap: write ALL current host-key types into the per-node file ---
#        Format = PVE/SSHInfo's HostKeyAlias key: "<Node> <keytype> <key>".
#        Written LAST so it wins over anything pvecm/setup may have (re)written.
tmp=$(mktemp)   # mktemp lands in /tmp (real fs), never pmxcfs
for kt in ed25519 rsa ecdsa; do
  pub="/etc/ssh/ssh_host_${kt}_key.pub"
  [[ -f "$pub" ]] && echo "$NODE $(cut -d' ' -f1-2 "$pub")" >> "$tmp"
done
[[ -s "$tmp" ]] || { echo "ERROR: no /etc/ssh/ssh_host_*_key.pub found" >&2; rm -f "$tmp"; exit 1; }
cat "$tmp" > "$KH"    # pmxcfs-safe: redirect truncates in place (no rename / hardlink)
rm -f "$tmp"
echo "  wrote $KH:"; sed 's/^/      /' "$KH"

# --- 4. Restart PVE services on THIS node ---
for svc in pve-cluster pvedaemon pveproxy; do
  systemctl restart "$svc" && echo "  restarted $svc" || echo "  WARN: failed to restart $svc" >&2
done

echo "=== Done on $NODE. Run this on EVERY node, then re-test the WebUI shell. ==="
