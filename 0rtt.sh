#!/bin/bash

cd /root

read -p "input domain:" domain

read -p "input v2ray_port:" v2ray_port

cat > config.json <<-EOF
{
    "inbound": {
        "protocol": "vless",
        "listen": "127.0.0.1",
        "port": ${v2ray_port},
        "settings": {
            "clients": [{
                    "id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
                    "level": 0,
                    "email": "lineair069@gmail.com"
                }
            ],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": {
                "path": "/natsu"
            }
        }
    },
    "outbound": {
        "protocol": "freedom"
    }
}
EOF

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

cat > Caddyfile <<-EOF
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

xray(){
cat > xray.service <<-EOF
[Unit]
Description=xray(/etc/systemd/system/xray.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/xray run -config /root/config.json
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
wget -O xray.zip https://github.com/manatsu525/roo/releases/download/1/Xray-linux-64.zip
unzip xray.zip
xray
mv xray.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable xray.service
systemctl start xray
