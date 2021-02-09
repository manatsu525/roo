#!/bin/bash

cd /root
read -p "input domain:" domain
read -p "input v2ray_port:" v2ray_port
cat > Caddyfile <<-EOF
$domain {
    tls lineair069@gmail.com
    gzip
	timeouts none
    browse
    root /var/lib/transmission-daemon/downloads
    proxy /natsu 127.0.0.1:${v2ray_port} {
        websocket
    }
}
import sites/*
EOF
