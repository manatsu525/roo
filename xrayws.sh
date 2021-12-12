#!/bin/bash

cd /root

read -p "input v2ray_port:" v2ray_port
read -p "input v2ray_domain:" domain

cat > config.json <<-EOF
{
"inbound": {
    "protocol": "vmess",
    "listen": "0.0.0.0",
 "port": ${v2ray_port},
 "settings": {"clients": [
        {"id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
	 "level": 0,
	 "alterId": 0}
    ]},
 "streamSettings": {
 "network": "ws",
 "wsSettings": {"path":"/natsu"}
    }
},
"outbound": {"protocol": "freedom"}
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

bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddya.sh)

cat >/root/vmess_qr.json <<-EOF
{
	"v": "2",
	"ps": "${domain}",
	"add": "${domain}",
	"port": "443",
	"id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
	"aid": "0",
	"net": "ws",
	"type": "none",
	"host": "${domain}",
	"path": "/natsu",
	"tls": "tls"
}
EOF

vmess="vmess://$(cat /root/vmess_qr.json | base64 -w 0)"
echo $vmess
