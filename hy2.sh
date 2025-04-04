#!/bin/bash

# Hysteria 2 安装/卸载脚本 (Debian) - 菜单交互版 v3
# 支持自定义密码和端口, 无obfs, 自签名证书, 一键卸载

# --- 配置 ---
BINARY_URL="https://github.com/manatsu525/roo/releases/download/1/hysteria-linux-amd64"
INSTALL_PATH="/usr/local/bin/hysteria"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
CERT_FILE="${CONFIG_DIR}/server.crt"
KEY_FILE="${CONFIG_DIR}/server.key"
DEFAULT_PASSWORD="sumire"
DEFAULT_PORT="443"
CERT_DAYS=3650 # 10 years

# --- 工具函数 ---
_info() { echo -e "\033[0;32m[信息]\033[0m $1"; }
_warn() { echo -e "\033[0;33m[警告]\033[0m $1"; }
_error() { echo -e "\033[0;31m[错误]\033[0m $1"; exit 1; }
_cmd() { "$@" > /dev/null 2>&1 || _error "执行命令失败: $*"; }

# --- 核心函数 ---

# 检查 root 权限
check_root() {
    [ "$(id -u)" -ne 0 ] && _error "请以 root 权限运行此脚本"
}

# 检查并安装依赖
check_deps() {
    for pkg in curl openssl; do
        if ! command -v $pkg &> /dev/null; then
            _info "安装依赖: $pkg ..."
            _cmd apt update
            _cmd apt install -y $pkg
        fi
    done
}

# 生成自签名证书
generate_cert() {
    _info "生成自签名 TLS 证书 (${CERT_DAYS} 天)..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
        -keyout "${KEY_FILE}" -out "${CERT_FILE}" -sha256 -days ${CERT_DAYS} \
        -subj "/CN=localhost" > /dev/null 2>&1 || _error "生成证书失败"
    _cmd chmod 600 "${KEY_FILE}"
}

# 生成配置文件 (无 obfs)
generate_config() {
    local port="$1"
    local password="$2"
    _info "创建配置文件: ${CONFIG_FILE}"
    cat << EOF > "${CONFIG_FILE}"
listen: :${port}
tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}
auth:
  type: password
  password: ${password}
EOF
    [ $? -ne 0 ] && _error "创建配置文件失败"
}

# 创建 Systemd 服务文件
create_service_file() {
    _info "创建 Systemd 服务: ${SERVICE_FILE}"
    cat << EOF > "${SERVICE_FILE}"
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=${CONFIG_DIR}
ExecStart=${INSTALL_PATH} server --config ${CONFIG_FILE}
Restart=on-failure
RestartSec=3s
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
}

# 执行安装流程
do_install() {
    local password=""
    local port=""

    # 获取端口
    read -p $'\033[0;36m请输入 Hysteria 监听端口 [默认: '"${DEFAULT_PORT}"']: \033[0m' input_port
    port="${input_port:-${DEFAULT_PORT}}" # 如果用户直接回车，则使用默认值
    # 简单的端口号验证
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        _error "无效的端口号: ${port}。请输入 1-65535 之间的数字。"
    fi
    _info "使用端口: ${port}"

    # 获取密码
    read -p $'\033[0;36m是否使用默认密码 '"'${DEFAULT_PASSWORD}'"'? (Y/n):\033[0m ' use_default_pw
    if [[ "$use_default_pw" =~ ^[Nn]$ ]]; then
        read -s -p $'\033[0;36m请输入你的 Hysteria 密码: \033[0m' input_password
        echo
        [ -z "$input_password" ] && _error "密码不能为空"
        password="${input_password}"
    else
        password="${DEFAULT_PASSWORD}"
    fi
    _info "使用密码: ${password}" # 注意：生产环境密码不应直接打印

    _info "开始安装 Hysteria 2 (来源: ${BINARY_URL})"
    check_deps

    _info "下载 Hysteria..."
    _cmd curl -L -o "${INSTALL_PATH}" "${BINARY_URL}"
    _cmd chmod +x "${INSTALL_PATH}"

    _info "创建配置目录..."
    _cmd mkdir -p "${CONFIG_DIR}"

    generate_cert
    generate_config "${port}" "${password}" # 传递端口和密码
    create_service_file

    _info "启用并启动服务..."
    _cmd systemctl daemon-reload
    _cmd systemctl enable hysteria-server
    _cmd systemctl restart hysteria-server

    sleep 2
    _info "检查 Hysteria 服务状态:"
    systemctl status hysteria-server --no-pager -l || _warn "服务可能启动失败, 请检查配置或日志 (journalctl -u hysteria-server -f)"

    echo "----------------------------------------"
    _info "Hysteria 2 安装完成!"
    _info "  监听端口: ${port}"
    _info "  认证密码: ${password}"
    _info "  配置文件: ${CONFIG_FILE}"
    _info "  证书文件: ${CERT_FILE}, ${KEY_FILE} (自签名)"
    _info "  客户端连接时，需要配置对应端口和密码，并忽略 TLS 证书验证。"
    _info "  如需修改配置, 编辑 ${CONFIG_FILE} 后运行: sudo systemctl restart hysteria-server"
    echo "----------------------------------------"
}

# 执行卸载流程
do_uninstall() {
    read -p $'\033[0;33m确定要卸载 Hysteria 2 并删除所有相关文件吗? (y/N):\033[0m ' confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        _info "正在卸载 Hysteria 2..."
        _cmd systemctl stop hysteria-server
        _cmd systemctl disable hysteria-server
        _cmd rm -f "${SERVICE_FILE}"
        _cmd rm -f "${INSTALL_PATH}"
        _cmd rm -rf "${CONFIG_DIR}"
        _cmd systemctl daemon-reload
        _info "Hysteria 2 已卸载。"
        _info "如果设置过防火墙规则，请手动移除。"
    else
        _info "取消卸载。"
    fi
}

# 显示主菜单
show_menu() {
    clear
    echo "===================================="
    echo " Hysteria 2 管理脚本 (Debian) v3 "
    echo " (无 Obfs, 端口/密码可配)"
    echo "===================================="
    echo " 1) 安装 Hysteria 2"
    echo " 2) 卸载 Hysteria 2"
    echo " *) 退出脚本"
    echo "------------------------------------"
    read -p "请输入选项 [1-2]: " choice
}

# --- 主逻辑 ---
check_root

show_menu

case "$choice" in
    1)
        do_install
        ;;
    2)
        do_uninstall
        ;;
    *)
        _info "退出脚本。"
        ;;
esac

exit 0
