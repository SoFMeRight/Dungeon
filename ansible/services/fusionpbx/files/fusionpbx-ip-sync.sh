#!/usr/bin/env bash
# Pins FreeSWITCH's external_sip_ip/external_rtp_ip to the current public IP,
# converging v_vars + vars.xml and restarting the external profile only on an actual
# change. Same logic the fusionpbx playbook applies, on a timer so a WAN rotation
# self-heals between runs. Set DRY_RUN=1 to log intended changes without applying.
set -euo pipefail

TRACE_URL="${FUSIONPBX_IP_DETECT_URL:-https://1.1.1.1/cdn-cgi/trace}"
CONF=/etc/fusionpbx/config.conf
VARS_XML=/etc/freeswitch/vars.xml

ip="$(curl -fsS --max-time 15 "$TRACE_URL" 2>/dev/null | sed -n 's/^ip=//p' | tr -d '[:space:]')" || true
# Never blank the advertised IP on a transient detection failure.
[[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || exit 0

getconf() { sed -n "s/^database\.0\.$1[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p" "$CONF" | head -1; }
dbhost="$(getconf host)"; dbuser="$(getconf username)"; dbname="$(getconf name)"
export PGPASSWORD="$(getconf password)"
psql_do() { psql -h "${dbhost:-127.0.0.1}" -U "$dbuser" -d "$dbname" "$@"; }

cur="$(psql_do -tAc "SELECT var_value FROM v_vars WHERE var_name='external_rtp_ip' LIMIT 1;" | tr -d '[:space:]')"
[[ "$cur" == "$ip" ]] && exit 0

if [[ -n "${DRY_RUN:-}" ]]; then
  echo "fusionpbx-ip-sync: [dry-run] would converge ${cur:-<none>} -> $ip and restart the external profile"
  exit 0
fi

echo "fusionpbx-ip-sync: ${cur:-<none>} -> $ip"
psql_do -c "UPDATE v_vars SET var_value='$ip' WHERE var_name IN ('external_rtp_ip','external_sip_ip');"
for v in external_rtp_ip external_sip_ip; do
  sed -i -E "s|^([[:space:]]*)<X-PRE-PROCESS cmd=\"set\" data=\"${v}=[^\"]*\"[[:space:]]*/>|\1<X-PRE-PROCESS cmd=\"set\" data=\"${v}=${ip}\" />|" "$VARS_XML"
done
# Flush the cache first: FusionPBX bakes the resolved IP into it, so reloadxml alone re-serves the stale one.
rm -f /var/cache/fusionpbx/* || true
fs_cli -x 'reloadacl' >/dev/null 2>&1 || true
fs_cli -x 'reloadxml' >/dev/null 2>&1 || true
fs_cli -x 'sofia profile external restart' >/dev/null 2>&1 || true
