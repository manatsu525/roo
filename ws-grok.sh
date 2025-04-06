#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "请以root权限运行此脚本：sudo $0"
    exit 1
fi

apt install uuid-runtime -y

# 定义变量
CONFIG_DIR="/usr/local/etc/v2ray"
CONFIG_FILE="$CONFIG_DIR/config.json"
V2RAY_BIN="/usr/local/bin/v2ray"
V2RAY_URL="https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip"
NGINX_CONF="/etc/nginx/sites-available/v2ray"
NGINX_LINK="/etc/nginx/sites-enabled/v2ray"
UUID=$(uuidgen)
PORT=1080
WS_PORT=443
ALTER_ID=0
DOMAIN=""
CERT_FILE="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_FILE="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
MKCP_TYPE="none"
DOWNLOAD_DIR="/usr/download"

# 检查并安装依赖
install_dependencies() {
    echo "正在更新包列表并安装依赖..."
    apt update -y
    apt install -y curl unzip jq nginx certbot python3-certbot-nginx
    mkdir -p "$DOWNLOAD_DIR"
    chown -R www-data:www-data "$DOWNLOAD_DIR"
    chmod -R 755 "$DOWNLOAD_DIR"
}

# 安装V2Ray
install_v2ray() {
    if [ -f "$V2RAY_BIN" ]; then
        echo "V2Ray已安装，跳过安装步骤。"
        return
    fi
    echo "正在从 $V2RAY_URL 下载并安装V2Ray..."
    curl -L -o v2ray.zip "$V2RAY_URL"
    unzip -o v2ray.zip -d /usr/local/bin/
    chmod +x "$V2RAY_BIN"
    rm v2ray.zip
    mkdir -p "$CONFIG_DIR"
    systemctl enable v2ray
}

# 配置TLS证书并设置自动续期（每两个月一次）
configure_tls() {
    echo "请输入你的域名（用于TLS证书和伪装网站）："
    read DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo "域名不能为空，跳过TLS配置。"
        return 1
    fi
    echo "正在为 $DOMAIN 获取TLS证书..."
    certbot certonly --nginx -d "$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN
    CERT_FILE="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    KEY_FILE="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        echo "证书获取失败，请检查域名或手动配置证书。"
        return 1
    fi

    # 配置证书自动续期，每60天检查一次
    echo "正在配置证书自动续期（每两个月一次）..."
    cat > /etc/cron.d/certbot-renew <<EOF
0 0 1 */2 * root certbot renew --quiet --post-hook "systemctl restart nginx v2ray"
EOF
    echo "证书自动续期已配置，每两个月（60天）的1号0点检查并更新证书，更新后重启Nginx和V2Ray。"
    return 0
}

# 配置Nginx反向代理、伪装网站和文件服务器
configure_nginx() {
    echo "正在配置Nginx作为前端，反代 www.honda.com，分流 /natsu，并启用文件服务器 /file..."
    cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location /natsu {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    location /file {
        alias $DOWNLOAD_DIR/;
        autoindex on;
    }

    location / {
        proxy_pass http://www.honda.com;
        proxy_set_header Host www.honda.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
    ln -sf "$NGINX_CONF" "$NGINX_LINK"
    systemctl restart nginx
    echo "Nginx配置完成，伪装网站和文件服务器已启用。"
}

# 生成配置文件
generate_config() {
    local protocol=$1
    local transport=$2
    case $protocol in
        "vmess")
            case $transport in
                "tcp")
                    cat > "$CONFIG_FILE" <<EOF
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "$UUID", "alterId": $ALTER_ID}]
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
                    ;;
                "ws")
                    cat > "$CONFIG_FILE" <<EOF
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "$UUID", "alterId": $ALTER_ID}]
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": {"path": "/natsu"}
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
                    ;;
                "mkcp")
                    cat > "$CONFIG_FILE" <<EOF
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "$UUID", "alterId": $ALTER_ID}]
        },
        "streamSettings": {
            "network": "kcp",
            "kcpSettings": {
                "header": {"type": "$MKCP_TYPE"}
            }
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
                    ;;
                "quic")
                    cat > "$CONFIG_FILE" <<EOF
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "$UUID", "alterId": $ALTER_ID}]
        },
        "streamSettings": {
            "network": "quic",
            "security": "tls",
            "tlsSettings": {
                "certificates": [{"certificateFile": "$CERT_FILE", "keyFile": "$KEY_FILE"}]
            }
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
                    ;;
            esac
            ;;
        "vless")
            case $transport in
                "ws")
                    cat > "$CONFIG_FILE" <<EOF
{
    "inbounds": [{
        "port": $PORT,
        "protocol": "vless",
        "settings": {
            "clients": [{"id": "$UUID"}],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": {"path": "/natsu"}
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF
                    ;;
            esac
            ;;
    esac
    echo "配置文件已生成：$CONFIG_FILE"
}

# 显示URL
show_url() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件不存在，请先搭建服务。"
        return
    
    local config=$(jq -r '.inbounds[0]' "$CONFIG_FILE")
    local port=$(echo "$config" | jq -r '.port')
    local protocol=$(echo "$config" | jq -r '.protocol')
    local uuid=$(echo "$config" | jq -r '.settings.clients[0].id')
    local alter_id=$(echo "$config" | jq -r '.settings.clients[0].alterId // 0')
    local network=$(echo "$config" | jq -r '.streamSettings.network // "tcp"')
    local path=$(echo "$config" | jq -r '.streamSettings.wsSettings.path // ""')
    local security=$(echo "$config" | jq -r '.streamSettings.security // "none"')
    local vmess_url="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"v2ray_debian\",\"add\":\"$DOMAIN\",\"port\":\"$WS_PORT\",\"id\":\"$uuid\",\"aid\":\"$alter_id\",\"net\":\"$network\",\"type\":\"none\",\"path\":\"$path\",\"tls\":\"$security\"}" | base64 -w 0)"
    echo "URL: $vmess_url"
}

# 删除所有服务
delete_all() {
    echo "正在删除V2Ray和Nginx服务..."
    systemctl stop v2ray nginx
    systemctl disable v2ray nginx
    rm -rf "$CONFIG_DIR" "$V2RAY_BIN" /etc/systemd/system/v2ray* "$NGINX_CONF" "$NGINX_LINK" /etc/nginx/sites-enabled/default /etc/cron.d/certbot-renew
    apt purge -y nginx nginx-common nginx-full certbot python3-certbot-nginx
    apt autoremove -y
    systemctl daemon-reload
    echo "V2Ray和Nginx已彻底删除，包括证书续期任务。"
}

# 主菜单
main_menu() {
    while true; do
        echo "================================="
        echo "     V2Ray 搭建管理脚本"
        echo "================================="
        echo "1. 搭建V2Ray服务"
        echo "2. 删除V2Ray和Nginx服务"
        echo "3. 修改V2Ray配置"
        echo "4. 显示V2Ray URL"
        echo "5. 退出"
        echo "请选择操作："
        read choice

        case $choice in
            1)
                install_dependencies
                install_v2ray
                echo "请选择协议：1) VMess  2) VLESS"
                read proto_choice
                case $proto_choice in
                    1) PROTOCOL="vmess";;
                    2) PROTOCOL="vless";;
                    *) echo "无效选择，默认使用VMess"; PROTOCOL="vmess";;
                esac
                echo "请选择传输方式：1) TCP  2) WebSocket+TLS  3) mKCP  4) QUIC"
                read trans_choice
                case $trans_choice in
                    1) TRANSPORT="tcp";;
                    2) TRANSPORT="ws"; configure_tls && configure_nginx;;
                    3) 
                        TRANSPORT="mkcp"
                        echo "请选择mKCP伪装类型：1) none  2) srtp  3) utp  4) wechat-video  5) dtls"
                        read mkcp_choice
                        case $mkcp_choice in
                            1) MKCP_TYPE="none";;
                            2) MKCP_TYPE="srtp";;
                            3) MKCP_TYPE="utp";;
                            4) MKCP_TYPE="wechat-video";;
                            5) MKCP_TYPE="dtls";;
                            *) echo "无效选择，默认使用none"; MKCP_TYPE="none";;
                        esac
                        ;;
                    4) TRANSPORT="quic"; configure_tls;;
                    *) echo "无效选择，默认使用TCP"; TRANSPORT="tcp";;
                esac
                echo "请输入监听端口（默认1080，WS+TLS时为后端端口）："
                read input_port
                PORT=${input_port:-$PORT}
                echo "请输入UUID（默认随机生成：$UUID，留空使用默认）："
                read input_uuid
                UUID=${input_uuid:-$UUID}
                if [ "$PROTOCOL" = "vmess" ]; then
                    echo "请输入AlterID（默认0）："
                    read input_alter_id
                    ALTER_ID=${input_alter_id:-$ALTER_ID}
                fi
                generate_config "$PROTOCOL" "$TRANSPORT"
                systemctl start v2ray
                echo "V2Ray服务已搭建并启动。"
                ;;
            2)
                delete_all
                ;;
            3)
                if [ ! -f "$CONFIG_FILE" ]; then
                    echo "配置文件不存在，请先搭建服务。"
                else
                    echo "当前配置："
                    jq '.' "$CONFIG_FILE"
                    echo "请输入新端口（当前：$PORT）："
                    read new_port
                    PORT=${new_port:-$PORT}
                    echo "请输入新UUID（当前：$UUID，留空则不变）："
                    read new_uuid
                    UUID=${new_uuid:-$UUID}
                    if [ "$(jq -r '.inbounds[0].protocol' "$CONFIG_FILE")" = "vmess" ]; then
                        echo "请输入新AlterID（当前：$ALTER_ID）："
                        read new_alter_id
                        ALTER_ID=${new_alter_id:-$ALTER_ID}
                    fi
                    generate_config "$(jq -r '.inbounds[0].protocol' "$CONFIG_FILE")" "$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$CONFIG_FILE")"
                    systemctl restart v2ray
                    echo "配置已更新并重启服务。"
                fi
                ;;
            4)
                show_url
                ;;
            5)
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请重试。"
                ;;
        esac
    done
}

# 执行主菜单
main_menu
