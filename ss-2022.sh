#!/bin/bash

cd /root

cat > config.json <<-EOF
{
"inbound": {
    "protocol": "shadowsocks",
    "listen": "127.0.0.1",
 "port": ${v2ray_port},
 "settings": {
    "email": "lineair069@gmail.com",
    "method": "2022-blake3-chacha20-poly1305",
    "password": "6xt9P+XsEdRkvVVZsPUg0v+cxt8rIztTXp1VQW2DJQ8=",
    "level": 0,
    "network": "tcp,udp"
    }
},
"outbound": {"protocol": "freedom"}
}
EOF
