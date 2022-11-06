#!/bin/bash

cd /root

read -p "input port:" port
read -p "input tlsweb:" tls
read -p "input v2ray_port:" v2ray_port
export v2ray_port


shadowtls(){
cat > shadowtls.service <<-EOF
[Unit]
Description=shadowtls(/etc/systemd/system/shadowtls.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/shadowtls server --listen 0.0.0.0:${port} --server 127.0.0.1:${v2ray_port} --tls ${tls}:443 --password sumire
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
wget -O shadowtls https://github.com/manatsu525/roo/releases/download/1/shadow-tls-x86_64-unknown-linux-musl && chmod +x shadowtls
shadowtls
mv shadowtls.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable shadowtls.service
systemctl start shadowtls
