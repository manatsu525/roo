#!/bin/bash

cd /root

read -p "input domain:" domain
read -p "input v2ray_port:" v2ray_port
export v2ray_port
export domain

cat > config.json <<-EOF
{
"inbound": {
    "protocol": "shadowsocks",
    "listen": "127.0.0.1",
 "port": ${v2ray_port},
 "settings": {
    "email": "lineair069@gmail.com",
    "method": "2022-blake3-chacha20-poly1305",
    "password": "6xt9P+XsEdRkvVVZsPUg0v+cxt8rIztTXp1VQW2DJQ8=",
    "level": 0,
    "network": "tcp,udp"
    },
 "streamSettings": {
 "network": "ws",
 "wsSettings": {"path":"/natsu"}
    }
},
"outbound": {"protocol": "freedom"}
}
EOF


cd /root
read -p "cert type: 1.auto 2.self-signed 3.none 4.without ws" type
case $type in
    1) bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddya.sh) 
    ;;
    2) bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddy.sh) 
    ;;
    3) echo "NO TLS"
    ;;
    4）bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/ss-2022.sh)
    ;;
esac

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
