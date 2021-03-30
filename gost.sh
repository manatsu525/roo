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
	0 ) echo "/root/gost -L=ss+ws://AEAD_CHACHA20_POLY1305:${passwd}@:${port}?path=${path} &" > shadow
	;;
	1 ) echo "/root/gost -L=ss+wss://AEAD_CHACHA20_POLY1305:${passwd}@:${port}?path=${path} &" > shadow
	;;
	2 ) echo "/root/gost -L=ss+ohttp://AEAD_CHACHA20_POLY1305:${passwd}@:${port}" > shadow
	;;
	3 ) echo "/root/gost -L=ss+otls://AEAD_CHACHA20_POLY1305:${passwd}@:${port}" > shadow
	;;
	4 ) echo "/root/gost -L=ss+kcp://AEAD_CHACHA20_POLY1305:${passwd}@:${port}?c=/root/kcp" > shadow
	;;
	5 ) update-rc.d -f shadow remove
		rm /etc/init.d/shadow
		rm shadow
		rm -rf /root/gost*
		killall gost
		exit 0
	;;
esac

wget -O gost.gz "https://github.com/manatsu525/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz" && gzip -d gost.gz && chmod +x gost
chmod +x shadow
cp shadow /etc/init.d/
update-rc.d shadow defaults 90
/etc/init.d/shadow >/dev/null &
