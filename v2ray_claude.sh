#!/bin/bash

# V2Ray + Caddy + WS+TLS 管理脚本
# 支持安装、卸载、查看配置等功能

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

V2RAY_CONFIG_DIR="/usr/local/etc/v2ray"
V2RAY_CONFIG_FILE="$V2RAY_CONFIG_DIR/config.json"
CADDY_CONFIG_FILE="/etc/caddy/Caddyfile"
DOWNLOADS_DIR="/usr/downloads"
SERVICE_NAME="v2ray"

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查系统
check_system() {
    if [[ ! -f /etc/debian_version ]]; then
        log_error "此脚本仅支持 Debian 系统"
        exit 1
    fi
    
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
}

# 生成随机字符串
generate_random() {
    local length=${1:-16}
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c $length
}

# 生成 UUID
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# 获取域名
get_domain() {
    while true; do
        read -p "请输入你的域名: " domain
        if [[ -n "$domain" ]]; then
            echo "$domain"
            break
        else
            log_error "域名不能为空"
        fi
    done
}

# 安装依赖
install_dependencies() {
    log_info "更新系统包..."
    apt update -y

    log_info "安装必要依赖..."
    apt install -y curl wget unzip jq
}

# 安装 V2Ray
install_v2ray() {
    log_info "安装 V2Ray..."
    
    # 下载安装脚本
    curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash
    
    if [[ $? -ne 0 ]]; then
        log_error "V2Ray 安装失败"
        exit 1
    fi
    
    log_info "V2Ray 安装完成"
}

# 安装 Caddy
install_caddy() {
    log_info "安装 Caddy..."
    
    # 添加 Caddy 官方源
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    
    apt update -y
    apt install -y caddy
    
    if [[ $? -ne 0 ]]; then
        log_error "Caddy 安装失败"
        exit 1
    fi
    
    log_info "Caddy 安装完成"
}

# 创建下载目录和文件浏览器
setup_file_browser() {
    log_info "设置文件浏览器..."
    
    mkdir -p "$DOWNLOADS_DIR"
    chmod 755 "$DOWNLOADS_DIR"
    
    # 创建一些示例文件
    echo "欢迎使用文件下载服务" > "$DOWNLOADS_DIR/README.txt"
    echo "# 文件下载中心" > "$DOWNLOADS_DIR/index.md"
    
    log_info "文件浏览器设置完成，目录: $DOWNLOADS_DIR"
}

# 配置 V2Ray
configure_v2ray() {
    local uuid=$(generate_uuid)
    local ws_path="/$(generate_random 10)"
    
    log_info "配置 V2Ray..."
    log_info "UUID: $uuid"
    log_info "WebSocket 路径: $ws_path"
    
    mkdir -p "$V2RAY_CONFIG_DIR"
    
    cat > "$V2RAY_CONFIG_FILE" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log"
  },
  "inbounds": [
    {
      "port": 10000,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "level": 1,
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$ws_path"
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

    # 创建日志目录
    mkdir -p /var/log/v2ray
    chown nobody:nogroup /var/log/v2ray
    
    # 保存配置信息到文件
    cat > "/root/v2ray_config.txt" << EOF
V2Ray 配置信息
=============
UUID: $uuid
WebSocket 路径: $ws_path
端口: 10000 (内部端口，通过 Caddy 代理)
协议: VMess
网络: WebSocket + TLS
EOF

    log_info "V2Ray 配置完成"
    return 0
}

# 配置 Caddy
configure_caddy() {
    local domain=$1
    local ws_path=$(grep -o '"/[^"]*"' "$V2RAY_CONFIG_FILE" | grep -o '[^"]*' | head -1)
    
    log_info "配置 Caddy..."
    log_info "域名: $domain"
    log_info "WebSocket 路径: $ws_path"
    
    cat > "$CADDY_CONFIG_FILE" << EOF
$domain {
    # WebSocket 代理到 V2Ray
    handle $ws_path {
        reverse_proxy 127.0.0.1:10000
    }
    
    # 文件浏览器伪装
    handle /* {
        file_server browse {
            root $DOWNLOADS_DIR
        }
    }
    
    # 自动 HTTPS
    tls {
        protocols tls1.2 tls1.3
    }
    
    # 访问日志
    log {
        output file /var/log/caddy/access.log
        format json
    }
    
    # 错误处理
    handle_errors {
        respond "Page not found" 404
    }
}
EOF

    # 创建日志目录
    mkdir -p /var/log/caddy
    chown caddy:caddy /var/log/caddy
    
    log_info "Caddy 配置完成"
}

# 启动服务
start_services() {
    log_info "启动服务..."
    
    # 启动 V2Ray
    systemctl enable v2ray
    systemctl start v2ray
    
    if ! systemctl is-active --quiet v2ray; then
        log_error "V2Ray 启动失败"
        systemctl status v2ray
        exit 1
    fi
    
    # 启动 Caddy
    systemctl enable caddy
    systemctl restart caddy
    
    if ! systemctl is-active --quiet caddy; then
        log_error "Caddy 启动失败"
        systemctl status caddy
        exit 1
    fi
    
    log_info "所有服务启动成功"
}

# 显示配置信息
show_config() {
    if [[ ! -f "/root/v2ray_config.txt" ]]; then
        log_error "找不到配置文件，请先安装 V2Ray"
        return 1
    fi
    
    local domain=$(grep -E "^[^#]*{" "$CADDY_CONFIG_FILE" | head -1 | awk '{print $1}')
    local uuid=$(grep -o '"id": "[^"]*"' "$V2RAY_CONFIG_FILE" | cut -d '"' -f 4)
    local ws_path=$(grep -o '"path": "[^"]*"' "$V2RAY_CONFIG_FILE" | cut -d '"' -f 4)
    
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         V2Ray 连接信息                 ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}地址 (Address):${NC} $domain"
    echo -e "${GREEN}端口 (Port):${NC} 443"
    echo -e "${GREEN}用户ID (UUID):${NC} $uuid"
    echo -e "${GREEN}额外ID (AlterID):${NC} 0"
    echo -e "${GREEN}加密方式 (Security):${NC} auto"
    echo -e "${GREEN}传输协议 (Network):${NC} ws"
    echo -e "${GREEN}WebSocket路径 (Path):${NC} $ws_path"
    echo -e "${GREEN}传输安全 (TLS):${NC} tls"
    echo -e "${GREEN}跳过证书验证:${NC} false"
    echo
    echo -e "${YELLOW}伪装网站:${NC} https://$domain"
    echo -e "${YELLOW}文件浏览器:${NC} https://$domain (访问 $DOWNLOADS_DIR)"
    echo -e "${BLUE}========================================${NC}"
    echo
}

# 检查服务状态
check_status() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         服务状态检查                   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # 检查 V2Ray
    if systemctl is-active --quiet v2ray; then
        echo -e "${GREEN}V2Ray:${NC} 运行中 ✓"
    else
        echo -e "${RED}V2Ray:${NC} 未运行 ✗"
    fi
    
    # 检查 Caddy
    if systemctl is-active --quiet caddy; then
        echo -e "${GREEN}Caddy:${NC} 运行中 ✓"
    else
        echo -e "${RED}Caddy:${NC} 未运行 ✗"
    fi
    
    # 检查端口
    if netstat -tlnp | grep -q ":443 "; then
        echo -e "${GREEN}端口 443:${NC} 监听中 ✓"
    else
        echo -e "${RED}端口 443:${NC} 未监听 ✗"
    fi
    
    if netstat -tlnp | grep -q ":10000 "; then
        echo -e "${GREEN}端口 10000:${NC} 监听中 ✓"
    else
        echo -e "${RED}端口 10000:${NC} 未监听 ✗"
    fi
    
    echo -e "${BLUE}========================================${NC}"
}

# 查看日志
view_logs() {
    echo "选择要查看的日志:"
    echo "1. V2Ray 访问日志"
    echo "2. V2Ray 错误日志"
    echo "3. Caddy 访问日志"
    echo "4. 系统服务日志 (V2Ray)"
    echo "5. 系统服务日志 (Caddy)"
    
    read -p "请选择 (1-5): " choice
    
    case $choice in
        1)
            if [[ -f "/var/log/v2ray/access.log" ]]; then
                tail -50 /var/log/v2ray/access.log
            else
                log_warn "V2Ray 访问日志文件不存在"
            fi
            ;;
        2)
            if [[ -f "/var/log/v2ray/error.log" ]]; then
                tail -50 /var/log/v2ray/error.log
            else
                log_warn "V2Ray 错误日志文件不存在"
            fi
            ;;
        3)
            if [[ -f "/var/log/caddy/access.log" ]]; then
                tail -50 /var/log/caddy/access.log | jq .
            else
                log_warn "Caddy 访问日志文件不存在"
            fi
            ;;
        4)
            journalctl -u v2ray -n 50
            ;;
        5)
            journalctl -u caddy -n 50
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 重启服务
restart_services() {
    log_info "重启服务..."
    
    systemctl restart v2ray
    systemctl restart caddy
    
    sleep 3
    check_status
}

# 卸载
uninstall() {
    log_warn "即将卸载 V2Ray 和 Caddy，此操作不可逆！"
    read -p "确认卸载？(y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "取消卸载"
        return
    fi
    
    log_info "停止服务..."
    systemctl stop v2ray caddy
    systemctl disable v2ray caddy
    
    log_info "卸载 V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) --remove
    
    log_info "卸载 Caddy..."
    apt remove -y caddy
    
    log_info "清理配置文件..."
    rm -rf "$V2RAY_CONFIG_DIR"
    rm -f "$CADDY_CONFIG_FILE"
    rm -f "/root/v2ray_config.txt"
    rm -rf "/var/log/v2ray"
    rm -rf "/var/log/caddy"
    
    log_info "清理下载目录..."
    read -p "是否删除下载目录 $DOWNLOADS_DIR ? (y/N): " del_downloads
    if [[ "$del_downloads" == "y" || "$del_downloads" == "Y" ]]; then
        rm -rf "$DOWNLOADS_DIR"
        log_info "下载目录已删除"
    fi
    
    log_info "卸载完成"
}

# 更新配置
update_config() {
    log_info "重新生成配置..."
    
    # 备份当前配置
    if [[ -f "$V2RAY_CONFIG_FILE" ]]; then
        cp "$V2RAY_CONFIG_FILE" "$V2RAY_CONFIG_FILE.bak"
    fi
    
    if [[ -f "$CADDY_CONFIG_FILE" ]]; then
        cp "$CADDY_CONFIG_FILE" "$CADDY_CONFIG_FILE.bak"
    fi
    
    # 获取域名
    local domain=$(get_domain)
    
    # 重新配置
    configure_v2ray
    configure_caddy "$domain"
    
    # 重启服务
    restart_services
    
    log_info "配置更新完成"
    show_config
}

# 安装主函数
install_all() {
    log_info "开始安装 V2Ray + Caddy + WS+TLS..."
    
    # 获取域名
    local domain=$(get_domain)
    
    # 安装步骤
    install_dependencies
    install_v2ray
    install_caddy
    setup_file_browser
    configure_v2ray
    configure_caddy "$domain"
    start_services
    
    log_info "安装完成！"
    show_config
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}      V2Ray + Caddy 管理脚本            ${NC}"
    echo -e "${BLUE}      WebSocket + TLS + 文件浏览器      ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    echo "1. 安装 V2Ray + Caddy"
    echo "2. 卸载"
    echo "3. 查看配置信息"
    echo "4. 检查服务状态"
    echo "5. 查看日志"
    echo "6. 重启服务"
    echo "7. 更新配置"
    echo "0. 退出"
    echo
}

# 主程序
main() {
    check_system
    
    while true; do
        show_menu
        read -p "请选择操作 (0-7): " choice
        
        case $choice in
            1)
                install_all
                read -p "按回车键继续..."
                ;;
            2)
                uninstall
                read -p "按回车键继续..."
                ;;
            3)
                show_config
                read -p "按回车键继续..."
                ;;
            4)
                check_status
                read -p "按回车键继续..."
                ;;
            5)
                view_logs
                read -p "按回车键继续..."
                ;;
            6)
                restart_services
                read -p "按回车键继续..."
                ;;
            7)
                update_config
                read -p "按回车键继续..."
                ;;
            0)
                log_info "退出脚本"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新输入"
                sleep 2
                ;;
        esac
    done
}

# 运行主程序
main "$@"
