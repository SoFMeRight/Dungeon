#!/bin/sh

# To use:
# curl -LJO https://git.optcp.com/precisionplanit/ant_parade-public/-/raw/main/onboarding/install-qemu-guest-agent-pfsense.sh && chmod +x install-qemu-guest-agent-pfsense.sh && ./install-qemu-guest-agent-pfsense.sh

pkg install -y qemu-guest-agent > /dev/null

cat > /etc/rc.conf.local << EOF
qemu_guest_agent_enable="YES"
qemu_guest_agent_flags="-d -v -l /var/log/qemu-ga.log"
#virtio_console_load="YES"
EOF

cat > /usr/local/etc/rc.d/qemu-agent.sh << EOF
#!/bin/sh
sleep 3
service qemu-guest-agent start
EOF

chmod +x /usr/local/etc/rc.d/qemu-agent.sh

service qemu-guest-agent start
