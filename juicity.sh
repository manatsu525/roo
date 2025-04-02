#!/bin/bash

# Juicity 管理脚本 (安装/卸载)
# 默认使用 Root 权限运行
# 系统: Debian

# --- 配置 ---
JUICITY_URL="https://github.com/manatsu525/roo/releases/download/2/juicity-linux-x86_64.zip"
JUICITY_INSTALL_PATH="/usr/local/bin"
JUICITY_CONFIG_DIR="/etc/juicity"
JUICITY_CONFIG_FILE="${JUICITY_CONFIG_DIR}/config.json"
JUICITY_SERVICE_FILE="/etc/systemd/system/juicity.service"
JUICITY_BINARY_NAME="juicity-server"
CERT_FILE="${JUICITY_CONFIG_DIR}/server.crt"
KEY_FILE="${JUICITY_CONFIG_DIR}/private.key"

# 固定 UUID (备选) - 已替换
FIXED_UUID="f4a2a2e5-1b4b-4e4e-8e8e-8a8a8a8a8a8a"

# 固定密码
FIXED_PASSWORD="sumire"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- 函数 ---

# 检查是否为 Root 用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行。${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在更新软件包列表并安装依赖 (curl, unzip, openssl, uuid-runtime)...${NC}"
    apt update > /dev/null 2>&1
    if ! apt install -y curl unzip openssl uuid-runtime > /dev/null 2>&1; then
        echo -e "${RED}错误: 安装依赖失败。请检查apt源或手动安装 curl, unzip, openssl, uuid-runtime。${NC}"
        exit 1
    fi
    echo -e "${GREEN}依赖安装完成。${NC}"
}

# 生成自签名证书
generate_certificate() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        echo -e "${YELLOW}证书文件已存在，跳过生成。${NC}"
        return
    fi
    echo -e "${YELLOW}正在生成自签名证书...${NC}"
    mkdir -p "$JUICITY_CONFIG_DIR"
    # 使用 ECDSA (P-384) 提高性能和安全性
    if openssl ecparam -name secp384r1 -genkey -noout -out "$KEY_FILE" && \
       openssl req -new -x509 -days 3650 -key "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=localhost"; then
        chmod 600 "$KEY_FILE" # 保护私钥
        echo -e "${GREEN}自签名证书生成成功 (${CERT_FILE}, ${KEY_FILE})。${NC}"
    else
        echo -e "${RED}错误: 生成自签名证书失败。${NC}"
        # 清理可能创建的部分文件
        rm -f "$KEY_FILE" "$CERT_FILE"
        exit 1
    fi
}

# 选择或生成 UUID
get_uuid() {
    local choice
    local generated_uuid
    echo -e "${YELLOW}请选择 UUID 生成方式:${NC}"
    echo "1) 使用固定的 UUID (${FIXED_UUID})"
    echo "2) 随机生成一个新的 UUID"
    read -p "请输入选项 (1 或 2): " choice

    case "$choice" in
        1)
            INSTALL_UUID="$FIXED_UUID"
            echo -e "${GREEN}将使用固定 UUID: ${INSTALL_UUID}${NC}"
            ;;
        2)
            if command -v uuidgen &> /dev/null; then
                generated_uuid=$(uuidgen)
                INSTALL_UUID="$generated_uuid"
                echo -e "${GREEN}已生成随机 UUID: ${INSTALL_UUID}${NC}"
            else
                echo -e "${RED}错误: 'uuidgen' 命令未找到。请确保 'uuid-runtime' 已安装。${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}无效的选择。退出。${NC}"
            exit 1
            ;;
    esac
}

# 创建 Juicity 配置文件
create_config_file() {
    echo -e "${YELLOW}正在创建 Juicity 配置文件 (${JUICITY_CONFIG_FILE})...${NC}"
    # 获取服务器的公网 IP (尝试多种方法)
    SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ipv4.icanhazip.com || echo "127.0.0.1")
    LISTEN_PORT="443" # 默认监听443端口，可以按需修改

    mkdir -p "$JUICITY_CONFIG_DIR"
    cat > "$JUICITY_CONFIG_FILE" << EOF
{
  "listen": ":${LISTEN_PORT}",
  "users": {
    "${INSTALL_UUID}": "${FIXED_PASSWORD}"
  },
  "certificate": "${CERT_FILE}",
  "private_key": "${KEY_FILE}",
  "congestion_control": "bbr",
  "log_level": "info"
}
EOF
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}配置文件创建成功。${NC}"
        # 显示给用户的信息
        echo -e "\n--- ${YELLOW}Juicity 配置信息${NC} ---"
        echo -e "服务器 IP / 域名: ${YELLOW}${SERVER_IP}${NC}"
        echo -e "监听端口:        ${YELLOW}${LISTEN_PORT}${NC}"
        echo -e "UUID:            ${YELLOW}${INSTALL_UUID}${NC}"
        echo -e "密码:            ${YELLOW}${FIXED_PASSWORD}${NC}" # 新增密码显示
        echo -e "协议:            ${YELLOW}juicity${NC}"
        echo -e "TLS:             ${YELLOW}开启 (使用自签名证书)${NC}"
        echo -e "允许不安全连接: ${YELLOW}是 (因为是自签名证书)${NC}"
        echo -e "---------------------------\n"
    else
        echo -e "${RED}错误: 创建配置文件失败。${NC}"
        exit 1
    fi
}

# 创建 Systemd 服务文件
create_service_file() {
    echo -e "${YELLOW}正在创建 Systemd 服务文件 (${JUICITY_SERVICE_FILE})...${NC}"
    cat > "$JUICITY_SERVICE_FILE" << EOF
[Unit]
Description=Juicity Server Service
Documentation=https://github.com/juicity/juicity
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=${JUICITY_CONFIG_DIR}
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=${JUICITY_INSTALL_PATH}/${JUICITY_BINARY_NAME} run -c ${JUICITY_CONFIG_FILE}
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Systemd 服务文件创建成功。${NC}"
    else
        echo -e "${RED}错误: 创建 Systemd 服务文件失败。${NC}"
        exit 1
    fi
}

# 安装 Juicity
install_juicity() {
    echo -e "${GREEN}=== 开始安装 Juicity ===${NC}"

    install_dependencies

    # 下载并解压 Juicity
    echo -e "${YELLOW}正在下载 Juicity (${JUICITY_URL})...${NC}"
    TEMP_DIR=$(mktemp -d)
    if curl -L -o "${TEMP_DIR}/juicity.zip" "$JUICITY_URL"; then
        echo -e "${GREEN}下载完成。正在解压...${NC}"
        if unzip -o "${TEMP_DIR}/juicity.zip" -d "$TEMP_DIR"; then
            echo -e "${GREEN}解压完成。${NC}"
            # 查找 juicity-server 文件并移动
            JUICITY_EXEC=$(find "$TEMP_DIR" -name "${JUICITY_BINARY_NAME}" -type f)
            if [ -n "$JUICITY_EXEC" ]; then
                if install -m 755 "$JUICITY_EXEC" "${JUICITY_INSTALL_PATH}/"; then
                     echo -e "${GREEN}Juicity 可执行文件已安装到 ${JUICITY_INSTALL_PATH}/${JUICITY_BINARY_NAME}${NC}"
                else
                     echo -e "${RED}错误: 移动 Juicity 可执行文件失败。${NC}"
                     rm -rf "$TEMP_DIR"
                     exit 1
                fi
            else
                echo -e "${RED}错误: 在解压后的文件中未找到 ${JUICITY_BINARY_NAME}。${NC}"
                rm -rf "$TEMP_DIR"
                exit 1
            fi
        else
            echo -e "${RED}错误: 解压失败。${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        echo -e "${RED}错误: 下载 Juicity 失败。请检查 URL 或网络连接。${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    # 清理临时文件
    rm -rf "$TEMP_DIR"

    # 生成证书
    generate_certificate

    # 获取 UUID
    get_uuid

    # 创建配置文件 (密码已固定为 sumire)
    create_config_file

    # 创建服务文件
    create_service_file

    # 启用并启动服务
    echo -e "${YELLOW}正在启用并启动 Juicity 服务...${NC}"
    systemctl daemon-reload
    systemctl enable juicity.service
    systemctl start juicity.service

    # 检查服务状态
    sleep 2 # 等待服务启动
    if systemctl is-active --quiet juicity.service; then
        echo -e "${GREEN}Juicity 服务已成功启动并运行。${NC}"
        echo -e "${YELLOW}重要提示: 请确保防火墙已放行配置文件中指定的端口 (默认为 443/TCP)。${NC}"
        echo -e "${GREEN}=== Juicity 安装完成 ===${NC}"
    else
        echo -e "${RED}错误: Juicity 服务未能成功启动。请运行 'journalctl -u juicity.service' 查看日志。${NC}"
        echo -e "${YELLOW}尝试查看最近的日志:${NC}"
        journalctl -n 20 -u juicity.service --no-pager
        exit 1
    fi
}

# 卸载 Juicity
uninstall_juicity() {
    echo -e "${YELLOW}=== 开始卸载 Juicity ===${NC}"

    # 停止并禁用服务
    if systemctl list-unit-files | grep -q juicity.service; then
        echo -e "${YELLOW}正在停止并禁用 Juicity 服务...${NC}"
        systemctl stop juicity.service
        systemctl disable juicity.service
        echo -e "${GREEN}服务已停止并禁用。${NC}"
    else
        echo -e "${YELLOW}Juicity 服务未找到，跳过停止和禁用步骤。${NC}"
    fi

    # 删除服务文件
    if [ -f "$JUICITY_SERVICE_FILE" ]; then
        echo -e "${YELLOW}正在删除 Systemd 服务文件...${NC}"
        rm -f "$JUICITY_SERVICE_FILE"
        systemctl daemon-reload
        echo -e "${GREEN}服务文件已删除。${NC}"
    fi

    # 删除配置文件和证书目录
    if [ -d "$JUICITY_CONFIG_DIR" ]; then
        echo -e "${YELLOW}正在删除配置文件和证书 (${JUICITY_CONFIG_DIR})...${NC}"
        rm -rf "$JUICITY_CONFIG_DIR"
        echo -e "${GREEN}配置目录已删除。${NC}"
    fi

    # 删除可执行文件
    if [ -f "${JUICITY_INSTALL_PATH}/${JUICITY_BINARY_NAME}" ]; then
        echo -e "${YELLOW}正在删除 Juicity 可执行文件 (${JUICITY_INSTALL_PATH}/${JUICITY_BINARY_NAME})...${NC}"
        rm -f "${JUICITY_INSTALL_PATH}/${JUICITY_BINARY_NAME}"
        echo -e "${GREEN}可执行文件已删除。${NC}"
    fi

    echo -e "${GREEN}=== Juicity 卸载完成 ===${NC}"
}

# --- 主逻辑 ---
check_root

echo -e "${GREEN}欢迎使用 Juicity 管理脚本${NC}"
echo "--------------------------------"
echo "请选择要执行的操作:"
echo "1) 安装 Juicity"
echo "2) 卸载 Juicity"
echo "*) 退出脚本"
echo "--------------------------------"
read -p "请输入选项 (1 或 2): " main_choice

case "$main_choice" in
    1)
        install_juicity
        ;;
    2)
        # 卸载前确认
        read -p "确定要卸载 Juicity 吗? 这将删除配置文件、证书和服务 (y/N): )" confirm_uninstall
        if [[ "$confirm_uninstall" =~ ^[Yy]$ ]]; then
            uninstall_juicity
        else
            echo -e "${YELLOW}取消卸载。${NC}"
        fi
        ;;
    *)
        echo -e "${YELLOW}无效选择，退出脚本。${NC}"
        exit 0
        ;;
esac

exit 0
