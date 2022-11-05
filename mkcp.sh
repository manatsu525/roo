#!/bin/bash

cd /root

read -p "input v2ray_port:" v2ray_port

cat > config.json <<-EOF
{
    "inbound": {
        "protocol": "vmess",
        "listen": "0.0.0.0",
        "port": ${v2ray_port},
        "settings": {
            "clients": [{
                    "id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239"
                }
            ]
        },
        "streamSettings": {
            "network": "kcp",
            "kcpSettings": {
                "mtu": 1200,
                "tti": 30,
                "uplinkCapacity": 100,
                "downlinkCapacity": 100,
                "congestion": true,
                "readBufferSize": 2,
                "writeBufferSize": 2,
                "header": {
                    "type": "srtp"
                },
                "seed": "tsukasakuro"
            }
        }
    },

    "outbound": {
        "protocol": "freedom"
    }
}
EOF

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
