#!/bin/bash
# BulkVS reads the outbound caller-ID from the From header. With caller_id_in_from unset,
# FreeSWITCH doesn't put the extension's number there -> BulkVS shows "FreeSwitch"/no ANI.
set -e
DBN=$(grep -oP "database\.0\.name\s*=\s*\K\S+" /etc/fusionpbx/config.conf)
DBU=$(grep -oP "database\.0\.username\s*=\s*\K\S+" /etc/fusionpbx/config.conf)
DBP=$(grep -oP "database\.0\.password\s*=\s*\K\S+" /etc/fusionpbx/config.conf)
q(){ PGPASSWORD="$DBP" psql -h 127.0.0.1 -U "$DBU" "$DBN" "$@"; }
q -c "update v_gateways set caller_id_in_from='true' where gateway='sip.bulkvs.com';"
echo "after:"; q -x -c "select gateway, caller_id_in_from from v_gateways where gateway='sip.bulkvs.com';"
rm -f /var/cache/fusionpbx/*
fs_cli -x 'reloadxml' >/dev/null
fs_cli -x 'sofia profile external rescan' >/dev/null
echo "gateway state: $(fs_cli -x 'sofia status' | grep -i bulkvs)"
