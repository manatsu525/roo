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

trojan(){
cat > trojan.service <<-EOF
[Unit]
Description=trojan(/etc/systemd/system/trojan.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/trojan-go -config /root/trojan.json
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
$domain:443 {
    tls self_signed
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


cd /root
wget https://github.com/manatsu525/v2ray-tcp-tls-web/releases/download/v1.2.1/trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip
cat > trojan.json <<-EOF
{
  "run_type": "server",
  "local_addr": "127.0.0.1",
  "local_port": ${v2ray_port},
  "remote_addr": "1.1.1.1",
  "remote_port": 80,
  "log_level": 3,
  "password": [
    "tsukasakuro"
  ],
  "transport_plugin": {
    "enabled": true,
    "type": "plaintext"
  },
  "router": {
    "enabled": false
  },
  "websocket": {
    "enabled": true,
    "path": "/natsu",
    "hostname": "${domain}"
  }
}
EOF

trojan
mv trojan.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable trojan.service
systemctl start trojan

