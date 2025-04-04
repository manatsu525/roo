#!/bin/bash

# 脚本信息 (保持不变)
echo "=================================================="
echo "  Debian 系统 Shadowsocks + ShadowTLS 一键安装/卸载脚本 (交互式)"
echo "=================================================="
echo "  作者: Gemini (Google AI)"
echo "  日期: 2025年4月3日" # 更新日期
echo "=================================================="

# 定义默认变量 (保持不变)
SS_LOCAL_PORT="1080"
SS_SERVER_PORT="8388"
SS_PASSWORD="sumire" # Shadowsocks 密码，请务必修改
SS_METHOD_DEFAULT="chacha20-ietf-poly1305"
TLS_LISTEN_PORT="443"
TLS_FORWARD_ADDR="127.0.0.1"
TLS_HOST_DEFAULT="www.honda.com"
TLS_PASSWORD="sumire" # ShadowTLS 密码 (根据你的示例)

# 检查是否以 root 用户运行 (保持不变)
if [[ $EUID -ne 0 ]]; then
   echo "错误: 请以 root 用户运行此脚本。"
   exit 1
fi

# --- 添加卸载函数 ---
uninstall_ss_shadowtls() {
    echo "=================================================="
    echo "  开始卸载 Shadowsocks + ShadowTLS"
    echo "=================================================="

    # 1. 停止服务
    echo ">>> 正在停止 ShadowTLS 服务 (shadowtls.service)..."
    systemctl stop shadowtls || echo "警告: ShadowTLS 服务停止失败或未运行。"
    echo ">>> 正在停止 Shadowsocks 服务 (shadowsocks.service)..."
    systemctl stop shadowsocks || echo "警告: Shadowsocks 服务停止失败或未运行。"

    # 2. 禁用服务
    echo ">>> 正在禁用 ShadowTLS 服务..."
    systemctl disable shadowtls || echo "警告: ShadowTLS 服务禁用失败或未启用。"
    echo ">>> 正在禁用 Shadowsocks 服务..."
    systemctl disable shadowsocks || echo "警告: Shadowsocks 服务禁用失败或未启用。"

    # 3. 删除 systemd 服务文件 (使用原始文件名)
    echo ">>> 正在删除 systemd 服务文件..."
    rm -f /etc/systemd/system/shadowtls.service
    rm -f /etc/systemd/system/shadowsocks.service

    # 4. 重新加载 systemd 配置
    echo ">>> 正在重新加载 systemd 配置..."
    systemctl daemon-reload

    # 5. 删除 ShadowTLS 可执行文件 (使用原始路径)
    echo ">>> 正在删除 ShadowTLS 可执行文件 (/root/shadowtls)..."
    rm -f /root/shadowtls

    # 6. 删除 Shadowsocks 配置文件和目录 (使用原始路径)
    echo ">>> 正在删除 Shadowsocks 配置文件和目录 (/etc/shadowsocks-libev)..."
    rm -rf /etc/shadowsocks-libev

    # 7. 卸载 Shadowsocks-libev 软件包
    echo ">>> 正在卸载 shadowsocks-libev 软件包 (将提示是否删除配置文件)..."
    # 改用 remove 而非 purge，以防用户想保留系统级配置（虽然我们手动删了/etc/shadowsocks-libev）
    # 如果需要完全清除，可以用 apt purge -y shadowsocks-libev
    apt remove -y shadowsocks-libev
    echo ">>> 如果需要彻底清除 shadowsocks-libev 的系统级配置文件，请手动执行: apt purge shadowsocks-libev"


    # 8. 提示清理依赖
    echo ">>> 建议运行 'apt autoremove -y' 来清理不再需要的依赖包。"

    echo ""
    echo "=================================================="
    echo "  Shadowsocks + ShadowTLS 卸载完成！"
    echo "=================================================="
}
# --- 卸载函数结束 ---


# --- 交互选择安装或卸载 ---
echo ""
echo "请选择要执行的操作:"
echo "  1) 安装 Shadowsocks + ShadowTLS (默认)"
echo "  2) 卸载 Shadowsocks + ShadowTLS"
read -p "请输入选项编号 (按 Enter 默认执行安装): " choice

case "$choice" in
    2)
        # 执行卸载
        uninstall_ss_shadowtls
        ;;
    1|*) # 选项 1 或 其他输入 (包括直接回车) 都执行安装
        if [[ "$choice" != "1" && "$choice" != "" ]]; then
            echo "无效输入，执行默认操作：安装。"
        fi
        echo ">>> 即将执行安装流程..."
        echo ""

        # --- 原来的安装代码开始 (保持不变) ---
        # 更新软件包列表
        echo "正在更新软件包列表..."
        apt update

        # 安装 Shadowsocks-libev
        echo "正在安装 Shadowsocks-libev..."
        apt install -y shadowsocks-libev
        systemctl disable --now shadowsocks-libev.service

        # 选择 Shadowsocks 加密方式
        echo ""
        echo "请选择 Shadowsocks 加密方式 (AEAD):"
        echo "1. aes-128-gcm"
        echo "2. aes-192-gcm"
        echo "3. aes-256-gcm"
        echo "4. chacha20-ietf-poly1305 (默认)"
        read -p "请输入选项编号 (按 Enter 使用默认): " ss_method_choice

        case "$ss_method_choice" in
            1) SS_METHOD="aes-128-gcm" ;;
            2) SS_METHOD="aes-192-gcm" ;;
            3) SS_METHOD="aes-256-gcm" ;;
            4) SS_METHOD="$SS_METHOD_DEFAULT" ;;
            "") SS_METHOD="$SS_METHOD_DEFAULT" ;;
            *) echo "无效的选项，使用默认加密方式: $SS_METHOD_DEFAULT"
               SS_METHOD="$SS_METHOD_DEFAULT" ;;
        esac

        echo "使用的 Shadowsocks 加密方式: $SS_METHOD"
        echo ""

        # 输入 TLS Host
        read -p "请输入 TLS Host (按 Enter 使用默认: $TLS_HOST_DEFAULT): " tls_host_input
        if [ -z "$tls_host_input" ]; then
            TLS_HOST="$TLS_HOST_DEFAULT"
        else
            TLS_HOST="$tls_host_input"
        fi

        echo "使用的 TLS Host: $TLS_HOST"
        echo ""

        # 配置 Shadowsocks (监听本地端口)
        echo "正在配置 Shadowsocks (监听本地端口)..."
        mkdir -p /etc/shadowsocks-libev
        cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server": "0.0.0.0",
    "server_port": $SS_SERVER_PORT,
    "local_port": $SS_LOCAL_PORT,
    "password": "$SS_PASSWORD",
    "method": "$SS_METHOD",
    "timeout": 600
}
EOF

        # 下载并配置 ShadowTLS
        echo "正在下载并配置 ShadowTLS..."
        cd /root/
        if ! wget -O shadowtls https://github.com/manatsu525/roo/releases/download/1/shadow-tls-x86_64-unknown-linux-musl; then
             echo "错误：下载 ShadowTLS 失败！请检查网络或提供的 URL。"
             echo "你可以尝试从 https://github.com/ihciah/shadow-tls/releases 获取最新的下载链接并修改脚本。"
             exit 1
        fi
        chmod +x shadowtls

        # 创建 Shadowsocks 服务文件 (使用原始文件名 shadowsocks.service)
        echo "正在创建 Shadowsocks 服务文件..."
        cat > /etc/systemd/system/shadowsocks.service <<EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
User=nobody
Group=nobody 
Type=simple
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks-libev/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        # 创建 ShadowTLS 服务文件 (使用原始文件名 shadowtls.service 和原始参数格式)
        echo "正在创建 ShadowTLS 服务文件..."
        cat > /etc/systemd/system/shadowtls.service <<EOF
[Unit]
Description=ShadowTLS Forwarder
After=network.target
Wants=network-online.target

[Service]
User=root
Type=simple
ExecStart=/root/shadowtls --v3 server --listen [::]:${TLS_LISTEN_PORT} --server 127.0.0.1:${SS_SERVER_PORT} --tls ${TLS_HOST}:443 --password ${TLS_PASSWORD}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        # 重新加载 systemd 配置
        echo "正在重新加载 systemd 配置..."
        systemctl daemon-reload

        # 启用并启动 Shadowsocks 服务
        echo "正在启用并启动 Shadowsocks 服务..."
        systemctl enable shadowsocks
        systemctl restart shadowsocks # 使用 restart 确保加载新配置

        # 启用并启动 ShadowTLS 服务
        echo "正在启用并启动 ShadowTLS 服务..."
        systemctl enable shadowtls
        systemctl restart shadowtls # 使用 restart 确保加载新配置

        # 检查 Shadowsocks 服务状态 (保持原始方式)
        echo "正在检查 Shadowsocks 服务状态..."
        systemctl status shadowsocks

        # 检查 ShadowTLS 服务状态 (保持原始方式)
        echo "正在检查 ShadowTLS 服务状态..."
        systemctl status shadowtls

        echo "=================================================="
        echo "  Shadowsocks + ShadowTLS 安装完成！"
        echo "=================================================="
        echo "  请确保你已将以下信息配置到你的客户端："
        echo "  服务器地址: <你的服务器IP或域名>" # 提醒用户需要填写真实IP
        echo "  服务器端口: $TLS_LISTEN_PORT"
        echo "  密码 (ShadowTLS): $TLS_PASSWORD"
        echo "  SNI/Host: $TLS_HOST"
        echo "---"
        echo "  以下为 Shadowsocks 内部配置 (通常 ShadowTLS 客户端会自动处理):"
        echo "  密码 (Shadowsocks): $SS_PASSWORD"
        echo "  加密方式: $SS_METHOD"
        echo "=================================================="
        echo "  Shadowsocks 服务内部监听在 127.0.0.1:$SS_SERVER_PORT (由 ShadowTLS 转发)"
        echo "  ShadowTLS 服务监听在 [::]:$TLS_LISTEN_PORT 并转发到 127.0.0.1:$SS_SERVER_PORT"
        echo "=================================================="
        # --- 原来的安装代码结束 ---
        ;;
esac

exit 0
