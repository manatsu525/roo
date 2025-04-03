#!/bin/bash

HYSTERIA_BIN="/usr/local/bin/hysteria"
CONFIG_DIR="/etc/hysteria"
SERVICE_FILE="/etc/systemd/system/hysteria.service"

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "请使用root权限运行此脚本"
        exit 1
    fi
}

# 生成自签名证书
generate_cert() {
    echo "正在生成自签名证书（有效期10年）..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout $CONFIG_DIR/server.key -out $CONFIG_DIR/server.crt \
        -subj "/CN=honda.com" -days 3650 -addext "subjectAltName=DNS:bing.com"
}

# 安装Hysteria
install_hysteria() {
    echo "正在安装Hysteria..."
    wget -O $HYSTERIA_BIN https://github.com/manatsu525/roo/releases/download/1/hysteria-linux-amd64
    chmod +x $HYSTERIA_BIN
}

# 生成配置文件
generate_config() {
    echo "正在生成配置文件..."
    cat > $CONFIG_DIR/config.yaml <<EOF
listen: :$PORT

tls:
  cert: $CONFIG_DIR/server.crt
  key: $CONFIG_DIR/server.key

auth:
  type: password
  password: "$AUTH_PASSWORD"

masquerade:
  type: proxy
  proxy:
    url: "$MASQ_URL"
    rewriteHost: true
EOF
}

# 配置系统服务
setup_service() {
    echo "正在配置系统服务..."
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Hysteria VPN Service
After=network.target

[Service]
User=root
WorkingDirectory=/etc/hysteria
ExecStart=$HYSTERIA_BIN server -c $CONFIG_DIR/config.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable hysteria
    systemctl start hysteria
}

# 交互式配置
interactive_config() {
    echo
    echo "====== 基本配置 ======"
    read -p "请输入监听端口（默认443）: " PORT
    PORT=${PORT:-443}

    echo
    read -p "请输入认证密码（默认随机生成）: " AUTH_PASSWORD
    if [ -z "$AUTH_PASSWORD" ]; then
        AUTH_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    fi

    echo
    read -p "请输入伪装代理地址（默认https://www.honda.com/）: " MASQ_URL
    MASQ_URL=${MASQ_URL:-"https://www.honda.com/"}
}

# 显示配置信息
show_info() {
    clear
    echo "====== 安装完成 ======"
    echo "监听端口: $PORT"
    echo "认证密码: $AUTH_PASSWORD"
    echo "伪装URL: $MASQ_URL"
    echo "证书路径: $CONFIG_DIR/server.crt"
    echo
    echo "管理命令:"
    echo "启动服务: systemctl start hysteria"
    echo "停止服务: systemctl stop hysteria"
    echo "查看日志: journalctl -u hysteria -f"
    echo
    echo "客户端配置示例："
    echo "server: your_server_ip:$PORT"
    echo "auth: $AUTH_PASSWORD"
    echo "tls:"
    echo "  insecure: true"
    echo "masquerade:"
    echo "  type: proxy"
}

# 卸载Hysteria
uninstall() {
    echo "正在卸载Hysteria..."
    systemctl stop hysteria
    systemctl disable hysteria
    rm -f $SERVICE_FILE
    rm -f $HYSTERIA_BIN
    rm -rf $CONFIG_DIR
    systemctl daemon-reload
    echo "Hysteria已卸载"
}

# 主菜单
main_menu() {
    clear
    echo "====== Hysteria2 管理脚本 ======"
    PS3='请选择操作: '
    options=("安装" "卸载" "退出")
    select opt in "${options[@]}"
    do
        case $opt in
            "安装")
                check_root
                mkdir -p $CONFIG_DIR
                install_hysteria
                interactive_config
                generate_cert
                generate_config
                setup_service
                show_info
                break
                ;;
            "卸载")
                check_root
                uninstall
                break
                ;;
            "退出")
                exit 0
                ;;
            *) echo "无效选项，请重新选择";;
        esac
    done
}

# 启动主菜单
main_menu
