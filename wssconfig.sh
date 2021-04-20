#!/bin/bash
cd /root
apt update -y
apt install socat -y
wget -qO- https://get.acme.sh|bash
read -p "input domain:" dom
/root/.acme.sh/acme.sh --issue -d ${dom} --standalone -k ec-256
/root/.acme.sh/acme.sh --install-cert -d ${dom} --fullchain-file /root/plugin.crt --key-file /root/plugin.key --ecc
cat > config.json <<EOF
{
"server":"0.0.0.0",
"server_port":8443,
"password":"sumire",
"timeout":300,
"method":"xchacha20-ietf-poly1305",
"fast_open":false,
"nameserver":"8.8.8.8",
"mode":"tcp_and_udp",
"plugin":"v2ray-plugin",
"plugin_opts":"server;tls;host=${dom};cert=/etc/shadowsocks-libev/plugin.crt;key=/etc/shadowsocks-libev/plugin.key;path=/natsu;mux=0"
}
EOF
