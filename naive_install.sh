#!/bin/bash

read -p "domain:" domain

cd /root

go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive
if [[ $? -ne 0 ]]; then
  echo "fail"
  exit 0
fi

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
rm ~/go/* -rf
