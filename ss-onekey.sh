#!/bin/bash

cd /root

read -p "input ss_port:" port
read -p "input passwd(default=sumire):" passwd
[[ -z $passwd ]] && passwd="sumire"
read -p "input path(default=/natsu):" path
[[ -z $path ]] && path="/natsu"
read -p "1.xchacha20-ietf-poly1305 2.chacha20-ietf-poly1305 3.aes-128-gcm 4.aes-192-gcm 5.aes-256-gcm": sel
case $sel in
    1) method="xchacha20-ietf-poly1305";;
    2) method="chacha20-ietf-poly1305";;
    3) method="aes-128-gcm";;
    4) method="aes-192-gcm";;
    5) method="aes-256-gcm";;
esac

download(){
    apt update -y && apt install snapd -y
    snap install core
    snap install shadowsocks-libev
    [[ ! -e v2ray-plugin ]] && wget https://github.com/manatsu525/roo/releases/download/1/v2ray-plugin
    chmod +x ./v2ray-plugin
}

ss-ws(){
cat > ss.service <<-EOF
[Unit]
Description=ss(/etc/systemd/system/ss.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/snap/bin/shadowsocks-libev.ss-server -c /root/ss.json -p ${port} --plugin /root/v2ray-plugin --plugin-opts "server;path=${path}"
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

ss(){
cat > ss.service <<-EOF
[Unit]
Description=ss(/etc/systemd/system/ss.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/snap/bin/shadowsocks-libev.ss-server -c /root/ss.json -p ${port} 
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root

read -p "1.ss 2.ss-ws 3.remove": sel2
case $sel2 in
    1) ss;;
    2) ss-ws;;
    3) systemctl stop ss
       systemctl disable ss.service
       rm /etc/systemd/system/ss.service
       snap remove shadowsocks-libev
       killall ss-server
       exit 0
    ;;   
esac

download

cat > ss.json <<-EOF
{
    "server":"0.0.0.0",
    "password":"${passwd}",
    "timeout":300,
    "method":"${method}",
    "fast_open":false,
    "mode":"tcp_and_udp"
}
EOF

mv ss.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable ss.service
systemctl start ss
