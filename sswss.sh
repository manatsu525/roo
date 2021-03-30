#!/bin/bash

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
"plugin_opts":"server;tls;host=${dom};cert=/etc/shadowsocks-libev/plugin.crt;key=/etc/shadowsocks-libev/plugin.key;path=/sumire;mux=0"
}
EOF
