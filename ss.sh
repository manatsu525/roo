#!/bin/bash

cd /root

cat > config.json <<EOF
{
    "server":"0.0.0.0",
    "server_port":8880,
    "password":"sumire",
    "timeout":300,
    "method":"aes-256-gcm",
    "fast_open":true,
    "nameserver":"8.8.8.8",
    "mode":"tcp_and_udp"
} 
EOF
