#!/bin/bash

# V2Ray Management Script for Debian
# Author: AI Assistant based on user requirements
# Features: Install (VMess/VLess + TCP/mKCP/WS/QUIC/gRPC + TLS), Uninstall, Modify, Show URL, Auto Cert Renewal

# --- Configuration ---
V2RAY_INSTALL_DIR="/usr/local/bin/v2ray"
V2RAY_CONFIG_DIR="/etc/v2ray"
V2RAY_CONFIG_FILE="${V2RAY_CONFIG_DIR}/config.json"
V2RAY_SERVICE_FILE="/etc/systemd/system/v2ray.service"
V2RAY_DL_URL="https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip"
V2RAY_LOG_FILE="/var/log/v2ray/access.log"
V2RAY_ERROR_LOG_FILE="/var/log/v2ray/error.log"

NGINX_CONFIG_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
NGINX_V2RAY_CONF="v2ray_proxy"
DOWNLOAD_DIR="/usr/download"
CERT_EMAIL="lineair069@gmail.com"

STATE_FILE="${V2RAY_CONFIG_DIR}/install_state.conf" # To store selected options

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行。${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${BLUE}正在更新软件包列表并安装依赖项...${NC}"
    apt update
    apt install -y curl wget unzip socat jq net-tools \
                   nginx python3-certbot-nginx || {
        echo -e "${RED}错误: 依赖项安装失败。请检查网络连接和apt源。${NC}"
        exit 1
    }
    # 创建 V2Ray 日志目录
    mkdir -p /var/log/v2ray
    chown nobody:nogroup /var/log/v2ray
    echo -e "${GREEN}依赖项安装完成。${NC}"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

generate_random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-16} | head -n 1
}

download_and_extract_v2ray() {
    echo -e "${BLUE}正在下载 V2Ray 核心文件...${NC}"
    mkdir -p "$V2RAY_INSTALL_DIR"
    cd /tmp || exit 1
    curl -L -o v2ray.zip "$V2RAY_DL_URL" || { echo -e "${RED}下载 V2Ray 失败。${NC}"; exit 1; }

    echo -e "${BLUE}正在解压 V2Ray 文件...${NC}"
    unzip -o v2ray.zip -d "$V2RAY_INSTALL_DIR" || { echo -e "${RED}解压 V2Ray 失败。${NC}"; exit 1; }
    chmod +x "${V2RAY_INSTALL_DIR}/v2ray" "${V2RAY_INSTALL_DIR}/v2ctl"
    rm v2ray.zip

    # 移动 dat 文件到配置目录 (v4.27.1+ 需要)
    mv "${V2RAY_INSTALL_DIR}/geoip.dat" "${V2RAY_INSTALL_DIR}/geosite.dat" "$V2RAY_CONFIG_DIR/" 2>/dev/null

    echo -e "${GREEN}V2Ray 核心文件准备就绪。位于: ${V2RAY_INSTALL_DIR}${NC}"
}

configure_v2ray() {
    local protocol=$1
    local port=$2
    local transport=$3
    local domain=$4
    local uuid=$(generate_uuid)
    local alter_id=0 # Keep low for compatibility
    local mkcp_seed=$(generate_random_string 10)
    local mkcp_header="none"
    local ws_path="/natsu"
    local grpc_servicename=$(generate_random_string 8)
    local quic_security="aes-128-gcm"
    local quic_key=$(generate_random_string 12)
    local quic_header="none"
    local use_tls="false"

    mkdir -p "$V2RAY_CONFIG_DIR"

    # --- Interactive Prompts ---
    read -p "请输入 V2Ray 监听端口 (默认 443 for TLS, 80 for others): " V2RAY_PORT
    V2RAY_PORT=${V2RAY_PORT:-$( [[ "$transport" == "ws" || "$transport" == "grpc" || "$transport" == "quic" ]] && echo "443" || echo "80" )}

    read -p "请输入 V2Ray 用户 UUID (留空则自动生成): " USER_UUID
    uuid=${USER_UUID:-$(generate_uuid)}

    if [[ "$transport" == "mkcp" ]]; then
        echo "请选择 mKCP 伪装类型 (header type):"
        select header_choice in "none" "srtp" "utp" "wechat-video" "dtls" "wireguard"; do
            if [[ -n "$header_choice" ]]; then
                mkcp_header=$header_choice
                break
            else
                echo "无效选择，请重试。"
            fi
        done
        read -p "请输入 mKCP Seed (留空则自动生成): " USER_MKCP_SEED
        mkcp_seed=${USER_MKCP_SEED:-$(generate_random_string 10)}
    fi

    if [[ "$transport" == "ws" ]]; then
        read -p "请输入 WebSocket 路径 (必须以 / 开头, 默认 /natsu): " USER_WS_PATH
        ws_path=${USER_WS_PATH:-/natsu}
        if [[ ! "$ws_path" =~ ^/ ]]; then
            echo -e "${RED}错误: WebSocket 路径必须以 / 开头。${NC}"
            exit 1
        fi
    fi

    if [[ "$transport" == "grpc" ]]; then
         read -p "请输入 gRPC ServiceName (留空则自动生成): " USER_GRPC_SERVICENAME
         grpc_servicename=${USER_GRPC_SERVICENAME:-$(generate_random_string 8)}
    fi
     if [[ "$transport" == "quic" ]]; then
        echo "请选择 QUIC 伪装类型 (header type):"
        select quic_header_choice in "none" "srtp" "utp" "wechat-video" "dtls" "wireguard"; do
             if [[ -n "$quic_header_choice" ]]; then
                quic_header=$quic_header_choice
                break
            else
                echo "无效选择，请重试。"
            fi
        done
        read -p "请输入 QUIC 加密密钥 (留空则自动生成): " USER_QUIC_KEY
        quic_key=${USER_QUIC_KEY:-$(generate_random_string 12)}
         read -p "请输入 QUIC 加密方式 (默认 aes-128-gcm): " USER_QUIC_SECURITY
         quic_security=${USER_QUIC_SECURITY:-"aes-128-gcm"}
     fi

    # TLS Configuration
    if [[ "$transport" == "ws" || "$transport" == "grpc" || "$transport" == "quic" ]]; then
         read -p "是否启用 TLS? (y/N): " ENABLE_TLS
         if [[ "$ENABLE_TLS" =~ ^[Yy]$ ]]; then
             use_tls="true"
             while true; do
                read -p "请输入您的域名 (例如: mydomain.com): " domain
                if [[ -z "$domain" ]]; then
                    echo -e "${RED}错误: 启用 TLS 必须提供域名。${NC}"
                else
                    # Simple validation
                    if [[ "$domain" =~ \. ]]; then
                        break
                    else
                         echo -e "${RED}错误: 无效的域名格式。${NC}"
                    fi
                fi
             done
             # Use the main V2RAY_PORT (like 443) for external connection
             port=$V2RAY_PORT
             # Internal V2Ray port if using Nginx (for WS)
             if [[ "$transport" == "ws" ]]; then
                 V2RAY_INTERNAL_PORT=$(shuf -i 10000-65000 -n 1) # Use a random high port for internal communication
                 echo -e "${YELLOW}WebSocket+TLS 模式: Nginx 将监听端口 ${port}, V2Ray 内部监听端口 ${V2RAY_INTERNAL_PORT}${NC}"
             else
                 V2RAY_INTERNAL_PORT=$port # QUIC/gRPC listen directly on the TLS port
                 echo -e "${YELLOW}${transport^^}+TLS 模式: V2Ray 将直接监听端口 ${port}${NC}"
             fi
         else
             use_tls="false"
             port=$V2RAY_PORT # Use the user-specified port directly
             V2RAY_INTERNAL_PORT=$port
             echo -e "${YELLOW}未启用 TLS。V2Ray 将监听端口 ${port}${NC}"
             if [[ "$transport" == "ws" ]]; then
                 echo -e "${YELLOW}警告: WebSocket 不使用 TLS 可能不安全或被检测。${NC}"
             fi
         fi
    else # TCP or mKCP
         use_tls="false"
         port=$V2RAY_PORT
         V2RAY_INTERNAL_PORT=$port
         echo -e "${YELLOW}${transport^^} 模式: V2Ray 将监听端口 ${port}${NC}"
    fi


    # --- Build JSON Configuration using jq ---
    local inbound_settings
    local stream_settings

    # Base settings
    jq -n \
      --arg V2RAY_LOG_FILE "$V2RAY_LOG_FILE" \
      --arg V2RAY_ERROR_LOG_FILE "$V2RAY_ERROR_LOG_FILE" \
      '{
        "log": {
          "access": $V2RAY_LOG_FILE,
          "error": $V2RAY_ERROR_LOG_FILE,
          "loglevel": "warning"
        },
        "inbounds": [],
        "outbounds": [
          {
            "protocol": "freedom",
            "settings": {}
          },
          {
            "protocol": "blackhole",
            "settings": {},
            "tag": "blocked"
          }
        ],
        "routing": {
          "rules": [
            {
              "type": "field",
              "ip": ["geoip:private"],
              "outboundTag": "blocked"
            }
          ]
        }
      }' > "$V2RAY_CONFIG_FILE" || { echo -e "${RED}创建基础 config.json 失败。${NC}"; exit 1; }


    # Inbound specific settings
    client_settings=$(jq -n \
        --arg uuid "$uuid" \
        --arg protocol "$protocol" \
        '{id: $uuid, level: 0, email: "user@v2ray"}' \
    )
    # VLESS doesn't use alterId, VMess does (though 0 is common now)
    if [[ "$protocol" == "vmess" ]]; then
        client_settings=$(echo "$client_settings" | jq --argjson alter_id "$alter_id" '. + {alterId: $alter_id}')
    elif [[ "$protocol" == "vless" ]]; then
         client_settings=$(echo "$client_settings" | jq '. + {encryption: "none"}') # VLESS requires encryption setting
    fi

    # Stream settings based on transport
    case "$transport" in
        "tcp")
            stream_settings=$(jq -n '{network: "tcp", security: "none", tcpSettings: {header: {type: "none"}}}')
            ;;
        "mkcp")
            stream_settings=$(jq -n \
                --arg mkcp_header "$mkcp_header" \
                --arg mkcp_seed "$mkcp_seed" \
                '{
                    network: "kcp",
                    security: "none",
                    kcpSettings: {
                        mtu: 1350, tti: 50, uplinkCapacity: 100, downlinkCapacity: 100,
                        congestion: true, readBufferSize: 2, writeBufferSize: 2,
                        header: { type: $mkcp_header },
                        seed: $mkcp_seed
                    }
                }')
            ;;
        "ws")
             stream_settings=$(jq -n \
                --arg ws_path "$ws_path" \
                '{network: "ws", security: "none", wsSettings: {path: $ws_path, headers: {Host: $ENV.domain}}}' \
                | jq --arg domain "${domain:-localhost}" envsubst) # Substitute domain if available
            ;;
        "quic")
            stream_settings=$(jq -n \
                --arg quic_security "$quic_security" \
                --arg quic_key "$quic_key" \
                --arg quic_header "$quic_header" \
                '{
                    network: "quic",
                    security: "none", # TLS handled in tlsSettings below
                    quicSettings: {
                        security: $quic_security,
                        key: $quic_key,
                        header: { type: $quic_header }
                    }
                }')
             # QUIC requires TLS
             if [[ "$use_tls" != "true" ]]; then
                echo -e "${RED}错误: QUIC 传输协议必须启用 TLS。${NC}"
                exit 1
             fi
            ;;
        "grpc")
            stream_settings=$(jq -n \
                --arg grpc_servicename "$grpc_servicename" \
                '{network: "grpc", security: "none", grpcSettings: {serviceName: $grpc_servicename}}')
            # gRPC requires TLS
             if [[ "$use_tls" != "true" ]]; then
                echo -e "${RED}错误: gRPC 传输协议必须启用 TLS。${NC}"
                exit 1
             fi
            ;;
    esac

    # Add TLS settings if enabled
    if [[ "$use_tls" == "true" ]]; then
        local cert_file="/etc/letsencrypt/live/${domain}/fullchain.pem"
        local key_file="/etc/letsencrypt/live/${domain}/privkey.pem"
        stream_settings=$(echo "$stream_settings" | jq \
            --arg domain "$domain" \
            --arg cert_file "$cert_file" \
            --arg key_file "$key_file" \
            '. + {
                security: "tls",
                tlsSettings: {
                    serverName: $domain,
                    alpn: ["h2", "http/1.1"],
                    certificates: [
                        {
                            certificateFile: $cert_file,
                            keyFile: $key_file
                        }
                    ]
                }
            }')
    fi


    # Combine settings into the final inbound object
    inbound_settings=$(jq -n \
      --argjson port "$V2RAY_INTERNAL_PORT" \
      --arg protocol "$protocol" \
      --argjson client_settings "$client_settings" \
      --argjson stream_settings "$stream_settings" \
      '{
        port: $port,
        listen: "127.0.0.1", # Listen on localhost for security, Nginx/firewall handles external access
        protocol: $protocol,
        settings: {
          clients: [$client_settings],
          disableInsecureEncryption: false # Set true if only using AEAD ciphers for VMess
        },
        streamSettings: $stream_settings,
        sniffing: {
          enabled: true,
          destOverride: ["http", "tls"]
        }
      }')

      # If not using TLS or not using WS, listen on 0.0.0.0
       if [[ "$use_tls" == "false" || ( "$transport" != "ws" && "$use_tls" == "true") ]]; then
           inbound_settings=$(echo "$inbound_settings" | jq '.listen = "0.0.0.0"')
           # Update port to external port if not using WS+TLS
           if [[ "$transport" != "ws" || "$use_tls" == "false" ]]; then
                 inbound_settings=$(echo "$inbound_settings" | jq --argjson port "$port" '.port = $port')
           fi
       fi


    # Add the inbound to the main config file
    jq --argjson inbound "$inbound_settings" '.inbounds += [$inbound]' "$V2RAY_CONFIG_FILE" > temp.json && mv temp.json "$V2RAY_CONFIG_FILE"

    # --- Save state for later use (show_config, uninstall) ---
     echo "PROTOCOL=$protocol" > "$STATE_FILE"
     echo "PORT=$port" >> "$STATE_FILE"
     echo "INTERNAL_PORT=$V2RAY_INTERNAL_PORT" >> "$STATE_FILE"
     echo "UUID=$uuid" >> "$STATE_FILE"
     echo "TRANSPORT=$transport" >> "$STATE_FILE"
     echo "USE_TLS=$use_tls" >> "$STATE_FILE"
     echo "DOMAIN=$domain" >> "$STATE_FILE"
     echo "WS_PATH=$ws_path" >> "$STATE_FILE"
     echo "MKCP_HEADER=$mkcp_header" >> "$STATE_FILE"
     echo "MKCP_SEED=$mkcp_seed" >> "$STATE_FILE"
     echo "QUIC_SECURITY=$quic_security" >> "$STATE_FILE"
     echo "QUIC_KEY=$quic_key" >> "$STATE_FILE"
     echo "QUIC_HEADER=$quic_header" >> "$STATE_FILE"
     echo "GRPC_SERVICENAME=$grpc_servicename" >> "$STATE_FILE"
     echo "ALTER_ID=$alter_id" >> "$STATE_FILE" # For VMess link generation

    echo -e "${GREEN}V2Ray 配置文件生成完毕: ${V2RAY_CONFIG_FILE}${NC}"
    echo "--- V2Ray config.json ---"
    jq '.' "$V2RAY_CONFIG_FILE"
    echo "-------------------------"

    # --- Configure Nginx if using WS+TLS ---
    if [[ "$transport" == "ws" && "$use_tls" == "true" ]]; then
        configure_nginx "$domain" "$port" "$V2RAY_INTERNAL_PORT" "$ws_path"
    fi

    # --- Install Certbot and get certificate ---
    if [[ "$use_tls" == "true" ]]; then
        install_and_configure_certbot "$domain" "$transport"
    fi
}

configure_nginx() {
    local domain=$1
    local listen_port=$2
    local v2ray_internal_port=$3
    local ws_path=$4
    local nginx_conf_path="${NGINX_CONFIG_DIR}/${NGINX_V2RAY_CONF}"

    echo -e "${BLUE}正在配置 Nginx...${NC}"

    # Create download directory
    mkdir -p "$DOWNLOAD_DIR"
    chown -R www-data:www-data "$DOWNLOAD_DIR" # Nginx usually runs as www-data
    chmod -R 755 "$DOWNLOAD_DIR"
    # Create a dummy index file for testing
    echo "<html><body><h1>Download Area</h1><p>Place files in ${DOWNLOAD_DIR} to serve them.</p></body></html>" > "${DOWNLOAD_DIR}/index.html"
    chown www-data:www-data "${DOWNLOAD_DIR}/index.html"

    # Basic HTTP server block for Certbot challenge and redirection
     cat > "$nginx_conf_path" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    # Let's Encrypt ACME challenge
    location ~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/html; # Default Certbot webroot
    }

    location / {
        # Redirect all HTTP traffic to HTTPS
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen ${listen_port} ssl http2;
    listen [::]:${listen_port} ssl http2;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem; # Managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem; # Managed by Certbot
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    # ssl_stapling on; # Enable after obtaining cert
    # ssl_stapling_verify on; # Enable after obtaining cert
    # resolver 8.8.8.8 8.8.4.4 valid=300s; # Optional: Specify resolver for stapling
    # resolver_timeout 5s; # Optional

    # HSTS (optional, but recommended) - Certbot can add this too
    # add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";

    # Root path - Reverse proxy to Honda
    location / {
        proxy_pass https://www.honda.com; # Use HTTPS for backend if possible
        proxy_ssl_server_name on;      # Important for SNI
        proxy_set_header Host www.honda.com; # Set correct Host header
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        proxy_buffering off; # Often better for proxying dynamic sites
        # Set a User-Agent if needed, some sites block default Nginx/proxy UAs
        # proxy_set_header User-Agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36";
    }

    # V2Ray WebSocket path
    location ${ws_path} {
        if (\$http_upgrade != "websocket") { # Return 404 if not a WebSocket upgrade request
             return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${v2ray_internal_port}; # Pass to V2Ray internal port
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host; # Pass the original host header
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # File Server Path
    location /file/ {
        alias ${DOWNLOAD_DIR}/; # Note the trailing slash on both location and alias
        autoindex on;          # Enable directory listing
        autoindex_exact_size off; # Show human-readable sizes
        autoindex_localtime on;  # Show local time
    }
}
EOF

    # Enable the Nginx site
    ln -sf "${nginx_conf_path}" "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}"

    # Test Nginx configuration
    echo -e "${BLUE}正在测试 Nginx 配置...${NC}"
    nginx -t
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: Nginx 配置测试失败。请检查 ${nginx_conf_path}${NC}"
        # Attempt to disable the faulty config
        rm -f "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}"
        exit 1
    fi

    echo -e "${GREEN}Nginx 配置成功。${NC}"
    # Nginx will be restarted/reloaded after certbot or at the end.
}


install_and_configure_certbot() {
    local domain=$1
    local transport=$2 # Needed to know if nginx plugin should be used

    echo -e "${BLUE}正在配置 Certbot 并申请证书...${NC}"

    # Ensure /var/www/html exists for webroot challenge fallback
    mkdir -p /var/www/html
    chown www-data:www-data /var/www/html

    # Stop Nginx temporarily ONLY if using standalone for QUIC/gRPC, or if Nginx isn't running yet
    local nginx_was_stopped=0
    if [[ "$transport" == "quic" || "$transport" == "grpc" ]]; then
        if systemctl is-active --quiet nginx; then
            echo -e "${YELLOW}暂时停止 Nginx 以便 Certbot 使用端口 80...${NC}"
            systemctl stop nginx
            nginx_was_stopped=1
            sleep 2 # Give it a moment to release the port
        fi
        # Use standalone for QUIC/gRPC as Nginx isn't necessarily configured for TLS yet
         certbot certonly --standalone --agree-tos --no-eff-email --email "$CERT_EMAIL" -d "$domain" --preferred-challenges http || {
            echo -e "${RED}错误: Certbot 证书申请失败 (standalone)。请确保域名解析正确，并且端口 80 未被占用。${NC}"
            if [ "$nginx_was_stopped" -eq 1 ]; then systemctl start nginx; fi
            exit 1
        }
         if [ "$nginx_was_stopped" -eq 1 ]; then
             echo -e "${BLUE}正在重新启动 Nginx...${NC}"
            systemctl start nginx
         fi
    elif [[ "$transport" == "ws" ]]; then
        # For WS, Nginx is configured, use the nginx plugin
        echo -e "${BLUE}Nginx 已经配置，尝试重新加载以应用 HTTP 配置...${NC}"
        systemctl reload nginx || systemctl start nginx # Ensure Nginx is running for the plugin
        sleep 2

        # Use Nginx plugin
        certbot --nginx --agree-tos --no-eff-email --email "$CERT_EMAIL" -d "$domain" \
                --redirect --hsts --staple-ocsp || {
             echo -e "${RED}错误: Certbot 证书申请失败 (nginx plugin)。请确保域名解析正确，并且 Nginx 配置 (${NGINX_CONFIG_DIR}/${NGINX_V2RAY_CONF}) 正确。${NC}"
             exit 1
        }
         # Certbot nginx plugin modifies the config, test it again
         echo -e "${BLUE}Certbot 已修改 Nginx 配置，再次测试...${NC}"
         nginx -t || {
             echo -e "${RED}错误: Certbot 修改后的 Nginx 配置测试失败。${NC}"
             # Consider reverting changes or providing manual instructions
             exit 1
         }
         echo -e "${BLUE}重新加载 Nginx 以应用 SSL 证书...${NC}"
         systemctl reload nginx
    else
         echo -e "${RED}内部错误: 不应在没有 TLS 的情况下调用 Certbot。${NC}"
         exit 1
    fi

    echo -e "${GREEN}证书申请成功并配置完成！${NC}"

    # --- Set up automatic renewal cron job ---
    echo -e "${BLUE}正在设置证书自动续期任务...${NC}"
    # Certbot package usually adds a systemd timer or cron job in /etc/cron.d/certbot
    # We add a specific one to run every 2 months for this script's purpose
    # Remove existing custom job first to avoid duplicates
    (crontab -l | grep -v "/usr/bin/certbot renew" | grep -v "certbot_renew_script") 2>/dev/null | crontab -

    # Add new job to run on the 1st day of every second month at 3:30 AM
    (crontab -l 2>/dev/null; echo "30 3 1 */2 * /usr/bin/certbot renew --quiet --deploy-hook 'systemctl reload nginx && systemctl restart v2ray' # certbot_renew_script") | crontab -

    echo -e "${GREEN}证书自动续期任务已设置 (每2个月尝试一次)。${NC}"
}

install_v2ray_service() {
    echo -e "${BLUE}正在创建并启用 V2Ray systemd 服务...${NC}"
    cat > "$V2RAY_SERVICE_FILE" <<EOF
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${V2RAY_INSTALL_DIR}/v2ray run -config ${V2RAY_CONFIG_FILE}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable v2ray || { echo -e "${RED}启用 V2Ray 服务失败。${NC}"; exit 1; }
    echo -e "${GREEN}V2Ray systemd 服务创建并启用成功。${NC}"
}

start_services() {
    echo -e "${BLUE}正在启动 V2Ray 服务...${NC}"
    systemctl restart v2ray
    sleep 2 # Wait a bit for service to start

    if ! systemctl is-active --quiet v2ray; then
        echo -e "${RED}错误: V2Ray 服务启动失败。请运行 'journalctl -u v2ray' 查看日志。${NC}"
        # Try showing last few log lines
        tail -n 10 "$V2RAY_ERROR_LOG_FILE"
        exit 1
    else
        echo -e "${GREEN}V2Ray 服务启动成功。${NC}"
    fi

    # Start/Reload Nginx if it was configured
    if [ -f "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}" ] || \
       ([[ -f "$STATE_FILE" ]] && grep -q 'TRANSPORT=ws' "$STATE_FILE" && grep -q 'USE_TLS=true' "$STATE_FILE"); then
        echo -e "${BLUE}正在启动/重新加载 Nginx 服务...${NC}"
        systemctl reload nginx || systemctl start nginx
        sleep 1
        if ! systemctl is-active --quiet nginx; then
             echo -e "${RED}错误: Nginx 服务启动/重新加载失败。请运行 'journalctl -u nginx' 查看日志。${NC}"
             # Don't exit, V2Ray might still work depending on config
        else
             echo -e "${GREEN}Nginx 服务启动/重新加载成功。${NC}"
        fi
    fi
}

stop_services() {
    echo -e "${BLUE}正在停止 V2Ray 服务...${NC}"
    systemctl stop v2ray
    if [ -f "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}" ]; then
        echo -e "${BLUE}正在停止 Nginx 服务...${NC}"
        systemctl stop nginx
    fi
    echo -e "${GREEN}服务已停止。${NC}"
}

uninstall_v2ray() {
    echo -e "${RED}警告: 这将彻底删除 V2Ray, Nginx 配置, Certbot 证书 (如果相关) 和 ${DOWNLOAD_DIR} !${NC}"
    read -p "确定要卸载吗? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "卸载已取消。"
        exit 0
    fi

    stop_services

    echo -e "${BLUE}正在禁用 V2Ray 服务...${NC}"
    systemctl disable v2ray 2>/dev/null
    rm -f "$V2RAY_SERVICE_FILE"
    systemctl daemon-reload

    echo -e "${BLUE}正在删除 V2Ray 文件...${NC}"
    rm -rf "$V2RAY_INSTALL_DIR"
    rm -rf "$V2RAY_CONFIG_DIR" # Also removes state file
    rm -rf /var/log/v2ray

    # Uninstall Nginx config if it exists
    if [ -f "${NGINX_CONFIG_DIR}/${NGINX_V2RAY_CONF}" ]; then
        echo -e "${BLUE}正在删除 Nginx 配置文件...${NC}"
        rm -f "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}"
        rm -f "${NGINX_CONFIG_DIR}/${NGINX_V2RAY_CONF}"
        echo -e "${BLUE}尝试重新加载 Nginx (如果它还在运行)...${NC}"
        nginx -t && systemctl reload nginx || echo -e "${YELLOW}Nginx 重载失败或未安装，已跳过。${NC}"
    fi

    # Uninstall Certbot certificate and renewal config
    if [[ -f "$STATE_FILE" ]] && grep -q 'USE_TLS=true' "$STATE_FILE"; then
        # Source state file to get domain
        source "$STATE_FILE"
        if [[ -n "$DOMAIN" ]]; then
             echo -e "${BLUE}正在删除 ${DOMAIN} 的 Certbot 证书和续订配置...${NC}"
             certbot delete --cert-name "$DOMAIN" --non-interactive || echo -e "${YELLOW}Certbot 删除证书失败，可能已被手动删除。${NC}"
        fi
        # Remove custom cron job
         (crontab -l | grep -v "certbot_renew_script") 2>/dev/null | crontab -
    fi

     # Remove download directory
     if [ -d "$DOWNLOAD_DIR" ]; then
         echo -e "${BLUE}正在删除下载目录 ${DOWNLOAD_DIR}...${NC}"
         rm -rf "$DOWNLOAD_DIR"
     fi

    # Remove state file explicitly in case V2RAY_CONFIG_DIR removal failed
    rm -f "$STATE_FILE"

    echo -e "${GREEN}V2Ray 卸载完成。${NC}"
    read -p "是否需要移除安装的依赖项 (nginx certbot jq etc.)? (y/N): " remove_deps
    if [[ "$remove_deps" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}正在卸载依赖项...${NC}"
        # Stopping nginx again just in case it was restarted by something
        systemctl stop nginx 2>/dev/null
        apt remove --purge -y nginx python3-certbot-nginx certbot curl wget unzip socat jq net-tools
        apt autoremove -y
        echo -e "${GREEN}依赖项卸载完成。${NC}"
    fi
}

show_config() {
    if [ ! -f "$STATE_FILE" ]; then
        echo -e "${RED}错误: 未找到安装状态文件 (${STATE_FILE})。请先安装。${NC}"
        return 1
    fi

    source "$STATE_FILE" # Load saved variables

    local address="${DOMAIN:-$(curl -s ip.sb || hostname -I | awk '{print $1}')}" # Use domain if TLS, else public IP
    local port="$PORT"
    local uuid="$UUID"
    local protocol="$PROTOCOL"
    local transport="$TRANSPORT"
    local path="$WS_PATH"
    local host="${DOMAIN:-}" # Host header for WS/gRPC
    local tls_status="${USE_TLS:-false}"
    local network="$TRANSPORT" # Alias for clarity in links
    local type="none" # Default header type for VMess URL if not mKCP
    local sni="${DOMAIN:-}" # SNI for TLS

    echo -e "\n--- ${GREEN}当前 V2Ray 配置信息${NC} ---"
    echo -e "协议 (Protocol) : ${BLUE}${protocol}${NC}"
    echo -e "地址 (Address)  : ${BLUE}${address}${NC}"
    echo -e "端口 (Port)     : ${BLUE}${port}${NC}"
    echo -e "用户 ID (UUID)  : ${BLUE}${uuid}${NC}"
    echo -e "传输方式 (Network): ${BLUE}${transport}${NC}"

    if [[ "$protocol" == "vmess" ]]; then
         echo -e "AlterId         : ${BLUE}${ALTER_ID}${NC}"
    fi

    if [[ "$transport" == "ws" ]]; then
        network="ws"
        echo -e "路径 (Path)     : ${BLUE}${path}${NC}"
        if [[ "$tls_status" == "true" ]]; then
             echo -e "Host (伪装域名): ${BLUE}${host}${NC}"
        fi
    elif [[ "$transport" == "mkcp" ]]; then
        network="kcp"
        type="$MKCP_HEADER" # Use mKCP header type
        echo -e "mKCP 伪装 (Type): ${BLUE}${MKCP_HEADER}${NC}"
        echo -e "mKCP Seed       : ${BLUE}${MKCP_SEED}${NC}"
    elif [[ "$transport" == "quic" ]]; then
        network="quic"
        type="$QUIC_HEADER"
         echo -e "QUIC 加密 (Sec) : ${BLUE}${QUIC_SECURITY}${NC}"
         echo -e "QUIC 密钥 (Key) : ${BLUE}${QUIC_KEY}${NC}"
         echo -e "QUIC 伪装 (Hdr) : ${BLUE}${QUIC_HEADER}${NC}"
    elif [[ "$transport" == "grpc" ]]; then
        network="grpc"
        echo -e "gRPC 服务名(SN) : ${BLUE}${GRPC_SERVICENAME}${NC}"
        path="$GRPC_SERVICENAME" # Use service name as "path" in VLess URL
    fi

     if [[ "$tls_status" == "true" ]]; then
        echo -e "TLS             : ${GREEN}启用${NC}"
        echo -e "SNI / Host      : ${BLUE}${sni}${NC}"
        if [[ "$transport" == "ws" || "$transport" == "grpc" || "$transport" == "quic" ]]; then
             security="tls"
        fi
     else
        echo -e "TLS             : ${RED}禁用${NC}"
        security="none"
     fi

    # --- Generate Share Links ---
    echo -e "\n--- ${GREEN}客户端配置链接${NC} ---"

    if [[ "$protocol" == "vmess" ]]; then
        # Base VMess JSON object
        local vmess_json=$(jq -n \
          --arg address "$address" \
          --argjson port "$port" \
          --arg uuid "$uuid" \
          --argjson aid "$ALTER_ID" \
          --arg network "$network" \
          --arg type "$type" \
          --arg host "$host" \
          --arg path "$path" \
          --arg security "$security" \
          --arg sni "$sni" \
          '{v: "2", ps: "V2Ray", add: $address, port: $port, id: $uuid, aid: $aid, net: $network, type: $type, host: $host, path: $path, tls: $security, sni: $sni}'
        )
        # Remove empty fields for cleaner output
        vmess_json=$(echo "$vmess_json" | jq 'del(select(. == "" or . == null))')

        local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"
        echo -e "${YELLOW}VMess 链接:${NC}"
        echo -e "${GREEN}${vmess_link}${NC}"

    elif [[ "$protocol" == "vless" ]]; then
        # Base VLess URL structure: vless://uuid@address:port?parameters
        local params=""
        params+="&type=${network}" # type = network (tcp, kcp, ws, quic, grpc)

        if [[ "$network" == "kcp" ]]; then
            params+="&headerType=${MKCP_HEADER}"
            params+="&seed=${MKCP_SEED}"
        elif [[ "$network" == "ws" ]]; then
            params+="&path=$(rawurlencode "$path")"
            if [[ "$tls_status" == "true" ]]; then
                 params+="&host=$(rawurlencode "$host")"
            fi
        elif [[ "$network" == "quic" ]]; then
             params+="&quicSecurity=${QUIC_SECURITY}"
             params+="&key=${QUIC_KEY}"
             params+="&headerType=${QUIC_HEADER}"
        elif [[ "$network" == "grpc" ]]; then
             params+="&serviceName=$(rawurlencode "$GRPC_SERVICENAME")"
             # mode=multi for newer clients? Usually implied.
        fi

        if [[ "$tls_status" == "true" ]]; then
             params+="&security=tls"
             params+="&sni=$(rawurlencode "$sni")"
             # Flow can be added if needed, e.g., &flow=xtls-rprx-vision
        else
             params+="&security=none"
        fi

        local vless_link="vless://${uuid}@${address}:${port}?${params#&}" # Remove leading &
        echo -e "${YELLOW}VLess 链接:${NC}"
        echo -e "${GREEN}${vless_link}${NC}"
    fi
    echo -e "\n${YELLOW}注意:${NC} 请根据您的客户端支持情况选择合适的链接。某些参数（如 mKCP Seed, QUIC Key）可能需要手动填写。"

     # Show Nginx file server URL if applicable
     if [[ "$transport" == "ws" && "$tls_status" == "true" && -n "$domain" ]]; then
         echo -e "\n--- ${GREEN}Nginx 文件服务器${NC} ---"
         echo -e "访问地址: ${BLUE}https://${domain}/file/${NC}"
         echo -e "文件存放目录: ${BLUE}${DOWNLOAD_DIR}${NC}"
     fi
}

# Helper function for URL encoding (needed for VLESS links)
rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"
}


# --- Main Menu ---
main_menu() {
    clear
    echo "=============================================="
    echo " V2Ray (VMess/VLess) 管理脚本 (Debian)"
    echo "=============================================="
    echo -e " ${GREEN}1. 安装 V2Ray${NC}"
    echo -e " ${YELLOW}2. 修改 V2Ray 配置 (重新安装)${NC}"
    echo -e " ${RED}3. 卸载 V2Ray${NC}"
    echo -e " ${BLUE}4. 查看 V2Ray 配置 / URL${NC}"
    echo " ------------------------------------------"
    echo -e " 5. 启动 V2Ray 服务"
    echo -e " 6. 停止 V2Ray 服务"
    echo -e " 7. 重启 V2Ray 服务"
    echo -e " 8. 查看 V2Ray 服务状态"
    echo -e " 9. 查看 V2Ray 错误日志"
    echo " ------------------------------------------"
    echo -e " 0. 退出脚本"
    echo "=============================================="

    # Check Status
    if systemctl is-active --quiet v2ray; then
        echo -e " V2Ray 状态: ${GREEN}运行中${NC}"
    else
        echo -e " V2Ray 状态: ${RED}未运行${NC}"
    fi
     if [ -f "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}" ]; then
         if systemctl is-active --quiet nginx; then
             echo -e " Nginx 状态: ${GREEN}运行中 (代理已配置)${NC}"
         else
              echo -e " Nginx 状态: ${RED}未运行 (代理已配置)${NC}"
         fi
     fi
    echo "=============================================="

    read -p "请输入选项 [0-9]: " choice

    case $choice in
        1)
            install_v2ray_main
            ;;
        2)
            echo -e "${YELLOW}修改配置将引导您完成完整的安装流程以覆盖现有设置。${NC}"
            read -p "确定要继续吗? (y/N): " confirm_modify
            if [[ "$confirm_modify" =~ ^[Yy]$ ]]; then
                 install_v2ray_main # Re-run install process
            else
                echo "修改已取消。"
            fi
            ;;
        3)
            uninstall_v2ray
            ;;
        4)
            show_config
            ;;
        5)
            systemctl start v2ray && echo -e "${GREEN}V2Ray 服务已启动。${NC}" || echo -e "${RED}启动失败。${NC}"
            ;;
        6)
            systemctl stop v2ray && echo -e "${GREEN}V2Ray 服务已停止。${NC}" || echo -e "${RED}停止失败。${NC}"
            ;;
        7)
             systemctl restart v2ray && echo -e "${GREEN}V2Ray 服务已重启。${NC}" || echo -e "${RED}重启失败。${NC}"
            ;;
        8)
            systemctl status v2ray
            ;;
        9)
            echo "--- V2Ray Error Log (${V2RAY_ERROR_LOG_FILE}) ---"
            tail -n 50 "$V2RAY_ERROR_LOG_FILE"
            echo "----------------------------------------"
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 0 到 9 之间的数字。${NC}"
            ;;
    esac
}

# --- Installation Workflow ---
install_v2ray_main() {
    check_root
    install_dependencies

    echo "请选择 V2Ray 核心协议:"
    select proto_choice in "VMess" "VLess"; do
        if [[ -n "$proto_choice" ]]; then
            v2ray_protocol=$(echo "$proto_choice" | tr '[:upper:]' '[:lower:]')
            break
        else
            echo "无效选择，请重试。"
        fi
    done

    echo "请选择传输协议:"
    select transport_choice in "TCP" "mKCP" "WebSocket" "QUIC" "gRPC"; do
         if [[ -n "$transport_choice" ]]; then
            v2ray_transport=$(echo "$transport_choice" | tr '[:upper:]' '[:lower:]')
            break
        else
            echo "无效选择，请重试。"
        fi
    done

    # Stop existing services before potentially overwriting configs
    if systemctl is-active --quiet v2ray; then
         echo -e "${YELLOW}检测到正在运行的 V2Ray 服务，将停止它以进行安装/修改...${NC}"
         systemctl stop v2ray
    fi
     if [ -f "${NGINX_ENABLED_DIR}/${NGINX_V2RAY_CONF}" ] && systemctl is-active --quiet nginx; then
         echo -e "${YELLOW}检测到正在运行的 Nginx 服务 (与 V2Ray 相关)，将停止它以进行安装/修改...${NC}"
         systemctl stop nginx
     fi


    download_and_extract_v2ray
    # Pass dummy values for port/domain initially, they will be prompted inside
    configure_v2ray "$v2ray_protocol" "0" "$v2ray_transport" ""
    install_v2ray_service
    start_services # This handles V2Ray and Nginx start/reload as needed

    echo -e "${GREEN}V2Ray 安装/配置完成！${NC}"
    show_config # Display config after installation
}


# --- Script Entry Point ---
check_root
while true; do
    main_menu
    read -p "按 Enter 键返回主菜单..." enter_key
done
