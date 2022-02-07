#!/bin/bash

read -p "input port:" port

cd /root
cat > config.json <<-EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [{
            "port": ${port},
            "protocol": "vmess",
            "settings": {
                "clients": [{
                        "id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239", // 填写你的 UUID
                        "level": 0,
                        "alterId": 0
                    }
                ],
                "fallbacks": [
                    {
                        "dest": 80
                    }
                ]
            },
            "streamSettings": {
                "network": "quic",
                "quicSettings": {
                        "security": "none",
                        "key": "",
                        "header": {
                            "type": "utp"
                        }
                    },
                "security": "tls",
                "tlsSettings": {
                    "certificates": [{
                            "certificateFile": "/root/plugin.crt", 
                            "keyFile": "/root/plugin.key" 
                        }
                    ]
                }
            }
        }  
    ],
    "outbounds": [{
            "protocol": "freedom"
        }
    ]
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
read -p "input domain:" domain
cat > Caddyfile <<-EOF
${domain}:80 {
    redir https://${domain}{uri}:8448
}
${domain}:8448 {
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

cat >/root/vmess_qr.json <<-EOF
{
	"v": "2",
	"ps": "${domain}",
	"add": "${domain}",
	"port": "${port}",
	"id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
	"aid": "0",
	"net": "quic",
	"type": "none",
	"header": "utp",
	"tls": "tls"
}
EOF

vmess="vmess://$(cat /root/vmess_qr.json | base64 -w 0)"
echo $vmess
