#!/bin/bash

read -p "domain:" domain

cd /root
wget https://dl.google.com/go/go1.18.1.linux-amd64.tar.gz
tar -zxvf go1.18.1.linux-amd64.tar.gz -C /usr/local/bin/

echo "export GOROOT=/usr/local/bin/go" >> ~/.bashrc
echo "export GOPATH=$HOME/go" >> ~/.bashrc
echo "export PATH=$GOROOT/bin:$PATH" >> ~/.bashrc
echo "export PATH=$PATH:$GOPATH/bin" >> ~/.bashrc
echo "export GO111MODULE=on" >> ~/.bashrc
source ~/.bashrc

go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive

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
