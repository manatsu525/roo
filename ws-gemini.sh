#!/bin/bash

# 定义 V2Ray 下载链接
V2RAY_DOWNLOAD_URL="https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip"
V2RAY_DIR="/usr/local/v2ray"
V2RAY_BIN="$V2RAY_DIR/v2ray"
V2RAY_CONFIG="$V2RAY_DIR/config.json"
V2RAY_SERVICE="v2ray.service"
V2RAY_SYSTEMD_CONFIG="/etc/systemd/system/$V2RAY_SERVICE"

NGINX_SERVICE="nginx.service"
NGINX_CONFIG_DIR="/etc/nginx"
NGINX_DEFAULT_SITE="$NGINX_CONFIG_DIR/sites-available/default"
NGINX_V2RAY_CONFIG="$NGINX_CONFIG_DIR/sites-available/v2ray"
NGINX_V2RAY_CONFIG_ENABLED="$NGINX_CONFIG_DIR/sites-enabled/v2ray"
NGINX_FILE_SERVER_CONFIG="$NGINX_CONFIG_DIR/sites-available/fileserver"
NGINX_FILE_SERVER_CONFIG_ENABLED="$NGINX_CONFIG_DIR/sites-enabled/fileserver"
FILE_SERVER_PATH="/usr/download"

CERTBOT_RENEW_CRON="/etc/cron.d/certbot_renew_v2ray"

# 默认配置
DEFAULT_PROTOCOL="vmess"
DEFAULT_TRANSPORT="ws"
DEFAULT_WS_PATH="/natsu"
DEFAULT_MKCP_DISGUISE="none"
DEFAULT_TLS="yes"
DEFAULT_PORT="443"
DEFAULT_VMESS_ID=$(uuidgen)
DEFAULT_VMESS_ALTERID="0"
DEFAULT_LISTEN_ADDRESS="0.0.0.0"
DEFAULT_DOMAIN=""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 检查是否安装了 curl 和 unzip
check_dependencies() {
    echo -e "${YELLOW}检查依赖...${NC}"
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}错误：curl 未安装，请先安装：apt update && apt install -y curl${NC}"
        exit 1
    fi
    if ! command -v unzip &> /dev/null; then
        echo -e "${RED}错误：unzip 未安装，请先安装：apt update && apt install -y unzip${NC}"
        exit 1
    fi
    echo -e "${GREEN}依赖检查完成。${NC}"
}

# 下载并安装 V2Ray
install_v2ray() {
    echo -e "${YELLOW}下载并安装 V2Ray...${NC}"
    mkdir -p "$V2RAY_DIR"
    curl -L "$V2RAY_DOWNLOAD_URL" -o "$V2RAY_DIR/v2ray.zip"
    cd "$V2RAY_DIR" || exit 1
    unzip v2ray.zip
    chmod +x "$V2RAY_BIN"
    echo -e "${GREEN}V2Ray 下载完成并解压到 ${V2RAY_DIR}${NC}"
}

# 创建 V2Ray systemd 服务
create_v2ray_service() {
    echo -e "${YELLOW}创建 V2Ray systemd 服务...${NC}"
    cat > "$V2RAY_SYSTEMD_CONFIG" <<EOF
[Unit]
Description=V2Ray Service
After=network.target

[Service]
User=root
WorkingDirectory=$V2RAY_DIR
ExecStart=$V2RAY_BIN run -config $V2RAY_CONFIG
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$V2RAY_SERVICE"
    echo -e "${GREEN}V2Ray systemd 服务创建完成。${NC}"
}

# 配置 V2Ray
configure_v2ray() {
    local protocol
    local transport
    local ws_path
    local mkcp_disguise
    local tls
    local port
    local vmess_id
    local vmess_alterid
    local listen_address
    local domain

    echo -e "${YELLOW}配置 V2Ray...${NC}"

    # 选择协议
    select protocol in "vmess" "vless"; do
        case "$protocol" in
            "vmess") break ;;
            "vless") break ;;
            *) echo "无效的选择，请重新选择。" ;;
        esac
    done
    protocol="${protocol:-$DEFAULT_PROTOCOL}"
    echo "选择的协议：${GREEN}$protocol${NC}"

    # 选择传输方式
    select transport in "ws" "mkcp" "quic" "grpc"; do
        case "$transport" in
            "ws") break ;;
            "mkcp") break ;;
            "quic") break ;;
            "grpc") break ;;
            *) echo "无效的选择，请重新选择。" ;;
        esac
    done
    transport="${transport:-$DEFAULT_TRANSPORT}"
    echo "选择的传输方式：${GREEN}$transport${NC}"

    # 配置通用参数
    read -p "监听地址 (默认: $DEFAULT_LISTEN_ADDRESS): " listen_address
    listen_address="${listen_address:-$DEFAULT_LISTEN_ADDRESS}"

    read -p "监听端口 (默认: $DEFAULT_PORT): " port
    port="${port:-$DEFAULT_PORT}"

    # 配置 TLS
    if [[ "$transport" == "ws" || "$transport" == "grpc" || "$transport" == "quic" ]]; then
        select tls in "yes" "no"; do
            case "$tls" in
                "yes") break ;;
                "no") break ;;
                *) echo "无效的选择，请重新选择。" ;;
            esac
        done
        tls="${tls:-$DEFAULT_TLS}"
        echo "是否启用 TLS：${GREEN}$tls${NC}"

        if [[ "$tls" == "yes" ]]; then
            read -p "域名 (用于 TLS，例如: yourdomain.com): " domain
            domain="${domain:-$DEFAULT_DOMAIN}"
            if [[ -z "$domain" ]]; then
                echo -e "${RED}错误：启用 TLS 时域名不能为空。${NC}"
                return 1
            fi
        fi
    else
        tls="no"
    fi

    # 配置 WebSocket
    if [[ "$transport" == "ws" ]]; then
        read -p "WebSocket 路径 (默认: $DEFAULT_WS_PATH): " ws_path
        ws_path="${ws_path:-$DEFAULT_WS_PATH}"
    fi

    # 配置 MKCP
    if [[ "$transport" == "mkcp" ]]; then
        select mkcp_disguise in "none" "srtp" "utp" "wechat-video" "dtls" "wireguard"; do
            case "$mkcp_disguise" in
                "none") break ;;
                "srtp") break ;;
                "utp") break ;;
                "wechat-video") break ;;
                "dtls") break ;;
                "wireguard") break ;;
                *) echo "无效的选择，请重新选择。" ;;
            esac
        done
        mkcp_disguise="${mkcp_disguise:-$DEFAULT_MKCP_DISGUISE}"
        echo "MKCP 伪装类型：${GREEN}$mkcp_disguise${NC}"
    fi

    # 配置 VMess
    if [[ "$protocol" == "vmess" ]]; then
        read -p "VMess 用户 ID (UUID) (默认: $DEFAULT_VMESS_ID): " vmess_id
        vmess_id="${vmess_id:-$DEFAULT_VMESS_ID}"
        read -p "VMess AlterID (默认: $DEFAULT_VMESS_ALTERID): " vmess_alterid
        vmess_alterid="${vmess_alterid:-$DEFAULT_VMESS_ALTERID}"
    fi

    # 生成 V2Ray 配置文件
    echo -e "${YELLOW}生成 V2Ray 配置文件...${NC}"
    cat > "$V2RAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "",
    "error": ""
  },
  "inbound": {
    "port": $port,
    "listen": "$listen_address",
    "protocol": "$protocol",
    "settings": {
EOF
    if [[ "$protocol" == "vmess" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
          "clients": [
            {
              "id": "$vmess_id",
              "alterId": "$vmess_alterid"
            }
          ]
EOF
    elif [[ "$protocol" == "vless" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
          "decryption": "none",
          "clients": [
            {
              "id": "$vmess_id" # VLESS 同样使用 UUID 作为 ID
            }
          ]
EOF
    fi
    cat >> "$V2RAY_CONFIG" <<EOF
    },
    "streamSettings": {
      "network": "$transport",
EOF
    if [[ "$transport" == "ws" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
      "wsSettings": {
        "path": "$ws_path"
      }
EOF
    elif [[ "$transport" == "mkcp" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
      "kcpSettings": {
        "uplinkCapacity": 100,
        "downlinkCapacity": 200,
        "congestion": false,
        "mtu": 1350,
        "tti": 20,
        "writeBufferSize": 2097152,
        "readBufferSize": 2097152,
        "header": {
          "type": "$mkcp_disguise"
        }
      }
EOF
    elif [[ "$transport" == "grpc" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
      "grpcSettings": {
        "serviceName": ""
      }
EOF
    elif [[ "$transport" == "quic" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
      "quicSettings": {
        "security": "none",
        "key": "",
        "padding": "false"
      }
EOF
    fi
    if [[ "$tls" == "yes" ]]; then
        cat >> "$V2RAY_CONFIG" <<EOF
      ,"security": "tls",
      "tlsSettings": {
        "alpn": [
EOF
        if [[ "$transport" == "ws" ]]; then
            cat >> "$V2RAY_CONFIG" <<EOF
          "http/1.1"
EOF
        elif [[ "$transport" == "grpc" ]]; then
            cat >> "$V2RAY_CONFIG" <<EOF
          "h2"
EOF
        elif [[ "$transport" == "quic" ]]; then
            cat >> "$V2RAY_CONFIG" <<EOF
          "http/3"
EOF
        fi
        cat >> "$V2RAY_CONFIG" <<EOF
        ],
        "certificates": [
          {
            "certificateFile": "/etc/letsencrypt/live/$domain/fullchain.pem",
            "keyFile": "/etc/letsencrypt/live/$domain/privkey.pem"
          }
        ]
      }
EOF
    else
        cat >> "$V2RAY_CONFIG" <<EOF
      ,"security": "none"
EOF
    fi
    cat >> "$V2RAY_CONFIG" <<EOF
    }
  },
  "outbound": {
    "protocol": "freedom",
    "settings": {}
  },
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  },
  "dns": {
    "servers": [
      "https://cloudflare-dns.com/dns-query",
      "https://1.1.1.1/dns-query"
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "uplinkOnly": 0,
        "downlinkOnly": 0
      }
    }
  },
  "stats": {}
}
EOF
    echo -e "${GREEN}V2Ray 配置文件生成完成。${NC}"
}

# 启动 V2Ray 服务
start_v2ray_service() {
    echo -e "${YELLOW}启动 V2Ray 服务...${NC}"
    systemctl start "$V2RAY_SERVICE"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}V2Ray 服务已启动。${NC}"
    else
        echo -e "${RED}启动 V2Ray 服务失败，请检查日志：journalctl -u $V2RAY_SERVICE${NC}"
    fi
}

# 停止 V2Ray 服务
stop_v2ray_service() {
    echo -e "${YELLOW}停止 V2Ray 服务...${NC}"
    systemctl stop "$V2RAY_SERVICE"
    echo -e "${GREEN}V2Ray 服务已停止。${NC}"
}

# 重启 V2Ray 服务
restart_v2ray_service() {
    echo -e "${YELLOW}重启 V2Ray 服务...${NC}"
    systemctl restart "$V2RAY_SERVICE"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}V2Ray 服务已重启。${NC}"
    else
        echo -e "${RED}重启 V2Ray 服务失败，请检查日志：journalctl -u $V2RAY_SERVICE${NC}"
    fi
}

# 卸载 V2Ray
uninstall_v2ray() {
    echo -e "${YELLOW}卸载 V2Ray...${NC}"
    stop_v2ray_service
    systemctl disable "$V2RAY_SERVICE"
    rm -f "$V2RAY_SYSTEMD_CONFIG"
    rm -rf "$V2RAY_DIR"
    echo -e "${GREEN}V2Ray 已卸载。${NC}"
    uninstall_nginx
}

# 安装 Nginx
install_nginx() {
    echo -e "${YELLOW}安装 Nginx...${NC}"
    apt update
    apt install -y nginx
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Nginx 安装完成。${NC}"
        configure_nginx_v2ray
        configure_nginx_fileserver
        enable_nginx_v2ray
        enable_nginx_fileserver
        start_nginx_service
        install_certbot
    else
        echo -e "${RED}Nginx 安装失败。${NC}"
    fi
}

# 配置 Nginx 反代 V2Ray
configure_nginx_v2ray() {
    local ws_path=$(grep '"path":' "$V2RAY_CONFIG" | awk -F '"' '{print $4}')
    local domain=$(grep '"certificateFile":' "$V2RAY_CONFIG" | awk -F '/' '{print $(NF-1)}')

    echo -e "${YELLOW}配置 Nginx 反代 V2Ray (路径: ${ws_path})...${NC}"
    cat > "$NGINX_V2RAY_CONFIG" <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+AESGCM:CHACHA20;
    ssl_prefer_server_ciphers off;

    access_log /var/log/nginx/$domain.access.log;
    error_log /var/log/nginx/$domain.error.log;

    root /var/www/html;
    index index.html index.htm;

    location /natsu {
        proxy_pass http://127.0.0.1:$(grep '"port":' "$V2RAY_CONFIG" | awk -F ':' '{print $2}' | tr -d '," ');
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        #proxy_set_header X-Real-IP \$remote_addr;
        #proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # 伪装网站
    location / {
        proxy_pass http://www.honda.com;
        proxy_set_header Host www.honda.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    echo -e "${GREEN}Nginx 反代 V2Ray 配置完成。${NC}"
}

# 配置 Nginx 文件服务器
configure_nginx_fileserver() {
    echo -e "${YELLOW}配置 Nginx 文件服务器 (路径: /file -> ${FILE_SERVER_PATH})...${NC}"
    cat > "$NGINX_FILE_SERVER_CONFIG" <<EOF
server {
    listen 8080;
    listen [::]:8080;

    server_name _; # 可以通过 IP:8080 访问

    location /file/ {
        alias $FILE_SERVER_PATH/;
        autoindex on;
    }
}
EOF
    mkdir -p "$FILE_SERVER_PATH"
    echo -e "${GREEN}Nginx 文件服务器配置完成，文件请放置在 ${FILE_SERVER_PATH} 目录下。${NC}"
}

# 启用 Nginx V2Ray 配置
enable_nginx_v2ray() {
    echo -e "${YELLOW}启用 Nginx V2Ray 配置...${NC}"
    if [[ -f "$NGINX_V2RAY_CONFIG_ENABLED" ]]; then
        rm -f "$NGINX_V2RAY_CONFIG_ENABLED"
    fi
    ln -s "$NGINX_V2RAY_CONFIG" "$NGINX_V2RAY_CONFIG_ENABLED"
    echo -e "${GREEN}Nginx V2Ray 配置已启用。${NC}"
}

# 启用 Nginx 文件服务器配置
enable_nginx_fileserver() {
    echo -e "${YELLOW}启用 Nginx 文件服务器配置...${NC}"
    if [[ -f "$NGINX_FILE_SERVER_CONFIG_ENABLED" ]]; then
        rm -f "$NGINX_FILE_SERVER_CONFIG_ENABLED"
    fi
    ln -s "$NGINX_FILE_SERVER_CONFIG" "$NGINX_FILE_SERVER_CONFIG_ENABLED"
    echo -e "${GREEN}Nginx 文件服务器配置已启用。${NC}"
}

# 启动 Nginx 服务
start_nginx_service() {
    echo -e "${YELLOW}启动 Nginx 服务...${NC}"
    systemctl start "$NGINX_SERVICE"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Nginx 服务已启动。${NC}"
    else
        echo -e "${RED}启动 Nginx 服务失败，请检查日志：journalctl -u $NGINX_SERVICE${NC}"
    fi
}

# 停止 Nginx 服务
stop_nginx_service() {
    echo -e "${YELLOW}停止 Nginx 服务...${NC}"
    systemctl stop "$NGINX_SERVICE"
    echo -e "${GREEN}Nginx 服务已停止。${NC}"
}

# 重启 Nginx 服务
restart_nginx_service() {
    echo -e "${YELLOW}重启 Nginx 服务...${NC}"
    systemctl restart "$NGINX_SERVICE"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Nginx 服务已重启。${NC}"
    else
        echo -e "${RED}重启 Nginx 服务失败，请检查日志：journalctl -u $NGINX_SERVICE${NC}"
    fi
}

# 卸载 Nginx
uninstall_nginx() {
    echo -e "${YELLOW}卸载 Nginx...${NC}"
    stop_nginx_service
    systemctl disable "$NGINX_SERVICE"
    apt purge -y nginx nginx-common nginx-full
    rm -rf "$NGINX_CONFIG_DIR"
    rm -rf /var/log/nginx/
    rm -rf /var/www/html
    echo -e "${GREEN}Nginx 已卸载。${NC}"
}

# 安装 Certbot 用于自动更新证书
install_certbot() {
    local domain=$(grep '"certificateFile":' "$V2RAY_CONFIG" | awk -F '/' '{print $(NF-1)}')
    if [[ -z "$domain" ]]; then
        echo -e "${YELLOW}未配置域名，跳过 Certbot 安装。${NC}"
        return 0
    fi
    echo -e "${YELLOW}安装 Certbot 以自动更新证书...${NC}"
    apt update
    apt install -y certbot python3-certbot-nginx
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Certbot 安装完成。${NC}"
        setup_certbot_certificate "$domain"
        setup_certbot_autorenew
    else
        echo -e "${RED}Certbot 安装失败，请手动安装并配置。${NC}"
    fi
}

# 使用 Certbot 获取证书
setup_certbot_certificate() {
    local domain="$1"
    echo -e "${YELLOW}获取 Let's Encrypt 证书 (域名: $domain)...${NC}"
    # 尝试使用 --nginx 插件，如果失败则使用 --webroot
    certbot --nginx -d "$domain" --non-interactive --agree-tos --email your_email@example.com
    if [[ $? -ne 0 ]]; then
        echo -e "${YELLOW}使用 Nginx 插件获取证书失败，尝试使用 Webroot 方式...${NC}"
        certbot certonly --webroot -w /var/www/html -d "$domain" --non-interactive --agree-tos --email your_email@example.com
        if [[ $? -eq 0 ]]; then
            # 需要修改 Nginx 配置以使用新的证书
            echo -e "${YELLOW}请确保你的 Nginx 配置文件中使用了以下证书路径：${NC}"
            echo -e "${YELLOW}ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;${NC}"
            echo -e "${YELLOW}ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;${NC}"
            restart_nginx_service
        else
            echo -e "${RED}获取 Let's Encrypt 证书失败，请检查你的域名解析和 Certbot 配置。${NC}"
        fi
    fi
    echo -e "${GREEN}Let's Encrypt 证书获取完成。${NC}"
}

# 设置 Certbot 自动更新 (每两个月)
setup_certbot_autorenew() {
    echo -e "${YELLOW}设置 Certbot 自动更新 (每两个月)...${NC}"
    local cron_command="0 0 */60 * * certbot renew --quiet --no-post-hook"
    echo "$cron_command" > "$CERTBOT_RENEW_CRON"
    chmod 0644 "$CERTBOT_RENEW_CRON"
    echo -e "${GREEN}Certbot 自动更新已设置为每两个月执行一次。${NC}"
}

# 显示 V2Ray 客户端配置 URL
show_v2ray_url() {
    if [[ ! -f "$V2RAY_CONFIG" ]]; then
        echo -e "${RED}错误：V2Ray 配置文件不存在，请先搭建 V2Ray。${NC}"
        return 1
    fi

    local protocol=$(jq -r .inbound.protocol "$V2RAY_CONFIG")
    local port=$(jq -r .inbound.port "$V2RAY_CONFIG")
    local id=$(jq -r .inbound.settings.clients[0].id "$V2RAY_CONFIG" 2>/dev/null || jq -r .inbound.settings.clients[0].id "$V2RAY_CONFIG") # 兼容 vmess 和 vless
    local ws_path=$(jq -r .inbound.streamSettings.wsSettings.path "$V2RAY_CONFIG" 2>/dev/null)
    local domain=$(jq -r .inbound.streamSettings.tlsSettings.certificates[0].certificateFile "$V2RAY_CONFIG" 2>/dev/null | awk -F '/' '{print $(NF-1)}')
    local transport=$(jq -r .inbound.streamSettings.network "$V2RAY_CONFIG")
    local tls=$(jq -r .inbound.streamSettings.security "$V2RAY_CONFIG")

    echo -e "${YELLOW}V2Ray 客户端配置 URL：${NC}"

    if [[ "$protocol" == "vmess" ]]; then
        local alterId=$(jq -r .inbound.settings.clients[0].alterId "$V2RAY_CONFIG")
        local url="vmess://${id}@${domain}:${port}?security=${tls}&type=${transport}"
        if [[ "$transport" == "ws" ]]; then
            url="${url}&path=${ws_path}&host=${domain}"
        fi
        echo -e "${GREEN}$url${NC}"
    elif [[ "$protocol" == "vless" ]]; then
        local url="vless://${id}@${domain}:${port}?security=${tls}&type=${transport}"
        if [[ "$transport" == "ws" ]]; then
            url="${url}&path=${ws_path}&host=${domain}"
        elif [[ "$transport" == "grpc" ]]; then
            local serviceName=$(jq -r .inbound.streamSettings.grpcSettings.serviceName "$V2RAY_CONFIG")
            url="${url}&serviceName=${serviceName}"
        elif [[ "$transport" == "quic" ]]; then
            url="${url}&quicSecurity=none&key="
        fi
        echo -e "${GREEN}$url${NC}"
    fi
}

# 修改 V2Ray 配置
modify_v2ray_config() {
    echo -e "${YELLOW}修改 V2Ray 配置...${NC}"
    stop_v2ray_service
    configure_v2ray
    create_v2ray_service # 重新创建服务以应用新的配置
    start_v2ray_service
    if is_nginx_installed; then
        configure_nginx_v2ray
        restart_nginx_service
    fi
    echo -e "${GREEN}V2Ray 配置已修改并重启。${NC}"
}

# 检查是否已安装 Nginx
is_nginx_installed() {
    command -v nginx &> /dev/null
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${YELLOW}V2Ray 搭建管理脚本${NC}"
        echo "1. 搭建 V2Ray (包含 Nginx)"
        echo "2. 卸载 V2Ray (包含 Nginx)"
        echo "3. 修改 V2Ray 配置"
        echo "4. 显示 V2Ray 客户端 URL"
        echo "5. 退出"
        read -p "请选择操作: " choice

        case "$choice" in
            1)
                check_dependencies
                install_v2ray
                create_v2ray_service
                configure_v2ray
                install_nginx
                start_v2ray_service
                ;;
            2)
                uninstall_v2ray
                ;;
            3)
                if [[ ! -f "$V2RAY_CONFIG" ]]; then
                    echo -e "${RED}错误：V2Ray 尚未搭建。${NC}"
                else
                    modify_v2ray_config
                fi
                ;;
            4)
                if [[ ! -f "$V2RAY_CONFIG" ]]; then
                    echo -e "${RED}错误：V2Ray 尚未搭建。${NC}"
                else
                    show_v2ray_url
                fi
                ;;
            5)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效的选择，请重新输入。"
                ;;
        esac
    done
}

# 检查是否以 root 身份运行
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}请以 root 权限运行此脚本。${NC}"
    exit 1
fi

# 运行主菜单
main_menu
