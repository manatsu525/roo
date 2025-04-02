#!/bin/bash

read -p "domain:" domain

cd /root
wget --no-check-certificate https://github.com/manatsu525/roo/releases/download/2/caddy && chmod +x caddy

cat > Caddyfile <<-EOF
${domain}:443 {
    tls lineair069@gmail.com

    route {
        forward_proxy {
            basic_auth sumire sumire
            hide_ip
            hide_via
            probe_resistance
        }

        handle_path /file/* {
            file_server {
                root /usr/downloads
                browse
            }
        }

        handle {
            reverse_proxy www.honda.com {
                header_up Host {http.request.host}
                header_up X-Forwarded-For {http.request.remote.addr}
                header_up X-Forwarded-Proto {http.request.scheme}
            }
        }
    }
}
EOF

./caddy start
