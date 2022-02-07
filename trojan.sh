#!/bin/bash

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
read -p "input password(default: sumire):" passwd
[[ -z ${passwd} ]] && passwd="sumire"
export v2ray_port
export domain

read -p "cert type: 1.auto 2.self-signed" type
case $type in
    1) bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddya.sh) 
    ;;
    2) bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/caddy.sh) 
    ;;
esac

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
    "${passwd}"
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
  },
  "shadowsocks": {
    "enabled": false,
    "method": "AES-128-GCM",
    "password": "${passwd}"
  }
}
EOF

trojan
mv trojan.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable trojan.service
systemctl start trojan

sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
sysctl -p 
