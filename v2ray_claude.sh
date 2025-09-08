#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置文件路径
V2RAY_PATH="/usr/local/bin/v2ray"
V2RAY_CONFIG="/usr/local/etc/v2ray/config.json"
CADDY_CONFIG="/etc/caddy/Caddyfile"
INFO_FILE="/etc/v2ray_info.txt"

# 生成UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 安装依赖
install_deps() {
    echo -e "${GREEN}安装依赖...${NC}"
    apt update
    apt install -y wget unzip curl
}

# 安装v2ray
install_v2ray() {
    echo -e "${GREEN}下载v2ray...${NC}"
    mkdir -p /usr/local/bin/v2ray /usr/local/etc/v2ray
    wget -O /tmp/v2ray.zip https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip
    unzip -o /tmp/v2ray.zip -d /usr/local/bin/v2ray/
    chmod +x /usr/local/bin/v2ray/v2ray
    rm /tmp/v2ray.zip
}

# 安装caddy
install_caddy() {
    echo -e "${GREEN}安装Caddy...${NC}"
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
}

# 配置v2ray
configure_v2ray() {
    local uuid=$1
    local ws_port=$2
    local mkcp_port=$3
    local mkcp_type=$4
    local mkcp_seed=$5
    
    cat > $V2RAY_CONFIG <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $ws_port,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/natsu"
        }
      }
    },
    {
      "port": $mkcp_port,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "mkcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 50,
          "uplinkCapacity": 12,
          "downlinkCapacity": 100,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "$mkcp_type"
          },
          "seed": "$mkcp_seed"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
}

# 配置caddy
configure_caddy() {
    local domain=$1
    local ws_port=$2
    
    # 检查文件目录
    if [ ! -d "/usr/downloads" ]; then
        echo -e "${YELLOW}警告: /usr/downloads 目录不存在，文件服务器可能无法正常工作${NC}"
    fi
    
    cat > $CADDY_CONFIG <<EOF
$domain {
    tls lineair069@gmail.com
    
    handle /natsu* {
        reverse_proxy localhost:$ws_port {
            header_up Host {host}
            header_up X-Real-IP {remote}
            header_up X-Forwarded-For {remote}
            header_up X-Forwarded-Proto {scheme}
        }
    }
    
    handle /file* {
        file_server browse {
            root /usr/downloads
        }
    }
    
    handle {
        reverse_proxy https://www.honda.com {
            header_up Host www.honda.com
        }
    }
}
EOF
}

# 创建systemd服务
create_service() {
    cat > /etc/systemd/system/v2ray.service <<EOF
[Unit]
Description=V2Ray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/v2ray/v2ray run -config /usr/local/etc/v2ray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable v2ray
    systemctl restart v2ray
    systemctl restart caddy
}

# 保存配置信息
save_info() {
    local domain=$1
    local uuid=$2
    local ws_port=$3
    local mkcp_port=$4
    local mkcp_type=$5
    local mkcp_seed=$6
    
    cat > $INFO_FILE <<EOF
DOMAIN=$domain
UUID=$uuid
WS_PORT=$ws_port
MKCP_PORT=$mkcp_port
MKCP_TYPE=$mkcp_type
MKCP_SEED=$mkcp_seed
EOF
}

# 显示配置信息
show_info() {
    if [ ! -f "$INFO_FILE" ]; then
        echo -e "${RED}未找到配置信息${NC}"
        return
    fi
    
    # 读取配置
    source $INFO_FILE
    
    echo -e "\n${GREEN}========== 配置信息 ==========${NC}"
    echo -e "域名: ${YELLOW}$DOMAIN${NC}"
    echo -e "UUID: ${YELLOW}$UUID${NC}"
    echo -e "WS端口: ${YELLOW}$WS_PORT${NC}"
    echo -e "mKCP端口: ${YELLOW}$MKCP_PORT${NC}"
    echo -e "mKCP类型: ${YELLOW}$MKCP_TYPE${NC}"
    echo -e "mKCP Seed: ${YELLOW}$MKCP_SEED${NC}"
    
    echo -e "\n${GREEN}========== VMess链接 ==========${NC}"
    
    # WS+TLS链接
    local ws_json=$(cat <<EOF
{
  "v": "2",
  "ps": "WS+TLS-${DOMAIN}",
  "add": "${DOMAIN}",
  "port": "443",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${DOMAIN}",
  "path": "/natsu",
  "tls": "tls",
  "sni": "${DOMAIN}",
  "alpn": ""
}
EOF
)
    local ws_base64=$(echo -n "$ws_json" | base64 -w 0)
    echo -e "\n${YELLOW}VMess (WS+TLS):${NC}"
    echo -e "${BLUE}vmess://${ws_base64}${NC}"
    
    # mKCP链接
    local mkcp_json=$(cat <<EOF
{
  "v": "2",
  "ps": "mKCP-${DOMAIN}",
  "add": "${DOMAIN}",
  "port": "${MKCP_PORT}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "kcp",
  "type": "${MKCP_TYPE}",
  "host": "",
  "path": "${MKCP_SEED}",
  "tls": "",
  "sni": "",
  "alpn": ""
}
EOF
)
    local mkcp_base64=$(echo -n "$mkcp_json" | base64 -w 0)
    echo -e "\n${YELLOW}VMess (mKCP):${NC}"
    echo -e "${BLUE}vmess://${mkcp_base64}${NC}"
    
    # 生成二维码链接（可选）
    echo -e "\n${GREEN}========== 二维码生成链接 ==========${NC}"
    echo -e "WS+TLS: https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=vmess://${ws_base64}"
    echo -e "mKCP: https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=vmess://${mkcp_base64}"
}

# 查看服务状态
check_status() {
    echo -e "\n${GREEN}========== 服务状态 ==========${NC}"
    
    # V2Ray状态
    echo -e "\n${YELLOW}V2Ray 状态:${NC}"
    if systemctl is-active --quiet v2ray; then
        echo -e "${GREEN}● V2Ray 正在运行${NC}"
        systemctl status v2ray --no-pager | head -n 3
    else
        echo -e "${RED}● V2Ray 未运行${NC}"
    fi
    
    # Caddy状态
    echo -e "\n${YELLOW}Caddy 状态:${NC}"
    if systemctl is-active --quiet caddy; then
        echo -e "${GREEN}● Caddy 正在运行${NC}"
        systemctl status caddy --no-pager | head -n 3
    else
        echo -e "${RED}● Caddy 未运行${NC}"
    fi
    
    # 端口监听状态
    echo -e "\n${YELLOW}端口监听状态:${NC}"
    if [ -f "$INFO_FILE" ]; then
        source $INFO_FILE
        echo -n "WS端口 ($WS_PORT): "
        if ss -tuln | grep -q ":$WS_PORT "; then
            echo -e "${GREEN}监听中${NC}"
        else
            echo -e "${RED}未监听${NC}"
        fi
        echo -n "mKCP端口 ($MKCP_PORT): "
        if ss -tuln | grep -q ":$MKCP_PORT "; then
            echo -e "${GREEN}监听中${NC}"
        else
            echo -e "${RED}未监听${NC}"
        fi
        echo -n "HTTPS端口 (443): "
        if ss -tuln | grep -q ":443 "; then
            echo -e "${GREEN}监听中${NC}"
        else
            echo -e "${RED}未监听${NC}"
        fi
    fi
}

# 查看日志
view_logs() {
    echo -e "\n${GREEN}========== 日志查看 ==========${NC}"
    echo "1. 查看V2Ray日志"
    echo "2. 查看Caddy日志"
    echo "3. 查看V2Ray错误日志（最后50行）"
    echo "4. 查看Caddy错误日志（最后50行）"
    echo "5. 实时查看V2Ray日志"
    echo "6. 实时查看Caddy日志"
    echo "0. 返回主菜单"
    
    read -p "请选择 [0-6]: " log_choice
    
    case $log_choice in
        1)
            echo -e "\n${YELLOW}V2Ray日志:${NC}"
            journalctl -u v2ray --no-pager -n 100
            ;;
        2)
            echo -e "\n${YELLOW}Caddy日志:${NC}"
            journalctl -u caddy --no-pager -n 100
            ;;
        3)
            echo -e "\n${YELLOW}V2Ray错误日志:${NC}"
            journalctl -u v2ray -p err --no-pager -n 50
            ;;
        4)
            echo -e "\n${YELLOW}Caddy错误日志:${NC}"
            journalctl -u caddy -p err --no-pager -n 50
            ;;
        5)
            echo -e "\n${YELLOW}实时V2Ray日志（按Ctrl+C退出）:${NC}"
            journalctl -u v2ray -f
            ;;
        6)
            echo -e "\n${YELLOW}实时Caddy日志（按Ctrl+C退出）:${NC}"
            journalctl -u caddy -f
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 卸载
uninstall() {
    echo -e "${YELLOW}开始卸载...${NC}"
    
    # 停止服务
    systemctl stop v2ray 2>/dev/null
    systemctl stop caddy 2>/dev/null
    systemctl disable v2ray 2>/dev/null
    
    # 删除文件
    rm -rf /usr/local/bin/v2ray
    rm -rf /usr/local/etc/v2ray
    rm -f /etc/systemd/system/v2ray.service
    rm -f $INFO_FILE
    
    # 卸载caddy但保留证书
    apt remove -y caddy
    rm -f $CADDY_CONFIG
    
    systemctl daemon-reload
    echo -e "${GREEN}卸载完成（证书已保留）${NC}"
}

# 安装
install() {
    echo -e "${GREEN}开始安装VMess服务${NC}"
    
    # 获取配置
    read -p "请输入域名: " domain
    read -p "请输入WS端口 [默认10000]: " ws_port
    ws_port=${ws_port:-10000}
    read -p "请输入mKCP端口 [默认20000]: " mkcp_port
    mkcp_port=${mkcp_port:-20000}
    
    echo "请选择mKCP伪装类型:"
    echo "1) none"
    echo "2) srtp"
    echo "3) utp"
    echo "4) wechat-video"
    echo "5) dtls"
    echo "6) wireguard"
    read -p "请选择 [1-6]: " mkcp_choice
    
    case $mkcp_choice in
        1) mkcp_type="none" ;;
        2) mkcp_type="srtp" ;;
        3) mkcp_type="utp" ;;
        4) mkcp_type="wechat-video" ;;
        5) mkcp_type="dtls" ;;
        6) mkcp_type="wireguard" ;;
        *) mkcp_type="none" ;;
    esac
    
    read -p "请输入mKCP seed [留空随机]: " mkcp_seed
    mkcp_seed=${mkcp_seed:-$(openssl rand -hex 8)}
    
    uuid=$(generate_uuid)
    
    # 安装组件
    install_deps
    install_v2ray
    install_caddy
    
    # 配置
    configure_v2ray "$uuid" "$ws_port" "$mkcp_port" "$mkcp_type" "$mkcp_seed"
    configure_caddy "$domain" "$ws_port"
    
    # 启动服务
    create_service
    
    # 保存信息
    save_info "$domain" "$uuid" "$ws_port" "$mkcp_port" "$mkcp_type" "$mkcp_seed"
    
    echo -e "${GREEN}安装完成！${NC}"
    show_info
}

# 主菜单
main_menu() {
    clear
    echo -e "${GREEN}========== VMess 管理脚本 ==========${NC}"
    echo "1. 安装VMess"
    echo "2. 卸载VMess"
    echo "3. 重新安装"
    echo "4. 显示配置信息"
    echo "5. 查看服务状态"
    echo "6. 查看日志"
    echo "0. 退出"
    echo -e "${GREEN}====================================${NC}"
    
    read -p "请选择操作 [0-6]: " choice
    
    case $choice in
        1)
            install
            ;;
        2)
            uninstall
            ;;
        3)
            uninstall
            install
            ;;
        4)
            show_info
            ;;
        5)
            check_status
            ;;
        6)
            view_logs
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo -e "\n按任意键返回主菜单..."
    read -n 1
    main_menu
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用root权限运行此脚本${NC}"
    exit 1
fi

# 启动主菜单
main_menu
