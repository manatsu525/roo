#!/bin/bash

cd /root
cat > config.json <<-EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [{
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [{
                        "id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239", // 填写你的 UUID
                        "flow": "xtls-rprx-direct",
                        "level": 0,
                        "email": "lineair069@gmail.com"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": 80
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "alpn": [
                        "http/1.1"
                    ],
                    "certificates": [{
                            "certificateFile": "/etc/xray/plugin.crt", // 换成你的证书，绝对路径
                            "keyFile": "/etc/xray/plugin.key" // 换成你的私钥，绝对路径
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
    gzip
	timeouts none
    browse
    root /usr/downloads
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
