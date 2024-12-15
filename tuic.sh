#!/bin/bash


cd /root
wget --no-check-certificate -O tuic https://github.com/manatsu525/roo/releases/download/2/tuic-server-1.0.0-aarch64-unknown-linux-gnu && chmod +x ./tuic

cat > tuic.json <<-EOF
{
    "port": 8443,
    "token": ["sumire"],
    "users": {
        "00000000-0000-0000-0000-000000000000": "sumire"
    },
    "certificate": "/root/plugin.crt",
    "private_key": "/root/plugin.key",

    "ip": "::",
    "congestion_controller": "bbr",
    "max_idle_time": 15000,
    "authentication_timeout": 1000,
    "alpn": ["h3", "spdy/3.1"],
    "max_udp_relay_packet_size": 1500,
    "log_level": "info"
}
EOF

nohup ./tuic -c tuic.json &
