#!/bin/bash

cd /root

read -p "input domain:" domain
export domain
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

sed -i "s/www-data/root/g" /etc/nginx/nginx.conf

cat > /etc/nginx/conf.d/default.conf <<-EOF
server {
    ### 1:
    server_name ${domain};
    listen [::]:80;
    listen 80;
    if (\$request_method  !~ ^(POST|GET)$) { return  501; }
    autoindex off;
    server_tokens off;
}
EOF

systemctl daemon-reload
systemctl restart nginx

echo -e "0. auto pem   1. no pem"
read -p "请选择（仅填数字）:" num

if [[ "${num}" == "0" ]];then
    bash <(curl -L -s https://raw.githubusercontent.com/manatsu525/roo/master/acme-nginx.sh)
fi

cat > /etc/nginx/conf.d/default.conf <<-EOF
server {
    ### 1:
    server_name ${domain};
    listen [::]:80;
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
    listen [::]:443 ssl http2;
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

systemctl restart nginx
systemctl enable nginx.service


v2ray(){
cat > v2ray.service <<-EOF
[Unit]
Description=v2ray(/etc/systemd/system/v2ray.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/v2ray run -config /root/config.json
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}

cd /root
wget -O v2ray.zip https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip
unzip v2ray.zip
v2ray
mv v2ray.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable v2ray.service
systemctl start v2ray

cat >/root/vmess_qr.json <<-EOF
{
	"v": "2",
	"ps": "${domain}",
	"add": "${domain}",
	"port": "443",
	"id": "3e88bf4b-a1ab-4c36-bc83-ea7d263e5239",
	"aid": "0",
	"net": "ws",
	"type": "none",
	"host": "${domain}",
	"path": "/natsu",
	"tls": "tls"
}
EOF

vmess="vmess://$(cat /root/vmess_qr.json | base64 -w 0)"
echo $vmess
