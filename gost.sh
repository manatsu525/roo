#!/bin/bash

cd /root
cat > kcp <<-EOF
{
    "key": "tsukasakuro",
    "crypt": "salsa20",
    "mode": "fast",
    "mtu" : 1200,
    "sndwnd": 2048,
    "rcvwnd": 2048,
    "datashard": 30,
    "parityshard": 15,
    "dscp": 0,
    "nocomp": true,
    "acknodelay": false,
    "nodelay": 0,
    "interval": 20,
    "resend": 0,
    "nc": 0,
    "sockbuf": 4194304,
    "keepalive": 10,
    "snmplog": "",
    "snmpperiod": 60,
    "tcp": false
}
EOF

service(){
cat > gost.service <<-EOF
[Unit]
Description=gost(/etc/systemd/system/gost.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/gost wsserver -l value:port -p passwd --path /en
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}


echo -e "0.ws  1.wss 2.ohttp 3.otls 4.kcp 5.remove"
read -p "请选择（仅填数字）:" num

read -p "method:" value
[[ -z ${value} ]] && value="wss"

read -p "请输入端口（default:8443）:" port
[[ -z ${port} ]] && port="8443"

read -p "请输入密码:" passwd
[[ -z ${passwd} ]] && passwd="sumire"

read -p "请输入path:" path
[[ -z ${path} ]] && path="sumire"

case ${num} in
	0 ) shadow="/root/gost -L=ss+ws://AEAD_CHACHA20_POLY1305:${passwd}@:${port}?path=${path} &"
	;;
	1 ) shadow="/root/gost -L=ss+wss://AEAD_CHACHA20_POLY1305:${passwd}@:${port}?path=${path} &"
	;;
	2 ) shadow="/root/gost -L=ss+ohttp://AEAD_CHACHA20_POLY1305:${passwd}@:${port}"
	;;
	3 ) shadow="/root/gost -L=ss+otls://AEAD_CHACHA20_POLY1305:${passwd}@:${port}"
	;;
	4 ) shadow="/root/gost -L=ss+kcp://AEAD_CHACHA20_POLY1305:${passwd}@:${port}?c=/root/kcp"
	;;
	5 ) rm -rf /root/gost*	
	killall gost
	systemctl stop gost
	systemctl disable gost.service
	rm -rf /etc/systemd/system/gost.service
	exit 0
	;;
esac

cd /root
service
sed -i "/ExecStart/c ExecStart=${shadow}" gost.service
wget -O gost.gz "https://github.com/manatsu525/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz" && gzip -d gost.gz && chmod +x gost
mv gost.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable gost.service
systemctl start gost
systemctl status gost
