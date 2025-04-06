#!/bin/bash

# V2Ray Variables
V2RAY_DOWNLOAD_URL="https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip"
V2RAY_INSTALL_PATH="/usr/local/bin/v2ray"
V2RAY_CONFIG_PATH="/etc/v2ray"
V2RAY_SERVICE_FILE="/etc/systemd/system/v2ray.service"
V2RAY_CONFIG_FILE="${V2RAY_CONFIG_PATH}/config.json"
V2RAY_ACCESS_LOG="/var/log/v2ray/access.log"
V2RAY_ERROR_LOG="/var/log/v2ray/error.log"

# Nginx Variables
NGINX_CONFIG_FILE="/etc/nginx/conf.d/v2ray.conf"
WEB_ROOT="/usr/share/nginx/html" # Default Nginx root
DOWNLOAD_DIR="/usr/download"

# Certbot Variables
CERT_EMAIL="lineair069@gmail.com"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# Check Root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以 root 身份运行！${PLAIN}"
        exit 1
    fi
}

# Check OS (Debian based)
check_os() {
    if ! grep -qi "debian\|ubuntu" /etc/os-release; then
        echo -e "${RED}错误: 此脚本仅支持 Debian 或 Ubuntu 系统！${PLAIN}"
        exit 1
    fi
}

# Install Dependencies
install_dependencies() {
    echo -e "${YELLOW}检查并安装依赖...${PLAIN}"
    apt update
    apt install -y curl unzip nginx certbot python3-certbot-nginx jq qrencode coreutils
    if ! command -v nginx &> /dev/null || ! command -v certbot &> /dev/null || ! command -v jq &> /dev/null; then
       echo -e "${RED}错误: 依赖安装失败，请检查网络或手动安装！${PLAIN}"
       exit 1
    fi
     # Ensure log directory exists
    mkdir -p /var/log/v2ray
    chown nobody:nogroup /var/log/v2ray # Or appropriate user for V2Ray if not using root
}

# Download and Install V2Ray Core
install_v2ray_core() {
    echo -e "${YELLOW}下载并安装 V2Ray Core...${PLAIN}"
    mkdir -p ${V2RAY_INSTALL_PATH}
    mkdir -p ${V2RAY_CONFIG_PATH}
    
    TEMP_DIR=$(mktemp -d)
    cd ${TEMP_DIR}

    if ! curl -L -o v2ray.zip "${V2RAY_DOWNLOAD_URL}"; then
        echo -e "${RED}错误: 下载 V2Ray 失败！请检查 URL 或网络。${PLAIN}"
        rm -rf ${TEMP_DIR}
        exit 1
    fi

    if ! unzip -o v2ray.zip -d ${V2RAY_INSTALL_PATH}; then
       echo -e "${RED}错误: 解压 V2Ray 失败！${PLAIN}"
       rm -rf ${TEMP_DIR}
       exit 1
    fi

    chmod +x ${V2RAY_INSTALL_PATH}/v2ray
    chmod +x ${V2RAY_INSTALL_PATH}/v2ctl

    # Move dat files
    mv ${V2RAY_INSTALL_PATH}/geoip.dat ${V2RAY_INSTALL_PATH}/geosite.dat ${V2RAY_CONFIG_PATH}/

    rm -rf ${TEMP_DIR}
    echo -e "${GREEN}V2Ray Core 安装成功！${PLAIN}"
}

# Create V2Ray Systemd Service File
create_service_file() {
    echo -e "${YELLOW}创建 V2Ray systemd 服务文件...${PLAIN}"
    cat > ${V2RAY_SERVICE_FILE} <<EOF
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
User=root # Or change to a dedicated user if needed
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${V2RAY_INSTALL_PATH}/v2ray run -config ${V2RAY_CONFIG_FILE}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable v2ray
    echo -e "${GREEN}V2Ray systemd 服务创建成功！${PLAIN}"
}

# Request Let's Encrypt Certificate
request_certificate() {
    local domain=$1
    echo -e "${YELLOW}为域名 ${domain} 申请 Let's Encrypt 证书...${PLAIN}"
    # Stop Nginx temporarily if running on port 80 to allow standalone challenge
    systemctl stop nginx &> /dev/null 
    # Ensure Nginx is not running on 80 for standalone challenge if needed, certbot --nginx should handle this
    # Alternatively, use webroot or nginx plugin
    
    # Using nginx plugin is generally more robust if nginx is already set up
    # Make sure default nginx config exists or create a temporary one for the challenge
    if ! systemctl is-active --quiet nginx; then
      systemctl start nginx # Start nginx if not running for the plugin
    fi
    sleep 2 # Give nginx time to start

    certbot certonly --nginx --agree-tos --no-eff-email --email ${CERT_EMAIL} -d ${domain} --non-interactive
    
    # Use standalone if nginx plugin fails or if nginx is not preferred for challenges
    # certbot certonly --standalone --agree-tos --no-eff-email --email ${CERT_EMAIL} -d ${domain} --non-interactive

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}错误: 证书申请失败！请检查：${PLAIN}"
        echo -e "${RED}1. 域名 (${domain}) 是否正确解析到本服务器 IP。${PLAIN}"
        echo -e "${RED}2. 服务器 80 端口是否被占用或防火墙拦截。${PLAIN}"
        echo -e "${RED}3. Nginx 是否配置正确（如果使用 Nginx 插件）。${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}证书申请成功！${PLAIN}"
    # No need to explicitly stop nginx here as certbot --nginx handles it or it was started temporarily
}

# Configure Nginx for WS+TLS
configure_nginx_ws_tls() {
    local domain=$1
    local v2ray_port=$2 # The port V2Ray listens on locally
    local ws_path=$3

    echo -e "${YELLOW}配置 Nginx (WS+TLS)...${PLAIN}"

    # Create download directory
    mkdir -p ${DOWNLOAD_DIR}
    chown www-data:www-data ${DOWNLOAD_DIR} # Set appropriate permissions for Nginx

    local ssl_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local ssl_key="/etc/letsencrypt/live/${domain}/privkey.pem"

    cat > ${NGINX_CONFIG_FILE} <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    # Redirect HTTP to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
    # For Let's Encrypt renewal verification
    location ~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/html; # Or the appropriate webroot used by Certbot
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate ${ssl_cert};
    ssl_certificate_key ${ssl_key};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # V2Ray WebSocket traffic
    location = ${ws_path} {
        if (\$http_upgrade != "websocket") {
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${v2ray_port}; # V2Ray listens on this local port
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        # Show real IP in V2Ray access log
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    # File Server
    location /file/ {
        alias ${DOWNLOAD_DIR}/;
        autoindex on; # Optional: directory listing
        # Add more security/options here if needed (e.g., auth_basic)
    }
    
    # Fake Website (Proxy to Honda)
    location / {
        proxy_pass https://www.honda.com/;
        proxy_ssl_server_name on; # Important for SNI
        proxy_set_header Host www.honda.com;
        proxy_set_header Accept-Encoding ""; # Avoid double compression issues
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        sub_filter_types *; # Apply sub_filter to all content types
        sub_filter "www.honda.com" \$host; # Replace honda domain with our domain in response body (basic attempt)
        sub_filter_once off;
        proxy_redirect ~^https://www.honda.com/(.*)$ https://\$host/\$1; # Redirect headers
    }
}
EOF

    if ! nginx -t; then
        echo -e "${RED}错误: Nginx 配置测试失败！请检查 ${NGINX_CONFIG_FILE} ${PLAIN}"
        # Optionally show the error: nginx -t
        exit 1
    fi

    systemctl reload nginx
    echo -e "${GREEN}Nginx 配置成功！${PLAIN}"
}


# Generate V2Ray Config
generate_v2ray_config() {
    local protocol choice_protocol
    local transport choice_transport
    local port domain uuid alterid ws_path mkcp_type mkcp_seed quic_security quic_key quic_header grpc_service_name
    local v2ray_listen_port # Port V2Ray listens on, might be different from external port if using Nginx

    echo "请选择 V2Ray 协议:"
    echo "1) VMess"
    echo "2) VLess"
    read -p "输入选择 [1]: " choice_protocol
    case "$choice_protocol" in
        2) protocol="vless" ;;
        *) protocol="vmess" ;;
    esac

    echo "请选择传输协议:"
    echo "1) TCP (原生)"
    echo "2) WebSocket (WS)"
    echo "3) WebSocket + TLS (WS+TLS, 需要 Nginx)"
    echo "4) mKCP"
    echo "5) QUIC + TLS"
    echo "6) gRPC + TLS"
    read -p "输入选择 [3]: " choice_transport

    read -p "请输入 V2Ray 监听端口 (例如 443, 8443): " port
    [[ -z "${port}" ]] && port=443 # Default port example

    uuid=$(cat /proc/sys/kernel/random/uuid)
    alterid=0 # Default AlterID for VMess

    # Common settings section
    cat > ${V2RAY_CONFIG_FILE} <<EOF
{
  "log": {
    "access": "${V2RAY_ACCESS_LOG}",
    "error": "${V2RAY_ERROR_LOG}",
    "loglevel": "warning" // Can be debug, info, warning, error, none
  },
  "inbounds": [
    {
      // Settings below will be replaced based on transport choice
    }
  ],
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
  // Policy, DNS, etc. can be added here if needed
}
EOF

    local inbound_config=""
    local stream_settings=""

    case "$choice_transport" in
        1) # TCP
            transport="tcp"
            v2ray_listen_port=${port}
            echo -e "${YELLOW}使用 TCP 传输.${PLAIN}"
            stream_settings='"network": "tcp"'
            ;;
        2) # WS
            transport="ws"
            v2ray_listen_port=${port}
            read -p "请输入 WebSocket 路径 (例如 /natsu) [/natsu]: " ws_path
            [[ -z "${ws_path}" ]] && ws_path="/natsu"
            echo -e "${YELLOW}使用 WebSocket 传输, 路径: ${ws_path}${PLAIN}"
            stream_settings=$(cat <<EOF
      "network": "ws",
      "security": "none",
      "wsSettings": {
        "path": "${ws_path}",
        "headers": {
          "Host": ""  // Leave empty or set domain if needed directly
        }
      }
EOF
)
            # Note: If behind CDN/proxy without TLS, domain might be needed in Host header
            read -p "请输入您的域名 (留空则监听 IP): " domain
            ;;
        3) # WS + TLS (Nginx)
            transport="ws"
            read -p "请输入您的域名 (必须): " domain
            if [[ -z "${domain}" ]]; then
                echo -e "${RED}错误: WS+TLS 必须提供域名！${PLAIN}"
                exit 1
            fi
             # V2Ray listens on a local port, Nginx handles external 443
            read -p "请输入 V2Ray 本地监听端口 (例如 10086) [10086]: " v2ray_listen_port
            [[ -z "${v2ray_listen_port}" ]] && v2ray_listen_port=10086

            read -p "请输入 WebSocket 路径 (例如 /natsu) [/natsu]: " ws_path
            [[ -z "${ws_path}" ]] && ws_path="/natsu"

            echo -e "${YELLOW}使用 WebSocket + TLS 传输, 域名: ${domain}, 路径: ${ws_path}, Nginx 监听 443, V2Ray 监听 ${v2ray_listen_port}${PLAIN}"
            
            request_certificate "${domain}"
            configure_nginx_ws_tls "${domain}" "${v2ray_listen_port}" "${ws_path}"

            stream_settings=$(cat <<EOF
      "network": "ws",
      "security": "none", // TLS is handled by Nginx
      "wsSettings": {
        "path": "${ws_path}"
      }
EOF
)
            port=443 # External port is 443
            ;;
        4) # mKCP
            transport="mkcp"
            v2ray_listen_port=${port}
            echo "请选择 mKCP 伪装类型:"
            echo "1) none (不伪装)"
            echo "2) srtp (视频通话)"
            echo "3) utp (BT 下载)"
            echo "4) wechat-video (微信视频通话)"
            echo "5) dtls1.2"
            echo "6) wireguard"
            read -p "输入选择 [1]: " choice_mkcp
            case "$choice_mkcp" in
                2) mkcp_type="srtp" ;;
                3) mkcp_type="utp" ;;
                4) mkcp_type="wechat-video" ;;
                5) mkcp_type="dtls" ;; # "dtls" maps to dtls1.2 in v2fly/v4; check if "dtls1.2" is valid identifier in JSON
                6) mkcp_type="wireguard" ;;
                *) mkcp_type="none" ;;
            esac
            mkcp_seed=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16) # Generate random seed
            echo -e "${YELLOW}使用 mKCP 传输, 伪装类型: ${mkcp_type}, Seed: ${mkcp_seed}${PLAIN}"
            stream_settings=$(cat <<EOF
      "network": "mkcp",
      "security": "none",
      "kcpSettings": {
        "mtu": 1350,
        "tti": 50,
        "uplinkCapacity": 5,
        "downlinkCapacity": 20,
        "congestion": false,
        "readBufferSize": 2,
        "writeBufferSize": 2,
        "header": {
          "type": "${mkcp_type}"
        },
        "seed": "${mkcp_seed}"
      }
EOF
)
            read -p "请输入您的域名或IP (用于客户端连接): " domain # Can be IP for mKCP
            ;;
        5) # QUIC + TLS
            transport="quic"
            v2ray_listen_port=${port}
            read -p "请输入您的域名 (必须): " domain
            if [[ -z "${domain}" ]]; then
                echo -e "${RED}错误: QUIC 必须提供域名！${PLAIN}"
                exit 1
            fi
            echo "请选择 QUIC 加密方式:"
            echo "1) none (不推荐)"
            echo "2) aes-128-gcm"
            echo "3) chacha20-poly1305"
            read -p "输入选择 [2]: " choice_quic_sec
            case "$choice_quic_sec" in
                1) quic_security="none" ;;
                3) quic_security="chacha20-poly1305" ;;
                *) quic_security="aes-128-gcm" ;;
            esac
            quic_key=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12) # Generate random key

            echo "请选择 QUIC 伪装类型 (Header Type):"
            echo "1) none"
            echo "2) srtp"
            echo "3) utp"
            echo "4) wechat-video"
            echo "5) dtls1.2"
            echo "6) wireguard"
            read -p "输入选择 [1]: " choice_quic_header
             case "$choice_quic_header" in
                2) quic_header="srtp" ;;
                3) quic_header="utp" ;;
                4) quic_header="wechat-video" ;;
                5) quic_header="dtls" ;;
                6) quic_header="wireguard" ;;
                *) quic_header="none" ;;
            esac

            echo -e "${YELLOW}使用 QUIC + TLS 传输, 域名: ${domain}, 加密: ${quic_security}, 伪装: ${quic_header}${PLAIN}"
            request_certificate "${domain}"

            stream_settings=$(cat <<EOF
      "network": "quic",
      "security": "tls",
      "quicSettings": {
        "security": "${quic_security}",
        "key": "${quic_key}",
        "header": {
          "type": "${quic_header}"
        }
      },
      "tlsSettings": {
        "serverName": "${domain}",
        "certificates": [
          {
            "certificateFile": "/etc/letsencrypt/live/${domain}/fullchain.pem",
            "keyFile": "/etc/letsencrypt/live/${domain}/privkey.pem"
          }
        ]
      }
EOF
)
            ;;
        6) # gRPC + TLS
            transport="grpc"
            v2ray_listen_port=${port}
            read -p "请输入您的域名 (必须): " domain
             if [[ -z "${domain}" ]]; then
                echo -e "${RED}错误: gRPC 必须提供域名！${PLAIN}"
                exit 1
            fi
            read -p "请输入 gRPC 服务名称 (例如 natsu_grpc) [natsu_grpc]: " grpc_service_name
            [[ -z "${grpc_service_name}" ]] && grpc_service_name="natsu_grpc"
            
            echo -e "${YELLOW}使用 gRPC + TLS 传输, 域名: ${domain}, 服务名: ${grpc_service_name}${PLAIN}"
            request_certificate "${domain}"

            stream_settings=$(cat <<EOF
      "network": "grpc",
      "security": "tls",
      "grpcSettings": {
        "serviceName": "${grpc_service_name}"
      },
      "tlsSettings": {
        "serverName": "${domain}",
        "certificates": [
          {
            "certificateFile": "/etc/letsencrypt/live/${domain}/fullchain.pem",
            "keyFile": "/etc/letsencrypt/live/${domain}/privkey.pem"
          }
        ]
      }
EOF
)
            ;;
        *)
            echo -e "${RED}错误: 无效的传输协议选择！${PLAIN}"
            exit 1
            ;;
    esac

    # Construct inbound JSON
    local clients_json=""
    if [[ "$protocol" == "vmess" ]]; then
        clients_json=$(cat <<EOF
        "clients": [
          {
            "id": "${uuid}",
            "alterId": ${alterid}
          }
        ]
EOF
)
    elif [[ "$protocol" == "vless" ]]; then
        clients_json=$(cat <<EOF
        "clients": [
          {
            "id": "${uuid}",
            "flow": "" // XTLS flow can be added here if needed, e.g., "xtls-rprx-direct"
          }
        ],
        "decryption": "none"
EOF
)
    fi

    inbound_config=$(cat <<EOF
    {
      "port": ${v2ray_listen_port},
      "listen": "127.0.0.1", // Default listen on localhost, change if needed (e.g. for non-TLS WS/TCP)
      "protocol": "${protocol}",
      "settings": {
${clients_json}
      },
      "streamSettings": {
${stream_settings}
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
EOF
)

    # Adjust listen address if not using Nginx proxy
     if [[ "$choice_transport" != "3" ]]; then # If not WS+TLS via Nginx
        if [[ "$transport" == "ws" && -z "$domain" ]]; then # Plain WS, listen on public IP if no domain
             inbound_config=$(echo "${inbound_config}" | jq '.listen = "0.0.0.0"')
        elif [[ "$transport" == "tcp" || "$transport" == "mkcp" ]]; then # TCP or mKCP, listen on public IP
             inbound_config=$(echo "${inbound_config}" | jq '.listen = "0.0.0.0"')
         # QUIC and gRPC usually bind to 127.0.0.1 if TLS is handled by V2Ray, but might need 0.0.0.0 depending on setup.
         # For simplicity and security, let's keep QUIC/gRPC listening on 127.0.0.1 as TLS settings are present.
         # If direct access is needed, manually change "listen" to "0.0.0.0" in the config.
        fi
     fi


    # Replace placeholder in the main config file
    jq --argjson inbound "$inbound_config" '.inbounds = [$inbound]' ${V2RAY_CONFIG_FILE} > ${V2RAY_CONFIG_FILE}.tmp && mv ${V2RAY_CONFIG_FILE}.tmp ${V2RAY_CONFIG_FILE}

    echo -e "${GREEN}V2Ray 配置文件生成成功！ (${V2RAY_CONFIG_FILE})${PLAIN}"

    # Store parameters for URL generation
    echo "${protocol}" > ${V2RAY_CONFIG_PATH}/protocol
    echo "${port}" > ${V2RAY_CONFIG_PATH}/port
    echo "${uuid}" > ${V2RAY_CONFIG_PATH}/uuid
    echo "${alterid}" > ${V2RAY_CONFIG_PATH}/alterid
    echo "${transport}" > ${V2RAY_CONFIG_PATH}/transport
    echo "${domain}" > ${V2RAY_CONFIG_PATH}/domain # Domain or IP
    echo "${ws_path}" > ${V2RAY_CONFIG_PATH}/ws_path
    echo "${mkcp_type}" > ${V2RAY_CONFIG_PATH}/mkcp_type
    echo "${mkcp_seed}" > ${V2RAY_CONFIG_PATH}/mkcp_seed
    echo "${quic_security}" > ${V2RAY_CONFIG_PATH}/quic_security
    echo "${quic_key}" > ${V2RAY_CONFIG_PATH}/quic_key
    echo "${quic_header}" > ${V2RAY_CONFIG_PATH}/quic_header
    echo "${grpc_service_name}" > ${V2RAY_CONFIG_PATH}/grpc_service_name
    
    # Determine security type for URL
    local security_type=""
     if [[ "$choice_transport" == "3" || "$choice_transport" == "5" || "$choice_transport" == "6" ]]; then
         security_type="tls"
     else
         security_type="none"
     fi
     echo "${security_type}" > ${V2RAY_CONFIG_PATH}/security

}


# Setup Automatic Certificate Renewal
setup_auto_renew() {
    local domain
    if [[ -f "${V2RAY_CONFIG_PATH}/domain" ]]; then
       domain=$(cat "${V2RAY_CONFIG_PATH}/domain")
    else
       echo -e "${YELLOW}未找到域名信息，跳过自动续期设置。${PLAIN}"
       return
    fi

    if [[ -z "$domain" ]]; then
        echo -e "${YELLOW}域名为空，无法设置自动续期。${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}设置 Certbot 自动续期...${PLAIN}"
    # Create a cron job to run certbot renew twice daily
    # Use --deploy-hook to reload nginx if needed (for WS+TLS)
    local deploy_hook=""
    local transport=$(cat "${V2RAY_CONFIG_PATH}/transport" 2>/dev/null)
    local security=$(cat "${V2RAY_CONFIG_PATH}/security" 2>/dev/null)

    # Reload Nginx only if WS+TLS was used
     if [[ "$transport" == "ws" && "$security" == "tls" ]] || systemctl is-active --quiet nginx; then
        deploy_hook='--deploy-hook "systemctl reload nginx"'
     fi

     # Check if cron job already exists
    if [[ ! -f /etc/cron.d/certbot_renew_v2ray ]]; then
        echo "0 */12 * * * root certbot renew --quiet ${deploy_hook}" > /etc/cron.d/certbot_renew_v2ray
        # Alternatively run weekly: 0 3 * * 1 root certbot ...
        chmod 644 /etc/cron.d/certbot_renew_v2ray
        echo -e "${GREEN}Certbot 自动续期任务已创建 (/etc/cron.d/certbot_renew_v2ray)。${PLAIN}"
    else
        echo -e "${YELLOW}Certbot 自动续期任务已存在。${PLAIN}"
    fi
    
    # Run renew once now to test
    echo -e "${YELLOW}尝试立即运行一次续期检查...${PLAIN}"
    certbot renew --quiet ${deploy_hook}
    echo -e "${GREEN}续期检查完成。${PLAIN}"

}

# Start V2Ray
start_v2ray() {
    echo -e "${YELLOW}启动 V2Ray 服务...${PLAIN}"
    systemctl start v2ray
    sleep 2 # Wait a bit for service to start
    if ! systemctl is-active --quiet v2ray; then
        echo -e "${RED}错误: V2Ray 服务启动失败！请检查日志: journalctl -u v2ray 或 ${V2RAY_ERROR_LOG}${PLAIN}"
        exit 1
    fi
    echo -e "${GREEN}V2Ray 服务已启动！${PLAIN}"
}

# Stop V2Ray
stop_v2ray() {
    echo -e "${YELLOW}停止 V2Ray 服务...${PLAIN}"
    systemctl stop v2ray
    echo -e "${GREEN}V2Ray 服务已停止。${PLAIN}"
}

# Restart V2Ray
restart_v2ray() {
    echo -e "${YELLOW}重启 V2Ray 服务...${PLAIN}"
    systemctl restart v2ray
    sleep 2
     if ! systemctl is-active --quiet v2ray; then
        echo -e "${RED}错误: V2Ray 服务重启失败！请检查日志: journalctl -u v2ray 或 ${V2RAY_ERROR_LOG}${PLAIN}"
    else
        echo -e "${GREEN}V2Ray 服务已重启！${PLAIN}"
     fi
}

# Uninstall V2Ray and related config
uninstall_v2ray() {
    echo -e "${YELLOW}正在卸载 V2Ray...${PLAIN}"
    stop_v2ray
    systemctl disable v2ray &> /dev/null
    rm -f ${V2RAY_SERVICE_FILE}
    rm -rf ${V2RAY_INSTALL_PATH}
    rm -rf ${V2RAY_CONFIG_PATH} # Remove config directory including saved parameters
    rm -f /var/log/v2ray/access.log /var/log/v2ray/error.log # Remove logs

    # Remove Nginx config if exists
    if [[ -f "${NGINX_CONFIG_FILE}" ]]; then
        echo -e "${YELLOW}移除 Nginx V2Ray 配置...${PLAIN}"
        rm -f ${NGINX_CONFIG_FILE}
        echo -e "${YELLOW}重新加载 Nginx...${PLAIN}"
        nginx -t && systemctl reload nginx # Test and reload nginx
    fi
    
    # Remove download directory
    if [[ -d "${DOWNLOAD_DIR}" ]]; then
       echo -e "${YELLOW}移除下载目录 ${DOWNLOAD_DIR}...${PLAIN}"
       rm -rf ${DOWNLOAD_DIR}
    fi
    
    # Remove cron job
    rm -f /etc/cron.d/certbot_renew_v2ray

    systemctl daemon-reload
    echo -e "${GREEN}V2Ray 卸载完成！${PLAIN}"
    echo -e "${YELLOW}注意：依赖项 (nginx, certbot, jq等) 和证书未被删除。${PLAIN}"
}

# Show V2Ray Config URL/Info
show_url() {
    if [[ ! -f "${V2RAY_CONFIG_PATH}/protocol" ]]; then
        echo -e "${RED}错误: 未找到 V2Ray 配置信息。请先安装或配置。${PLAIN}"
        return 1
    fi

    local protocol=$(cat "${V2RAY_CONFIG_PATH}/protocol")
    local port=$(cat "${V2RAY_CONFIG_PATH}/port")
    local uuid=$(cat "${V2RAY_CONFIG_PATH}/uuid")
    local alterid=$(cat "${V2RAY_CONFIG_PATH}/alterid")
    local transport=$(cat "${V2RAY_CONFIG_PATH}/transport")
    local address=$(cat "${V2RAY_CONFIG_PATH}/domain") # This holds domain or IP
    local ws_path=$(cat "${V2RAY_CONFIG_PATH}/ws_path" 2>/dev/null)
    local mkcp_type=$(cat "${V2RAY_CONFIG_PATH}/mkcp_type" 2>/dev/null)
    local mkcp_seed=$(cat "${V2RAY_CONFIG_PATH}/mkcp_seed" 2>/dev/null)
    local quic_security=$(cat "${V2RAY_CONFIG_PATH}/quic_security" 2>/dev/null)
    local quic_key=$(cat "${V2RAY_CONFIG_PATH}/quic_key" 2>/dev/null)
    local quic_header=$(cat "${V2RAY_CONFIG_PATH}/quic_header" 2>/dev/null)
    local grpc_service_name=$(cat "${V2RAY_CONFIG_PATH}/grpc_service_name" 2>/dev/null)
    local security=$(cat "${V2RAY_CONFIG_PATH}/security") # tls or none
    local remarks="V2Ray_${transport}_${address}" # Simple remarks

    # Get current public IP if address is empty (e.g., plain WS without domain)
    if [[ -z "$address" ]]; then
        address=$(curl -s https://api.ipify.org || curl -s https://ipinfo.io/ip)
        if [[ -z "$address" ]]; then
            echo -e "${YELLOW}警告：无法自动获取公网 IP，请手动填写地址。${PLAIN}"
            address="你的服务器IP或域名"
        fi
    fi

    echo -e "\n${GREEN}----- V2Ray 配置信息 -----${PLAIN}"
    echo -e "协议 (Protocol):      ${YELLOW}${protocol}${PLAIN}"
    echo -e "地址 (Address):       ${YELLOW}${address}${PLAIN}"
    echo -e "端口 (Port):          ${YELLOW}${port}${PLAIN}"
    echo -e "用户 ID (UUID):       ${YELLOW}${uuid}${PLAIN}"
    if [[ "$protocol" == "vmess" ]]; then
    echo -e "额外 ID (AlterId):    ${YELLOW}${alterid}${PLAIN}"
    fi
    echo -e "传输协议 (Network):   ${YELLOW}${transport}${PLAIN}"
    echo -e "TLS (Security):       ${YELLOW}${security}${PLAIN}"

    local share_url=""

    if [[ "$protocol" == "vmess" ]]; then
        local vmess_conf="{
          \"v\": \"2\",
          \"ps\": \"${remarks}\",
          \"add\": \"${address}\",
          \"port\": \"${port}\",
          \"id\": \"${uuid}\",
          \"aid\": \"${alterid}\",
          \"net\": \"${transport}\",
          \"type\": \"none\",
          \"host\": \"\",
          \"path\": \"\",
          \"tls\": \"${security}\"
        }"
        # Add transport specific details
        if [[ "$transport" == "ws" ]]; then
            vmess_conf=$(echo $vmess_conf | jq --arg path "$ws_path" '.path = $path')
            if [[ "$security" == "tls" ]]; then
               vmess_conf=$(echo $vmess_conf | jq --arg host "$address" '.host = $host') # SNI = address (domain)
            fi
        elif [[ "$transport" == "mkcp" ]]; then
            vmess_conf=$(echo $vmess_conf | jq --arg type "$mkcp_type" '.type = $type')
            # Note: VMess format doesn't officially support seed in URL, client needs manual config
        elif [[ "$transport" == "quic" ]]; then
            vmess_conf=$(echo $vmess_conf | jq --arg host "$address" '.host = $address') # SNI = address (domain)
            vmess_conf=$(echo $vmess_conf | jq --arg type "$quic_header" '.type = $type')
            # Note: VMess format doesn't officially support quicSecurity/quicKey in URL
        elif [[ "$transport" == "grpc" ]]; then
             vmess_conf=$(echo $vmess_conf | jq --arg path "$grpc_service_name" '.path = $path') # Use path for serviceName
             vmess_conf=$(echo $vmess_conf | jq '.host = ""') # Host for gRPC is usually empty unless specific routing needed
             if [[ "$security" == "tls" ]]; then
                vmess_conf=$(echo $vmess_conf | jq --arg host "$address" '.host = $host') # Add SNI
             fi
        fi
        share_url="vmess://$(echo -n $vmess_conf | base64 -w 0)"
        echo -e "VMess Type (Header):  ${YELLOW}${mkcp_type:-${quic_header:-none}}${PLAIN}" # Show header if applicable
        echo -e "路径/服务名 (Path):   ${YELLOW}${ws_path:-${grpc_service_name:-N/A}}${PLAIN}" # Show path/serviceName

    elif [[ "$protocol" == "vless" ]]; then
        share_url="vless://${uuid}@${address}:${port}"
        local params=""
        params+="type=${transport}"
        params+="&security=${security}"
         if [[ "$transport" == "ws" ]]; then
             params+="&path=$(rawurlencode "${ws_path}")"
             if [[ "$security" == "tls" ]]; then
                 params+="&host=${address}" # SNI
             fi
        elif [[ "$transport" == "mkcp" ]]; then
            params+="&headerType=${mkcp_type}"
            params+="&seed=$(rawurlencode "${mkcp_seed}")"
        elif [[ "$transport" == "quic" ]]; then
            params+="&quicSecurity=${quic_security}"
            params+="&key=${quic_key}"
            params+="&headerType=${quic_header}"
            params+="&host=${address}" # SNI
        elif [[ "$transport" == "grpc" ]]; then
            params+="&serviceName=${grpc_service_name}"
             if [[ "$security" == "tls" ]]; then
                 params+="&sni=${address}" # SNI for gRPC is often 'sni=' param
                 params+="&host=${address}" # Some clients might use 'host=' too
             fi
        fi
        share_url+="?${params}#$(rawurlencode "${remarks}")"
        echo -e "路径 (Path):          ${YELLOW}${ws_path:-N/A}${PLAIN}"
        echo -e "mKCP 类型 (Header):   ${YELLOW}${mkcp_type:-N/A}${PLAIN}"
        echo -e "mKCP Seed:          ${YELLOW}${mkcp_seed:-N/A}${PLAIN}"
        echo -e "QUIC 加密 (Sec):    ${YELLOW}${quic_security:-N/A}${PLAIN}"
        echo -e "QUIC 密钥 (Key):    ${YELLOW}${quic_key:-N/A}${PLAIN}"
        echo -e "QUIC 类型 (Header): ${YELLOW}${quic_header:-N/A}${PLAIN}"
        echo -e "gRPC 服务名:        ${YELLOW}${grpc_service_name:-N/A}${PLAIN}"
    fi

    echo -e "\n${GREEN}----- 分享链接 -----${PLAIN}"
    echo -e "${YELLOW}${share_url}${PLAIN}"

    echo -e "\n${GREEN}----- 二维码 (需要终端支持) -----${PLAIN}"
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 "${share_url}"
    else
        echo -e "${YELLOW}qrencode 未安装，无法生成二维码。请运行: sudo apt install qrencode${PLAIN}"
    fi
    echo -e "${GREEN}------------------------${PLAIN}"
}

# URL Encode Helper
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


# Main Menu
main_menu() {
    clear
    echo "========================================"
    echo " V2Ray (VMess/VLess) 安装管理脚本 "
    echo "========================================"
    echo " 1. 安装 V2Ray"
    echo " 2. 卸载 V2Ray"
    echo " 3. 修改 V2Ray 配置"
    echo " 4. 查看 V2Ray 配置/URL"
    echo " 5. 启动 V2Ray"
    echo " 6. 停止 V2Ray"
    echo " 7. 重启 V2Ray"
    echo " 8. 设置证书自动续期"
    echo " 0. 退出脚本"
    echo "----------------------------------------"
    
    # Check status
    if systemctl is-active --quiet v2ray; then
       echo -e " V2Ray 状态: ${GREEN}运行中${PLAIN}"
    else
       echo -e " V2Ray 状态: ${RED}未运行${PLAIN}"
    fi
    if [[ -f "${V2RAY_CONFIG_FILE}" ]]; then
        echo -e " 配置状态: ${GREEN}已配置${PLAIN}"
    else
        echo -e " 配置状态: ${RED}未配置/未安装${PLAIN}"
    fi
    echo "========================================"

    read -p "请输入选项 [0-8]: " choice

    case $choice in
        1)
            check_root
            check_os
            install_dependencies
            install_v2ray_core
            create_service_file
            generate_v2ray_config # This will ask all config questions
            setup_auto_renew # Setup renewal after getting domain
            start_v2ray
            show_url # Show result
            ;;
        2)
            check_root
            read -p "确定要卸载 V2Ray 吗? 这将删除程序、配置和 Nginx 相关设置 [y/N]: " confirm_uninstall
            if [[ "${confirm_uninstall}" =~ ^[yY]$ ]]; then
                uninstall_v2ray
            else
                echo -e "${YELLOW}卸载操作已取消。${PLAIN}"
            fi
            ;;
        3)
            check_root
            if [[ ! -f "${V2RAY_CONFIG_FILE}" ]]; then
                echo -e "${RED}错误: V2Ray 未安装或未配置，无法修改。请先安装。${PLAIN}"
            else
                echo -e "${YELLOW}修改配置将重新生成配置文件并重启服务。${PLAIN}"
                # Optionally ask to keep existing UUID/Domain before calling generate_v2ray_config
                stop_v2ray # Stop before changing config
                # Consider backing up old config here: cp ${V2RAY_CONFIG_FILE} ${V2RAY_CONFIG_FILE}.bak
                generate_v2ray_config # Ask all questions again
                setup_auto_renew # Re-run renewal setup in case domain changed
                restart_v2ray
                show_url
            fi
            ;;
        4)
            check_root
            show_url
            ;;
        5)
            check_root
            start_v2ray
            ;;
        6)
            check_root
            stop_v2ray
            ;;
        7)
            check_root
            restart_v2ray
            ;;
        8)
            check_root
             if [[ ! -f "${V2RAY_CONFIG_PATH}/domain" ]] || [[ -z $(cat "${V2RAY_CONFIG_PATH}/domain") ]]; then
                 echo -e "${RED}错误：需要先进行包含域名的 TLS 配置才能设置自动续期。${PLAIN}"
             else
                 setup_auto_renew
             fi
            ;;

        0)
            echo -e "${GREEN}退出脚本。${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请输入 0 到 8 之间的数字。${PLAIN}"
            ;;
    esac
    read -p "按 Enter键 返回主菜单..." enter_key
    main_menu # Loop back to main menu
}

# --- Script Execution Starts Here ---
main_menu
