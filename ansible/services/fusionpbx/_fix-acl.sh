#!/bin/bash
# LAN phones on subnets other than the PBX's own (e.g. 10.40.x) were classified as
# remote by local-network-acl=localnet.auto (box subnet only), so FreeSWITCH advertised
# the PUBLIC ext-rtp-ip to them and their audio went to the internet. Use the rfc1918
# ACL so every private-range phone is treated as local and gets the LAN IP.
set -e
DBN=$(grep -oP "database\.0\.name\s*=\s*\K\S+" /etc/fusionpbx/config.conf)
DBU=$(grep -oP "database\.0\.username\s*=\s*\K\S+" /etc/fusionpbx/config.conf)
DBP=$(grep -oP "database\.0\.password\s*=\s*\K\S+" /etc/fusionpbx/config.conf)
q(){ PGPASSWORD="$DBP" psql -h 127.0.0.1 -U "$DBU" "$DBN" "$@"; }
U=$(q -tAc "select sip_profile_uuid from v_sip_profiles where sip_profile_name='internal';")
q -c "update v_sip_profile_settings set sip_profile_setting_value='rfc1918' where sip_profile_setting_name='local-network-acl' and sip_profile_uuid='$U';"
echo "internal local-network-acl now:"
q -tAc "select sip_profile_setting_value from v_sip_profile_settings where sip_profile_setting_name='local-network-acl' and sip_profile_uuid='$U';"
rm -f /var/cache/fusionpbx/*
fs_cli -x 'reloadacl' >/dev/null
fs_cli -x 'reloadxml' >/dev/null
fs_cli -x 'sofia profile internal restart' >/dev/null
sleep 4
echo "profile state: $(fs_cli -x 'sofia status' | grep -i 'internal.*profile')"
