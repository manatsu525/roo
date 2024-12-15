#!/bin/bash


cd /root
wget --no-check-certificate -O tuic https://github.com/manatsu525/roo/releases/download/2/tuic-server-1.0.0-x86_64-unknown-linux-gnu && chmod +x ./tuic

cat > tuic.json <<-EOF
{
    "server": "[::]:8443",
    
    "users": {
        "00000000-0000-0000-0000-000000000000": "sumire"
    },
    "certificate": "/root/plugin.crt",
    "private_key": "/root/plugin.key",

    "congestion_control": "bbr",
    
    "alpn": ["h3", "spdy/3.1"],
    
    "log_level": "info"
}
EOF

nohup ./tuic -c tuic.json &
