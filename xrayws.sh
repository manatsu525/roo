#!/bin/bash

cd /root

read -p "input v2ray_port:" v2ray_port
read -p "input v2ray_domain:" domain
export v2ray_port
export domain

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

v2ray(){
cat > v2ray.service <<-EOF
[Unit]
Description=v2ray(/etc/systemd/system/v2ray.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/v2ray run -config /root/config.json
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
wget -O v2ray.zip https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip
unzip v2ray.zip
v2ray
mv v2ray.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable v2ray.service
systemctl start v2ray

read -p "cert type: 1.auto 2.self-signed 3.none" type
case $type in
    1) bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddya.sh) 
    ;;
    2) bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddy.sh) 
    ;;
    3) echo "NO TLS"
    ;;
esac

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
