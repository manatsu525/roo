#!/bin/bash

read -p "domain:" domain

cd /root
wget --no-check-certificate https://github.com/manatsu525/roo/releases/download/1/caddy && chmod +x caddy

cat > Caddyfile <<-EOF
:443, ${domain}
tls lineair069@gmail.com
route {
  forward_proxy {
    basic_auth sumire sumire
    hide_ip
    hide_via
    probe_resistance
  }
  file_server { 
    root /usr/downloads
    browse 
  }
}
EOF

./caddy start
