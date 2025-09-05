#!/bin/bash

# VMess搭建管理脚本
# 适用于Debian系统

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
CLEAR='\033[0m'

# 配置文件路径
V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"
V2RAY_SERVICE="/etc/systemd/system/v2ray.service"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
DOWNLOAD_DIR="/usr/download"
CERT_EMAIL="lineair069@gmail.com"

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}错误：请使用root权限运行此脚本${CLEAR}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${GREEN}正在安装依赖...${CLEAR}"
    apt update -y
    apt install -y wget unzip nginx certbot python3-certbot-nginx socat cron curl
}

# 下载并安装V2Ray
install_v2ray() {
    echo -e "${GREEN}正在下载V2Ray...${CLEAR}"
    cd /tmp
    wget -O v2ray-linux-64.zip https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip
    
    # 创建目录
    mkdir -p /usr/local/bin/v2ray
    mkdir -p /usr/local/etc/v2ray
    mkdir -p /var/log/v2ray
    
    # 解压文件
    unzip -o v2ray-linux-64.zip -d /usr/local/bin/v2ray
    
    # 设置权限
    chmod +x /usr/local/bin/v2ray/v2ray
    chmod +x /usr/local/bin/v2ray/v2ctl
    
    # 创建systemd服务
    cat > "$V2RAY_SERVICE" <<EOF
[Unit]
Description=V2Ray Service
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/v2ray/v2ray run -config $V2RAY_CONFIG
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable v2ray
}

# 生成UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 配置VMess+WS+TLS
configure_vmess_ws_tls() {
    echo -e "${CYAN}配置 VMess+WS+TLS${CLEAR}"
    
    read -p "请输入域名: " domain
    read -p "请输入V2Ray端口 (默认10000): " v2_port
    v2_port=${v2_port:-10000}
    read -p "请输入路径 (默认/natsu): " ws_path
    ws_path=${ws_path:-/natsu}
    
    uuid=$(generate_uuid)
    
    # 创建V2Ray配置
    cat > "$V2RAY_CONFIG" <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [{
    "port": $v2_port,
    "listen": "127.0.0.1",
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "$uuid",
        "alterId": 0
      }]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "$ws_path"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

    # 配置Nginx
    configure_nginx_ws "$domain" "$v2_port" "$ws_path"
    
    # 申请证书
    apply_certificate "$domain"
    
    # 保存配置信息
    save_config "ws" "$domain" "$uuid" "443" "$ws_path"
    
    # 重启服务
    systemctl restart v2ray
    systemctl restart nginx
}

# 配置VLess+WS+TLS
configure_vless_ws_tls() {
    echo -e "${CYAN}配置 VLess+WS+TLS${CLEAR}"
    
    read -p "请输入域名: " domain
    read -p "请输入V2Ray端口 (默认10000): " v2_port
    v2_port=${v2_port:-10000}
    read -p "请输入路径 (默认/natsu): " ws_path
    ws_path=${ws_path:-/natsu}
    
    uuid=$(generate_uuid)
    
    # 创建V2Ray配置
    cat > "$V2RAY_CONFIG" <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [{
    "port": $v2_port,
    "listen": "127.0.0.1",
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "$uuid",
        "level": 0
      }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "$ws_path"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

    # 配置Nginx
    configure_nginx_ws "$domain" "$v2_port" "$ws_path"
    
    # 申请证书
    apply_certificate "$domain"
    
    # 保存配置信息
    save_config "vless" "$domain" "$uuid" "443" "$ws_path"
    
    # 重启服务
    systemctl restart v2ray
    systemctl restart nginx
}

# 配置VMess+mKCP
configure_vmess_mkcp() {
    echo -e "${CYAN}配置 VMess+mKCP${CLEAR}"
    
    read -p "请输入服务器端口 (默认8888): " port
    port=${port:-8888}
    
    echo "请选择伪装类型:"
    echo "1) none"
    echo "2) srtp"
    echo "3) utp"
    echo "4) wechat-video"
    echo "5) dtls"
    echo "6) wireguard"
    read -p "请选择 (1-6): " header_choice
    
    case $header_choice in
        1) header_type="none" ;;
        2) header_type="srtp" ;;
        3) header_type="utp" ;;
        4) header_type="wechat-video" ;;
        5) header_type="dtls" ;;
        6) header_type="wireguard" ;;
        *) header_type="none" ;;
    esac
    
    read -p "请输入mKCP seed (留空随机生成): " mkcp_seed
    if [ -z "$mkcp_seed" ]; then
        mkcp_seed=$(head -c 16 /dev/urandom | base64)
    fi
    
    uuid=$(generate_uuid)
    
    # 创建V2Ray配置
    cat > "$V2RAY_CONFIG" <<EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "info"
  },
  "inbounds": [{
    "port": $port,
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "$uuid",
        "alterId": 0
      }]
    },
    "streamSettings": {
      "network": "mkcp",
      "kcpSettings": {
        "mtu": 1350,
        "tti": 20,
        "uplinkCapacity": 10,
        "downlinkCapacity": 100,
        "congestion": false,
        "readBufferSize": 2,
        "writeBufferSize": 2,
        "header": {
          "type": "$header_type"
        },
        "seed": "$mkcp_seed"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF
    
    # 保存配置信息
    save_config "mkcp" "none" "$uuid" "$port" "" "$header_type" "$mkcp_seed"
    
    # 重启服务
    systemctl restart v2ray
}

# 配置Nginx
configure_nginx_ws() {
    local domain=$1
    local v2_port=$2
    local ws_path=$3
    
    # 创建文件下载目录
    mkdir -p "$DOWNLOAD_DIR"
    
    # 创建Nginx配置文件
    cat > "$NGINX_CONF_DIR/$domain" <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $domain;
    
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    
    # 伪装网站反代
    location / {
        proxy_pass https://www.honda.com;
        proxy_set_header Host www.honda.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_server_name on;
    }
    
    # V2Ray WebSocket
    location $ws_path {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$v2_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    # 文件服务器
    location /file {
        alias $DOWNLOAD_DIR;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
}
EOF
    
    # 启用网站
    ln -sf "$NGINX_CONF_DIR/$domain" "$NGINX_ENABLED_DIR/$domain"
}

# 申请证书
apply_certificate() {
    local domain=$1
    echo -e "${GREEN}正在申请SSL证书...${CLEAR}"
    
    # 先创建一个临时的nginx配置用于验证
    cat > "$NGINX_CONF_DIR/${domain}_temp" <<EOF
server {
    listen 80;
    server_name $domain;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
}
EOF
    
    ln -sf "$NGINX_CONF_DIR/${domain}_temp" "$NGINX_ENABLED_DIR/${domain}_temp"
    systemctl reload nginx
    
    # 申请证书
    certbot certonly --webroot -w /var/www/html -d "$domain" --non-interactive --agree-tos --email "$CERT_EMAIL"
    
    # 删除临时配置
    rm -f "$NGINX_CONF_DIR/${domain}_temp" "$NGINX_ENABLED_DIR/${domain}_temp"
    
    # 设置自动更新
    setup_cert_renewal "$domain"
}

# 设置证书自动更新
setup_cert_renewal() {
    local domain=$1
    
    # 创建更新脚本
    cat > "/usr/local/bin/renew-cert-${domain}.sh" <<EOF
#!/bin/bash
certbot renew --cert-name $domain --quiet
systemctl reload nginx
EOF
    
    chmod +x "/usr/local/bin/renew-cert-${domain}.sh"
    
    # 添加cron任务 - 每两个月更新一次
    (crontab -l 2>/dev/null | grep -v "renew-cert-${domain}"; echo "0 3 1 */2 * /usr/local/bin/renew-cert-${domain}.sh") | crontab -
}

# 保存配置信息
save_config() {
    local type=$1
    local domain=$2
    local uuid=$3
    local port=$4
    local path=$5
    local header=$6
    local seed=$7
    
    cat > "/usr/local/etc/v2ray/client_config.txt" <<EOF
配置类型: $type
域名: $domain
UUID: $uuid
端口: $port
路径: $path
伪装类型: $header
mKCP Seed: $seed
EOF
}

# 显示配置URL
show_url() {
    if [ ! -f "/usr/local/etc/v2ray/client_config.txt" ]; then
        echo -e "${RED}没有找到配置信息${CLEAR}"
        return
    fi
    
    echo -e "${GREEN}当前配置信息：${CLEAR}"
    cat "/usr/local/etc/v2ray/client_config.txt"
    
    # 从配置文件读取信息
    local type=$(grep "配置类型:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2)
    local domain=$(grep "域名:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2)
    local uuid=$(grep "UUID:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2)
    local port=$(grep "端口:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2)
    local path=$(grep "路径:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2)
    
    echo -e "\n${CYAN}客户端配置信息：${CLEAR}"
    
    if [[ "$type" == "ws" ]] || [[ "$type" == "vless" ]]; then
        echo -e "${YELLOW}协议: $type${CLEAR}"
        echo -e "${YELLOW}地址: $domain${CLEAR}"
        echo -e "${YELLOW}端口: $port${CLEAR}"
        echo -e "${YELLOW}UUID: $uuid${CLEAR}"
        echo -e "${YELLOW}路径: $path${CLEAR}"
        echo -e "${YELLOW}传输协议: ws${CLEAR}"
        echo -e "${YELLOW}TLS: 开启${CLEAR}"
    elif [[ "$type" == "mkcp" ]]; then
        local header=$(grep "伪装类型:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2)
        local seed=$(grep "mKCP Seed:" /usr/local/etc/v2ray/client_config.txt | cut -d' ' -f2-)
        local server_ip=$(curl -s ip.sb)
        
        echo -e "${YELLOW}协议: vmess${CLEAR}"
        echo -e "${YELLOW}地址: $server_ip${CLEAR}"
        echo -e "${YELLOW}端口: $port${CLEAR}"
        echo -e "${YELLOW}UUID: $uuid${CLEAR}"
        echo -e "${YELLOW}传输协议: mkcp${CLEAR}"
        echo -e "${YELLOW}伪装类型: $header${CLEAR}"
        echo -e "${YELLOW}mKCP Seed: $seed${CLEAR}"
    fi
}

# 修改配置
modify_config() {
    echo -e "${CYAN}修改配置${CLEAR}"
    echo "1) 修改UUID"
    echo "2) 修改端口"
    echo "3) 修改路径"
    echo "4) 重新配置"
    read -p "请选择: " choice
    
    case $choice in
        1)
            new_uuid=$(generate_uuid)
            sed -i "s/\"id\": \".*\"/\"id\": \"$new_uuid\"/" "$V2RAY_CONFIG"
            systemctl restart v2ray
            echo -e "${GREEN}UUID已更新为: $new_uuid${CLEAR}"
            ;;
        2)
            read -p "请输入新端口: " new_port
            sed -i "s/\"port\": [0-9]*/\"port\": $new_port/" "$V2RAY_CONFIG"
            systemctl restart v2ray
            echo -e "${GREEN}端口已更新为: $new_port${CLEAR}"
            ;;
        3)
            read -p "请输入新路径: " new_path
            sed -i "s|\"path\": \".*\"|\"path\": \"$new_path\"|" "$V2RAY_CONFIG"
            systemctl restart v2ray
            echo -e "${GREEN}路径已更新为: $new_path${CLEAR}"
            ;;
        4)
            uninstall_all
            install_v2ray_menu
            ;;
    esac
}

# 卸载所有组件
uninstall_all() {
    echo -e "${RED}正在卸载所有组件...${CLEAR}"
    
    # 停止服务
    systemctl stop v2ray 2>/dev/null
    systemctl stop nginx 2>/dev/null
    
    # 删除V2Ray
    systemctl disable v2ray 2>/dev/null
    rm -rf /usr/local/bin/v2ray
    rm -rf /usr/local/etc/v2ray
    rm -rf /var/log/v2ray
    rm -f "$V2RAY_SERVICE"
    
    # 删除Nginx配置（保留证书）
    rm -f $NGINX_CONF_DIR/*
    rm -f $NGINX_ENABLED_DIR/*
    
    # 卸载nginx
    apt remove --purge -y nginx nginx-common
    
    # 删除文件下载目录
    rm -rf "$DOWNLOAD_DIR"
    
    # 删除证书更新脚本和cron任务
    rm -f /usr/local/bin/renew-cert-*.sh
    crontab -l 2>/dev/null | grep -v "renew-cert" | crontab -
    
    echo -e "${GREEN}卸载完成（证书已保留）${CLEAR}"
}

# 安装菜单
install_v2ray_menu() {
    echo -e "${CYAN}请选择要安装的配置类型：${CLEAR}"
    echo "1) VMess + WebSocket + TLS"
    echo "2) VLess + WebSocket + TLS" 
    echo "3) VMess + mKCP"
    read -p "请选择 (1-3): " install_choice
    
    install_dependencies
    install_v2ray
    
    case $install_choice in
        1) configure_vmess_ws_tls ;;
        2) configure_vless_ws_tls ;;
        3) configure_vmess_mkcp ;;
        *) echo -e "${RED}无效选择${CLEAR}" ;;
    esac
}

# 主菜单
main_menu() {
    clear
    echo -e "${PURPLE}==================================${CLEAR}"
    echo -e "${CYAN}    V2Ray 搭建管理脚本${CLEAR}"
    echo -e "${PURPLE}==================================${CLEAR}"
    echo -e "${GREEN}1) 安装 V2Ray${CLEAR}"
    echo -e "${YELLOW}2) 显示配置信息/URL${CLEAR}"
    echo -e "${BLUE}3) 修改配置${CLEAR}"
    echo -e "${RED}4) 卸载所有组件${CLEAR}"
    echo -e "${PURPLE}0) 退出${CLEAR}"
    echo -e "${PURPLE}==================================${CLEAR}"
    
    read -p "请选择操作: " choice
    
    case $choice in
        1) install_v2ray_menu ;;
        2) show_url ;;
        3) modify_config ;;
        4) uninstall_all ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${CLEAR}" ;;
    esac
    
    echo -e "\n${GREEN}按任意键返回主菜单...${CLEAR}"
    read -n 1
    main_menu
}

# 主程序
check_root
main_menu
