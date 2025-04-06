#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 定义 V2Ray 下载链接和版本
V2RAY_DOWNLOAD_URL="https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip"
V2RAY_VERSION="5.5.0" # 可以根据实际压缩包内的版本修改

# 定义 Nginx 安装状态
NGINX_INSTALLED=false

# 定义证书邮箱
CERTBOT_EMAIL="lineair069@gmail.com"

# 定义 V2Ray 配置文件夹
V2RAY_CONFIG_DIR="/etc/v2ray"
V2RAY_CONFIG_FILE="${V2RAY_CONFIG_DIR}/config.json"
V2RAY_SYSTEMD_FILE="/etc/systemd/system/v2ray.service"

# 定义 Nginx 配置文件夹
NGINX_CONFIG_DIR="/etc/nginx"
NGINX_DEFAULT_SITE="${NGINX_CONFIG_DIR}/sites-available/default"
NGINX_V2RAY_CONFIG="${NGINX_CONFIG_DIR}/conf.d/v2ray.conf"

# 定义文件服务器路径
FILE_SERVER_PATH="/usr/download"

# 检查是否为 root 用户
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}错误：请使用 root 权限运行此脚本。${NC}"
  exit 1
fi

# 函数：打印菜单
print_menu() {
  echo -e "${BLUE}V2Ray 搭建管理脚本${NC}"
  echo "-------------------------"
  echo "1. 搭建 V2Ray"
  echo "2. 卸载 V2Ray"
  echo "3. 修改 V2Ray 配置"
  echo "4. 显示 V2Ray URL"
  echo "5. 退出"
  echo "-------------------------"
  read -p "请选择操作 (1-5): " choice
}

# 函数：检查 V2Ray 是否已安装
is_v2ray_installed() {
  if [ -f "/usr/bin/v2ray" ] && [ -f "$V2RAY_CONFIG_FILE" ] && [ -f "$V2RAY_SYSTEMD_FILE" ]; then
    return 0 # 已安装
  else
    return 1 # 未安装
  fi
}

# 函数：检查 Nginx 是否已安装
is_nginx_installed() {
  if command -v nginx &> /dev/null; then
    NGINX_INSTALLED=true
    return 0 # 已安装
  else
    NGINX_INSTALLED=false
    return 1 # 未安装
  fi
}

# 函数：安装 V2Ray
install_v2ray() {
  if is_v2ray_installed; then
    echo -e "${YELLOW}V2Ray 已经安装过了。${NC}"
    return
  fi

  echo -e "${GREEN}开始安装 V2Ray...${NC}"

  # 下载 V2Ray
  echo "下载 V2Ray..."
  if ! curl -o /tmp/v2ray.zip -L "$V2RAY_DOWNLOAD_URL"; then
    echo -e "${RED}下载 V2Ray 失败。${NC}"
    return
  fi

  # 解压 V2Ray
  echo "解压 V2Ray..."
  if ! unzip /tmp/v2ray.zip -d /tmp/v2ray; then
    echo -e "${RED}解压 V2Ray 失败。${NC}"
    rm -f /tmp/v2ray.zip
    return
  fi

  # 移动 V2Ray 可执行文件
  echo "移动 V2Ray 可执行文件..."
  chmod +x /tmp/v2ray/v2ray /tmp/v2ray/v2ctl
  mv /tmp/v2ray/v2ray /usr/bin/
  mv /tmp/v2ray/v2ctl /usr/bin/
  rm -rf /tmp/v2ray /tmp/v2ray.zip

  # 创建 V2Ray 配置文件夹
  echo "创建 V2Ray 配置文件夹..."
  mkdir -p "$V2RAY_CONFIG_DIR"

  # 生成默认配置
  generate_v2ray_config

  # 创建 systemd 服务文件
  echo "创建 systemd 服务文件..."
  cat <<EOF > "$V2RAY_SYSTEMD_FILE"
[Unit]
Description=V2Ray Service
After=network.target

[Service]
User=nobody
WorkingDirectory=$V2RAY_CONFIG_DIR
ExecStart=/usr/bin/v2ray run -config $V2RAY_CONFIG_FILE
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  # 启用并启动 V2Ray 服务
  echo "启用并启动 V2Ray 服务..."
  systemctl enable v2ray
  systemctl start v2ray

  if systemctl is-active --quiet v2ray; then
    echo -e "${GREEN}V2Ray 安装完成并已启动。${NC}"
  else
    echo -e "${RED}V2Ray 安装完成，但启动失败，请检查日志。${NC}"
  fi
}

# 函数：卸载 V2Ray
uninstall_v2ray() {
  if ! is_v2ray_installed; then
    echo -e "${YELLOW}V2Ray 尚未安装。${NC}"
    return
  fi

  echo -e "${YELLOW}开始卸载 V2Ray...${NC}"

  # 停止并禁用 V2Ray 服务
  echo "停止并禁用 V2Ray 服务..."
  systemctl stop v2ray
  systemctl disable v2ray
  systemctl daemon-reload

  # 删除 V2Ray 相关文件
  echo "删除 V2Ray 相关文件..."
  rm -f /usr/bin/v2ray /usr/bin/v2ctl
  rm -rf "$V2RAY_CONFIG_DIR"
  rm -f "$V2RAY_SYSTEMD_FILE"

  echo -e "${GREEN}V2Ray 卸载完成。${NC}"

  # 询问是否卸载 Nginx
  read -p "是否同时卸载 Nginx？ (y/N): " uninstall_nginx
  if [[ "$uninstall_nginx" == "y" || "$uninstall_nginx" == "Y" ]]; then
    uninstall_nginx_full
  fi
}

# 函数：安装 Nginx
install_nginx() {
  if is_nginx_installed; then
    echo -e "${YELLOW}Nginx 已经安装过了。${NC}"
    return
  fi

  echo -e "${GREEN}开始安装 Nginx...${NC}"
  apt update
  apt install -y nginx

  if is_nginx_installed; then
    echo -e "${GREEN}Nginx 安装完成。${NC}"
  else
    echo -e "${RED}Nginx 安装失败。${NC}"
  fi
}

# 函数：卸载 Nginx (完整卸载，包括配置文件)
uninstall_nginx_full() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}Nginx 尚未安装。${NC}"
    return
  fi

  echo -e "${YELLOW}开始卸载 Nginx (包括配置文件)...${NC}"
  apt purge -y nginx nginx-common nginx-core
  apt autoremove -y
  echo -e "${GREEN}Nginx 卸载完成。${NC}"
  NGINX_INSTALLED=false
}

# 函数：配置 Nginx 反向代理和文件服务器
configure_nginx() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}请先安装 Nginx。${NC}"
    return
  fi

  echo -e "${GREEN}配置 Nginx 反向代理和文件服务器...${NC}"

  # 备份默认 Nginx 配置文件
  if [ -f "$NGINX_DEFAULT_SITE" ]; then
    mv "$NGINX_DEFAULT_SITE" "$NGINX_DEFAULT_SITE".bak
  fi

  # 创建文件服务器目录
  mkdir -p "$FILE_SERVER_PATH"

  # 生成 Nginx 配置文件
  cat <<EOF > "$NGINX_V2RAY_CONFIG"
server {
    listen 80;
    listen [::]:80;
    server_name _; # 你的域名或 IP

    location /natsu {
        proxy_pass http://127.0.0.1:$V2RAY_WS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /file {
        alias $FILE_SERVER_PATH/;
        autoindex on;
    }

    location / {
        proxy_pass http://www.honda.com;
        proxy_set_header Host www.honda.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name _; # 你的域名或 IP

    ssl_certificate /etc/letsencrypt/live/\$V2RAY_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/\$V2RAY_DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256;
    ssl_prefer_server_ciphers on;

    location /natsu {
        proxy_pass http://127.0.0.1:$V2RAY_WS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /file {
        alias $FILE_SERVER_PATH/;
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

  # 删除默认的 default 软链接（如果存在）
  if [ -L "${NGINX_CONFIG_DIR}/sites-enabled/default" ]; then
    rm "${NGINX_CONFIG_DIR}/sites-enabled/default"
  fi

  # 启用 v2ray 配置
  ln -s "$NGINX_V2RAY_CONFIG" "${NGINX_CONFIG_DIR}/sites-enabled/v2ray.conf"

  # 测试 Nginx 配置
  nginx -t
  if [ $? -ne 0 ]; then
    echo -e "${RED}Nginx 配置有误，请检查 /etc/nginx/conf.d/v2ray.conf 文件。${NC}"
    return
  fi

  # 重启 Nginx 服务
  systemctl restart nginx

  echo -e "${GREEN}Nginx 配置完成。请确保你的域名已正确解析到服务器 IP。${NC}"
}

# 函数：获取 Let's Encrypt 证书
get_certificate() {
  if ! is_nginx_installed; then
    echo -e "${YELLOW}请先安装 Nginx。${NC}"
    return
  fi

  echo -e "${GREEN}获取 Let's Encrypt 证书...${NC}"

  # 检查是否已安装 certbot
  if ! command -v certbot &> /dev/null; then
    echo "certbot 未安装，尝试安装..."
    apt update
    apt install -y certbot python3-certbot-nginx
    if ! command -v certbot &> /dev/null; then
      echo -e "${RED}安装 certbot 失败，请手动安装。${NC}"
      return
    fi
  fi

  # 获取证书
  certbot --nginx --agree-tos -m "$CERTBOT_EMAIL" -d "$V2RAY_DOMAIN" --non-interactive
  if [ $? -ne 0 ]; then
    echo -e "${RED}获取 Let's Encrypt 证书失败，请检查域名是否正确解析，以及 Nginx 配置是否正确。${NC}"
    return
  fi

  echo -e "${GREEN}Let's Encrypt 证书获取成功。${NC}"
}

# 函数：配置自动证书更新
configure_certbot_renewal() {
  echo -e "${GREEN}配置自动证书更新 (每两个月)...${NC}"

  # 构建 cron 命令
  cron_command="0 0 */60 * * /usr/bin/certbot renew --nginx --quiet"

  # 检查 crontab 中是否已存在相关条目，避免重复添加
  if ! crontab -l | grep -q "$cron_command"; then
    (crontab -l; echo "$cron_command") | crontab -
    echo -e "${GREEN}自动证书更新已配置，每两个月执行一次。${NC}"
  else
    echo -e "${YELLOW}自动证书更新已配置过。${NC}"
  fi
}

# 函数：生成 V2Ray 配置文件
generate_v2ray_config() {
  local protocol
  local transport
  local vmess_port
  local vless_port
  local ws_port
  local grpc_port
  local quic_port
  local mkcp_port
  local mkcp_type
  local mkcp_seed
  local domain
  local uuid

  echo -e "${BLUE}配置 V2Ray 参数${NC}"

  # 选择协议
  select protocol in "vmess" "vless"; do
    case "$protocol" in
      vmess) break ;;
      vless) break ;;
      *) echo "无效的选择，请重新选择。" ;;
    esac
  done

  # 配置 VMess
  if [[ "$protocol" == "vmess" ]]; then
    read -p "请输入 VMess 端口 (例如: 10001): " vmess_port
    read -p "请输入 VMess 用户 UUID (留空自动生成): " uuid
    if [ -z "$uuid" ]; then
      uuid=$(uuidgen)
      echo "自动生成的 UUID: $uuid"
    fi
  fi

  # 配置 VLess
  if [[ "$protocol" == "vless" ]]; then
    read -p "请输入 VLess 端口 (例如: 20001): " vless_port
    read -p "请输入 VLess 用户 UUID (留空自动生成): " uuid
    if [ -z "$uuid" ]; then
      uuid=$(uuidgen)
      echo "自动生成的 UUID: $uuid"
    fi
  fi

  # 选择传输方式
  echo -e "\n${BLUE}选择传输方式${NC}"
  echo "1. ws+tls"
  echo "2. mkcp"
  echo "3. quic"
  echo "4. grpc"
  read -p "请选择传输方式 (1-4): " transport_choice

  case "$transport_choice" in
    1) transport="ws"; read -p "请输入 WebSocket 端口 (例如: 443): " ws_port; read -p "请输入你的域名 (用于 TLS): " domain; V2RAY_WS_PORT="$ws_port"; V2RAY_DOMAIN="$domain" ;;
    2) transport="mkcp"; read -p "请输入 MKCP 端口 (例如: 30001): " mkcp_port;
       echo -e "\n${BLUE}选择 MKCP 伪装类型${NC}"
       echo "1. none"
       echo "2. tcp"
       echo "3. utp"
       echo "4. wechat-video"
       echo "5. dtls"
       echo "6. srtp"
       echo "7. wireguard"
       read -p "请选择 MKCP 伪装类型 (1-7): " mkcp_type_choice
       case "$mkcp_type_choice" in
         1) mkcp_type="none" ;;
         2) mkcp_type="tcp" ;;
         3) mkcp_type="utp" ;;
         4) mkcp_type="wechat-video" ;;
         5) mkcp_type="dtls" ;;
         6) mkcp_type="srtp" ;;
         7) mkcp_type="wireguard" ;;
         *) echo "无效的选择，使用默认值 none。" mkcp_type="none" ;;
       esac
       read -p "请输入 MKCP seed (留空自动生成): " mkcp_seed
       if [ -z "$mkcp_seed" ]; then
         mkcp_seed=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
         echo "自动生成的 MKCP seed: $mkcp_seed"
       fi
       ;;
    3) transport="quic"; read -p "请输入 QUIC 端口 (例如: 40001): " quic_port ;;
    4) transport="grpc"; read -p "请输入 gRPC 端口 (例如: 50001): " grpc_port ;;
    *) echo "无效的选择，使用默认传输方式 ws+tls。" transport="ws"; read -p "请输入 WebSocket 端口 (例如: 443): " ws_port; read -p "请输入你的域名 (用于 TLS): " domain; V2RAY_WS_PORT="$ws_port"; V2RAY_DOMAIN="$domain" ;;
  esac

  # 生成配置文件内容
  local config_content='{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": '$vmess_port${vless_port}',
      "protocol": "'$protocol'",
      "settings": {
        "clients": [
          {
            "id": "'$uuid'",
            "level": 1,
            "alterId": 64
          }
        ]
      },
      "streamSettings": {
        "network": "'$transport'"'
  if [[ "$transport" == "ws" ]]; then
    config_content="$config_content',
        "wsSettings": {
          "path": "/natsu"
        },
        "security": "tls",
        "tlsSettings": {
          "serverName": "'$domain'",
          "certificates": [
            {
              "certificateFile": "/etc/letsencrypt/live/$domain/fullchain.pem",
              "keyFile": "/etc/letsencrypt/live/$domain/privkey.pem"
            }
          ]
        }'
  elif [[ "$transport" == "mkcp" ]]; then
    config_content="$config_content',
        "kcpSettings": {
          "uplinkCapacity": 100,
          "downlinkCapacity": 100,
          "congestion": false,
          "mtu": 1350,
          "tti": 20,
          "seed": "'$mkcp_seed'",
          "writeBufferSize": 2097152,
          "readBufferSize": 2097152,
          "header": {
            "type": "'$mkcp_type'"
          }
        }'
  elif [[ "$transport" == "quic" ]]; then
    config_content="$config_content',
        "quicSettings": {}'
  elif [[ "$transport" == "grpc" ]]; then
    config_content="$config_content',
        "grpcSettings": {
          "serviceName": ""
        }'
  fi
  config_content="$config_content'
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}'

  # 将配置写入文件
  echo "$config_content" > "$V2RAY_CONFIG_FILE"

  echo -e "${GREEN}V2Ray 配置文件已生成。${NC}"
}

# 函数：修改 V2Ray 配置
modify_v2ray_config() {
  if ! is_v2ray_installed; then
    echo -e "${YELLOW}V2Ray 尚未安装。${NC}"
    return
  fi

  echo -e "${YELLOW}开始修改 V2Ray 配置...${NC}"
  generate_v2ray_config

  # 重启 V2Ray 服务
  echo "重启 V2Ray 服务..."
  systemctl restart v2ray

  if systemctl is-active --quiet v2ray; then
    echo -e "${GREEN}V2Ray 配置已修改并已重启。${NC}"
  else
    echo -e "${RED}V2Ray 配置已修改，但重启失败，请检查日志。${NC}"
  fi
}

# 函数：显示 V2Ray URL
show_v2ray_url() {
  if ! is_v2ray_installed; then
    echo -e "${YELLOW}V2Ray 尚未安装。${NC}"
    return
  fi

  local protocol
  local transport
  local port
  local uuid
  local domain

  # 从配置文件中读取必要信息
  protocol=$(jq -r .inbounds[0].protocol "$V2RAY_CONFIG_FILE")
  transport=$(jq -r .inbounds[0].streamSettings.network "$V2RAY_CONFIG_FILE")
  port=$(jq -r .inbounds[0].port "$V2RAY_CONFIG_FILE")
  uuid=$(jq -r .inbounds[0].settings.clients[0].id "$V2RAY_CONFIG_FILE")

  echo -e "\n${BLUE}V2Ray 客户端 URL${NC}"

  if [[ "$protocol" == "vmess" ]]; then
    if [[ "$transport" == "ws" ]]; then
      domain=$(jq -r .inbounds[0].streamSettings.tlsSettings.serverName "$V2RAY_CONFIG_FILE")
      echo "vmess://${uuid}@${domain}:${port}?path=/natsu&security=tls&type=ws"
    elif [[ "$transport" == "mkcp" ]]; then
      local mkcp_type=$(jq -r .inbounds[0].streamSettings.kcpSettings.header.type "$V2RAY_CONFIG_FILE")
      echo "vmess://${uuid}@服务器IP:${port}?security=none&type=kcp&headerType=${mkcp_type}" # 注意替换服务器IP
    elif [[ "$transport" == "quic" ]]; then
      echo "vmess://${uuid}@服务器IP:${port}?security=none&type=quic" # 注意替换服务器IP
    elif [[ "$transport" == "grpc" ]]; then
      echo "vmess://${uuid}@服务器IP:${port}?security=none&type=grpc&serviceName=" # 注意替换服务器IP
    else
      echo -e "${RED}不支持的传输方式，无法生成 URL。${NC}"
    fi
  elif [[ "$protocol" == "vless" ]]; then
    if [[ "$transport" == "ws" ]]; then
      domain=$(jq -r .inbounds[0].streamSettings.tlsSettings.serverName "$V2RAY_CONFIG_FILE")
      echo "vless://${uuid}@${domain}:${port}?path=/natsu&security=tls&type=ws&alpn=h2,http/1.1"
    elif [[ "$transport" == "mkcp" ]]; then
      local mkcp_type=$(jq -r .inbounds[0].streamSettings.kcpSettings.header.type "$V2RAY_CONFIG_FILE")
      echo "vless://${uuid}@服务器IP:${port}?security=none&type=kcp&headerType=${mkcp_type}&alpn=h2,http/1.1" # 注意替换服务器IP
    elif [[ "$transport" == "quic" ]]; then
      echo "vless://${uuid}@服务器IP:${port}?security=none&type=quic&alpn=h2,http/1.1" # 注意替换服务器IP
    elif [[ "$transport" == "grpc" ]]; then
      echo "vless://${uuid}@服务器IP:${port}?security=none&type=grpc&serviceName=&alpn=h2,http/1.1" # 注意替换服务器IP
    else
      echo -e "${RED}不支持的传输方式，无法生成 URL。${NC}"
    fi
  else
    echo -e "${RED}不支持的协议，无法生成 URL。${NC}"
  fi

  echo -e "\n${YELLOW}请将 '服务器IP' 替换为你的服务器实际 IP 地址。${NC}"
}

# 主函数
main() {
  while true; do
    print_menu
    case "$choice" in
      1) install_v2ray;
         if is_v2ray_installed; then
           install_nginx
           if is_nginx_installed; then
             configure_nginx
             get_certificate
             configure_certbot_renewal
           fi
         fi
         ;;
      2) uninstall_v2ray ;;
      3) modify_v2ray_config;
         if is_v2ray_installed && is_nginx_installed; then
           configure_nginx
           get_certificate
           configure_certbot_renewal
         fi
         ;;
      4) show_v2ray_url ;;
      5) echo "退出。"; exit 0 ;;
      *) echo -e "${RED}无效的选择，请重新输入。${NC}" ;;
    esac
  done
}

# 运行主函数
main
