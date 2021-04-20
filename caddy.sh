#!/bin/bash

service(){
cat > caddy.service <<-EOF
[Unit]
Description=caddy(/etc/systemd/system/caddy.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/caddy/caddy -agree=true -conf=/root/Caddyfile
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
read -p "input domain:" domain
read -p "input v2ray_port:" v2ray_port
cat > Caddyfile <<-EOF
${domain}:80 {
    redir https://${domain}{uri}
}
${domain}:443 {
    tls /root/plugin.crt /root/plugin.key
    gzip
	timeouts none
    browse
    root /usr/downloads
    proxy /natsu 127.0.0.1:${v2ray_port} {
        websocket
    }
}
import sites/*
EOF
mkdir caddy
cd caddy
wget -O caddy.tar.gz https://github.com/manatsu525/v2ray/releases/download/v3.05/caddy_v1.0.4_linux_amd64.tar.gz
tar -xzvf caddy.tar.gz
service
mv caddy.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable caddy.service
systemctl start caddy
