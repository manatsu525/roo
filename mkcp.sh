#!/bin/bash

cat > config.json <<-EOF
{
    "inbound": {
        "protocol": "vless",
        "listen": "0.0.0.0",
        "port": 14100,
        "settings": {
            "clients": [{
                    "id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
                    "level": 0,
                    "email": "lineair069@gmail.com"
                }
            ], 
                    "decryption": "none"
        },
        "streamSettings": {
            "network": "kcp",
            "kcpSettings": {
                "mtu": 1200,
                "tti": 30,
                "uplinkCapacity": 100,
                "downlinkCapacity": 100,
                "congestion": false,
                "readBufferSize": 2,
                "writeBufferSize": 2,
                "header": {
                    "type": "utp"
                },
                "seed": "tsukasakuro"
            }
        }
    },

    "outbound": {
        "protocol": "freedom"
    }
}
EOF
