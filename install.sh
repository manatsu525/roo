#!/bin/bash

cd /root

wget https://github.com/txthinking/brook/releases/download/v20200701/brook
chmod +x brook

cat > brook.service <<-EOF
[Unit]
Description=Brook(/etc/systemd/system/brook.service)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/root/brook wsserver -l value:port -p passwd
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

read -p "请输入监听地址（default:0.0.0.0）:" value
[[ -z ${value} ]] && value="0.0.0.0"

read -p "请输入端口（default:8080）:" port
[[ -z ${port} ]] && port="8080"

read -p "请输入密码:" passwd
[[ -z ${passwd} ]] && passwd="Cjh19960525"

sed -i "s/value/${value}/g" brook.service
sed -i "s/port/${port}/g" brook.service
sed -i "s/passwd/${passwd}/g" brook.service

mv brook.service /etc/systemd/system/
systemctl enable brook.service
service brook start
service brook status
