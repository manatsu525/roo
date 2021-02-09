#!/bin/bash

cat > config.json <<-EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [{
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [{
                        "id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239", // 填写你的 UUID
                        "flow": "xtls-rprx-direct",
                        "level": 0,
                        "email": "lineair069@gmail.com"
                    }
                ],
                "decryption": "none",
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "alpn": [
                        "http/1.1"
                    ],
                    "certificates": [{
                            "certificateFile": "/root/plugin.crt", // 换成你的证书，绝对路径
                            "keyFile": "/root/plugin.key" // 换成你的私钥，绝对路径
                        }
                    ]
                }
            }
        }  
    ],
    "outbounds": [{
            "protocol": "freedom"
        }
    ]
}
EOF
