#!/bin/bash

service(){
cat > hysteria.service <<-EOF
[Unit]
Description=hysteria(/etc/systemd/system/hysteria.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/hysteria/hysteria -config /root/hysteria.json server
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
read -p "input alpn:" alpn
read -p "input passwd:" passwd
read -p "input v2ray_port:" v2ray_port
cat > hysteria.json <<-EOF
{
  "listen": ":${v2ray_port}",
  "cert": "/root/plugin.crt",
  "key": "/root/plugin.key",
  "alpn": "${alpn}",
  "auth": { 
    "mode": "password",
    "config": {
      "password": "${passwd}"
    }
  },
  "up_mbps": 100,
  "down_mbps": 100
}
EOF

mkdir hysteria
cd hysteria
wget -O hysteria https://github.com/manatsu525/roo/releases/download/2/hysteria-linux-amd64
chmod +x hysteria
service
mv hysteria.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable hysteria.service
systemctl start hysteria
