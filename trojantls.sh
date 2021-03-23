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

read -p "input domain:" domain
cat > /root/trojan.json <<EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "tsukasakuro"
    ],
    "ssl": {
        "cert": "plugin.crt",
        "key": "plugin.key",
        "sni": "${domain}",
        "fallback_port": 1234
    }
}
EOF

cd /root
wget https://github.com/manatsu525/v2ray-tcp-tls-web/releases/download/v1.2.1/trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip
trojan
mv trojan.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable trojan.service
systemctl start trojan
