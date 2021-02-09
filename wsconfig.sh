cat > config.json <<EOF
{
    "server":"0.0.0.0",
    "server_port":8080,
    "password":"sumire",
    "timeout":300,
    "method":"xchacha20-ietf-poly1305",
    "fast_open":true,
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp",
    "plugin":"v2ray-plugin",
    "plugin_opts":"server;path=/natsu;mux=0"
} 
EOF
