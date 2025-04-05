#!/bin/bash

INSTALL_DIR="/root"
CADDY_BIN="${INSTALL_DIR}/caddy"
CADDY_CONFIG="${INSTALL_DIR}/Caddyfile"
CADDY_URL="https://github.com/manatsu525/roo/releases/download/naive/caddy"
TLS_EMAIL="lineair069@gmail.com" # 你原来的邮箱
AUTH_USER="sumire"             # 你原来的用户名
AUTH_PASS="sumire"             # 你原来的密码
FILE_ROOT="/usr/downloads"      # 你原来的文件路径

# 函数：停止 Caddy
stop_caddy() {
    echo "尝试停止 Caddy..."
    cd "${INSTALL_DIR}" || return 1 # 如果目录不存在，直接返回失败
    if [ -f "${CADDY_BIN}" ]; then
        # 尝试优雅停止
        ./caddy stop --config "${CADDY_CONFIG}" > /dev/null 2>&1
        sleep 1 # 给点时间停止
        # 强制杀死以防万一 (检查进程是否存在再杀更安全，但为了简洁直接尝试)
        pkill -f "${CADDY_BIN} run --config ${CADDY_CONFIG}" > /dev/null 2>&1
    fi
    echo "停止操作尝试完成。"
}

# 函数：创建 Caddyfile (提取出来方便复用)
create_caddyfile() {
    local domain=$1
    echo "正在创建 Caddyfile (域名: ${domain})..."
    cat > "${CADDY_CONFIG}" <<-EOF
:443, ${domain}
tls ${TLS_EMAIL}
route {
    forward_proxy {
        basic_auth ${AUTH_USER} ${AUTH_PASS}
        hide_ip
        hide_via
        probe_resistance
    }
    file_server {
        root ${FILE_ROOT}
        browse
    }
}
EOF
    #mkdir -p "${FILE_ROOT}" # 确保文件服务器目录存在
}

# 函数：启动 Caddy
start_caddy() {
    cd "${INSTALL_DIR}" || { echo "错误：无法进入目录 ${INSTALL_DIR}"; return 1; }
    if [ ! -f "${CADDY_BIN}" ]; then echo "错误：未找到 Caddy 执行文件 ${CADDY_BIN}"; return 1; fi
    if [ ! -f "${CADDY_CONFIG}" ]; then echo "错误：未找到配置文件 ${CADDY_CONFIG}"; return 1; fi

    echo "正在启动 Caddy..."
    ./caddy start --config "${CADDY_CONFIG}"
    sleep 1 # 等待一下
}


# 函数：安装或更新
install_or_update() {
    read -p "请输入你的域名: " domain
    if [[ -z "$domain" ]]; then echo "错误：域名不能为空。"; return 1; fi

    stop_caddy # 先停止旧的

    cd "${INSTALL_DIR}" || exit 1
    echo "正在下载/更新 Caddy..."
    # 只有在安装/更新时才下载
    wget --no-check-certificate -O "${CADDY_BIN}" "${CADDY_URL}" && chmod +x "${CADDY_BIN}"
    if [ $? -ne 0 ]; then echo "错误：下载 Caddy 失败。"; return 1; fi

    create_caddyfile "$domain" # 创建配置文件
    start_caddy               # 启动服务

    echo "--- 安装/更新完成 ---"
    echo "域名: ${domain}"
    echo "用户: ${AUTH_USER}"
    echo "密码: ${AUTH_PASS}"
    echo "NaiveProxy URL 示例: https://${AUTH_USER}:${AUTH_PASS}@${domain}"
    echo "Caddy 已在后台启动。"
    echo "--------------------"
}

# 函数：修改配置 (只改配置，不重新下载)
modify_config() {
    echo "修改配置将停止当前服务并使用新域名重新生成配置。"
    read -p "请输入新的域名: " new_domain
    if [[ -z "$new_domain" ]]; then echo "错误：域名不能为空。"; return 1; fi

    # 检查 Caddy 是否已安装
    if [ ! -f "${CADDY_BIN}" ]; then
        echo "错误：未找到 Caddy (${CADDY_BIN})。请先执行安装选项 (1)。"
        return 1
    fi

    stop_caddy # 停止当前服务

    create_caddyfile "$new_domain" # 使用新域名创建配置文件
    start_caddy                   # 使用现有 caddy 二进制文件启动

    echo "--- 配置修改完成 ---"
    echo "域名已更新为: ${new_domain}"
    echo "用户: ${AUTH_USER}"
    echo "密码: ${AUTH_PASS}"
    echo "NaiveProxy URL 示例: https://${AUTH_USER}:${AUTH_PASS}@${new_domain}"
    echo "Caddy 已使用新配置在后台启动。"
    echo "--------------------"
}

# 函数：卸载
uninstall_caddy() {
    read -p "确定要停止 Caddy 并删除 ${CADDY_BIN} 和 ${CADDY_CONFIG} 吗？(y/N): " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        stop_caddy
        echo "正在删除文件..."
        rm -f "${CADDY_BIN}" "${CADDY_CONFIG}"
        # 可选：删除 Caddy 数据 rm -rf "${INSTALL_DIR}/.local/share/caddy" "${INSTALL_DIR}/.config/caddy"
        echo "--- 卸载完成 ---"
    else
        echo "操作已取消。"
    fi
}

# --- 主程序 ---
clear
echo "NaiveProxy (Caddy) 管理脚本"
echo "--------------------------"
echo "1. 安装 / 更新 NaiveProxy"
echo "2. 修改配置 (仅更新域名和重启)"
echo "3. 卸载 NaiveProxy"
echo "--------------------------"
read -p "请输入选项编号: " choice

case "$choice" in
    1) install_or_update ;;
    2) modify_config ;;
    3) uninstall_caddy ;;
    *) echo "无效选项。" ;;
esac

exit 0
