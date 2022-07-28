#!/bin/bash

cd /root

cat > config.json <<-EOF
{
"inbound": {
    "protocol": "shadowsocks",
 "port": ${v2ray_port},
 "settings": {
    "method": "2022-blake3-chacha20-poly1305",
    "password": "6xt9P+XsEdRkvVVZsPUg0v+cxt8rIztTXp1VQW2DJQ8=",
    "network": "tcp,udp"
    }
},
"outbound": {"protocol": "freedom"}
}
EOF
