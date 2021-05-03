#!/bin/bash

cd /root

read -p "input domain:" domain

read -p "input v2ray_port:" v2ray_port

cat > config.json <<-EOF
{
"inbound": {
    "protocol": "vmess",
    "listen": "127.0.0.1",
 "port": ${v2ray_port},
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


cd /root
apt install nginx -y
cat > /etc/nginx/conf.d/default.conf <<-EOF
server {
    ### 1:
    server_name ${domain};
    listen 80;
    rewrite ^(.*) https://\$server_name\$1 permanent;
    if (\$request_method  !~ ^(POST|GET)$) { return  501; }
    autoindex off;
    server_tokens off;
}
server {
    ### 2:
    ssl_certificate /root/plugin.crt;
    ### 3:
    ssl_certificate_key /root/plugin.key;
    ### 4:
    location /natsu
    {
        proxy_pass              http://127.0.0.1:${v2ray_port};
        proxy_redirect          off;
        proxy_http_version      1.1;
        proxy_set_header        Upgrade \$http_upgrade;
        proxy_set_header        Connection "upgrade";
        proxy_set_header        Host \$host;
        sendfile                on;
        tcp_nopush              on;
        tcp_nodelay             on;
        keepalive_requests      25600;
        keepalive_timeout       300 300;
        proxy_buffering         off;
        proxy_buffer_size       8k;
    }
    listen 443 ssl http2;
    server_name \$server_name;
    charset utf-8;
    ssl_protocols TLSv1.2;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!3DES:!MD5:!PSK;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:60m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 10s;
    # Security settings
    if (\$request_method  !~ ^(POST|GET)$) { return 501; }
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options nosniff;
    add_header Strict-Transport-Security max-age=31536000 always;
    autoindex off;
    server_tokens off;
	
	location / {
        return 302 https://www.morinagamilk.co.jp/;
     }
        
	location /file 
        {
	alias /usr/downloads;
        autoindex on;            
        autoindex_exact_size off;
        }
}
EOF

systemctl daemon-reload
systemctl restart nginx
systemctl enable nginx.service

xray(){
cat > xray.service <<-EOF
[Unit]
Description=xray(/etc/systemd/system/xray.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/xray run -config /root/config.json
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
wget -O xray.zip https://github.com/manatsu525/roo/releases/download/1/Xray-linux-64.zip
unzip xray.zip
xray
mv xray.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable xray.service
systemctl start xray
