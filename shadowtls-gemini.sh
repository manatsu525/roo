#!/bin/bash

# 脚本信息
echo "=================================================="
echo "  Debian 系统 Shadowsocks + ShadowTLS 一键安装脚本 (交互式配置)"
echo "=================================================="
echo "  作者: Gemini (Google AI)"
echo "  日期: 2025年3月29日"
echo "=================================================="

# 定义默认变量
SS_LOCAL_PORT="1080" # Shadowsocks 本地监听端口
SS_SERVER_PORT="8388" # Shadowsocks 服务器端口 (内部端口)
SS_PASSWORD="sumire" # Shadowsocks 密码，请务必修改
SS_METHOD_DEFAULT="chacha20-ietf-poly1305" # Shadowsocks 默认加密方式
TLS_LISTEN_PORT="443" # ShadowTLS 监听端口 (外部端口)
TLS_FORWARD_ADDR="127.0.0.1" # ShadowTLS 转发地址 (Shadowsocks 本地地址)
TLS_HOST_DEFAULT="www.honda.com" # 默认 TLS Host
TLS_PASSWORD="sumire" # ShadowTLS 密码 (根据你的示例)

# 检查是否以 root 用户运行
if [[ $EUID -ne 0 ]]; then
   echo "错误: 请以 root 用户运行此脚本。"
   exit 1
fi

# 更新软件包列表
echo "正在更新软件包列表..."
apt update

# 安装 Shadowsocks-libev
echo "正在安装 Shadowsocks-libev..."
apt install -y shadowsocks-libev

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
wget -O shadowtls https://github.com/manatsu525/roo/releases/download/1/shadow-tls-x86_64-unknown-linux-musl
chmod +x shadowtls

# 创建 Shadowsocks 服务文件
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

# 创建 ShadowTLS 服务文件
echo "正在创建 ShadowTLS 服务文件..."
cat > /etc/systemd/system/shadowtls.service <<EOF
[Unit]
Description=ShadowTLS Forwarder
After=network.target
Wants=network-online.target

[Service]
User=root
Type=simple
ExecStart=/root/shadowtls server --listen [::]:${TLS_LISTEN_PORT} --server 127.0.0.1:${SS_SERVER_PORT} --tls ${TLS_HOST}:443 --password ${TLS_PASSWORD} --v3
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
systemctl start shadowsocks

# 启用并启动 ShadowTLS 服务
echo "正在启用并启动 ShadowTLS 服务..."
systemctl enable shadowtls
systemctl start shadowtls

# 检查 Shadowsocks 服务状态
echo "正在检查 Shadowsocks 服务状态..."
systemctl status shadowsocks

# 检查 ShadowTLS 服务状态
echo "正在检查 ShadowTLS 服务状态..."
systemctl status shadowtls

echo "=================================================="
echo "  Shadowsocks + ShadowTLS 安装完成！"
echo "=================================================="
echo "  请确保你已将以下信息配置到你的客户端："
echo "  服务器地址: $TLS_HOST"
echo "  服务器端口: $TLS_LISTEN_PORT"
echo "  协议 (Protocol): origin 或 tls (取决于你的客户端)"
echo "  密码 (Shadowsocks): $SS_PASSWORD"
echo "  加密方式: $SS_METHOD"
echo "=================================================="
echo "  Shadowsocks 服务监听在 127.0.0.1:$SS_SERVER_PORT"
echo "  ShadowTLS 服务监听在 [::]:$TLS_LISTEN_PORT 并转发到 127.0.0.1:$SS_SERVER_PORT"
echo "  ShadowTLS 密码: $TLS_PASSWORD"
echo "=================================================="
