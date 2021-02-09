#!/bin/bash

cat > config.json <<-EOF
{
"inbound": {
    "protocol": "vmess",
    "listen": "127.0.0.1",
 "port": 8080,
 "settings": {"clients": [
        {"id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
	 "level": 0,
	 "alterId": 0}
    ]},
 "streamSettings": {
 "network": "ws",
 "wsSettings": {"path":"/natsu"}
    }
},

"outbound": {"protocol": "freedom"}
}
EOF
