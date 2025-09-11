#!/usr/bin/env bash
# Xray VLESS+Reality 一键脚本（Debian）
# 功能：安装、卸载、显示URL、查看状态与日志
# 下载来源：https://github.com/manatsu525/roo/releases/download/1/xray.zip

set -e

XRAY_ZIP_URL="https://github.com/manatsu525/roo/releases/download/1/xray.zip"
XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/etc/xray"
XRAY_CONF="$XRAY_DIR/config.json"
XRAY_SVC="/etc/systemd/system/xray.service"
META_FILE="$XRAY_DIR/meta.env"   # 保存安装参数与生成内容

color() { echo -e "\033[$1m$2\033[0m"; }
ok()    { color "32" "[OK] $1"; }
warn()  { color "33" "[WARN] $1"; }
err()   { color "31" "[ERR] $1" >&2; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "请以 root 身份运行。"
    exit 1
  fi
}

ensure_deps() {
  apt-get update -y
  apt-get install -y unzip curl
}

public_ip() {
  # 优先公网识别，降级为本机IP
  ip=$(curl -s --max-time 3 https://api.ipify.org || true)
  if [ -z "$ip" ]; then
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')
  fi
  echo "$ip"
}

gen_short_id() {
  # Reality 建议 8~16 位十六进制
  head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

write_service() {
cat > "$XRAY_SVC" <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=$XRAY_BIN run -c $XRAY_CONF
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

install_xray() {
  need_root
  ensure_deps
  mkdir -p "$XRAY_DIR"
  cd /tmp

  ok "下载 Xray..."
  curl -fsSL "$XRAY_ZIP_URL" -o xray.zip
  rm -f xray && rm -rf xray_unzip
  mkdir xray_unzip
  unzip -o xray.zip -d xray_unzip >/dev/null
  # 兼容未知结构：寻找可执行 xray
  XR_BIN_FOUND=$(find xray_unzip -type f -name "xray" | head -n1 || true)
  if [ -z "$XR_BIN_FOUND" ]; then
    err "压缩包内未找到 xray 可执行文件。"
    exit 1
  fi
  install -m 755 "$XR_BIN_FOUND" "$XRAY_BIN"
  ok "Xray 已安装到 $XRAY_BIN"

  # 交互获取参数
  read -rp "请输入监听端口（建议 443）: " PORT
  PORT=${PORT:-443}
  read -rp "请输入伪装网站域名（SNI/回源，如 www.cloudflare.com）: " SNI
  if [ -z "$SNI" ]; then
    err "伪装网站域名不能为空。"
    exit 1
  fi

  # 生成密钥、UUID、ShortID
  ok "生成 Reality 密钥对..."
  KEY_JSON=$($XRAY_BIN x25519)
  PRIVATE_KEY=$(echo "$KEY_JSON" | awk -F': ' '/PrivateKey/ {print $2}')
  PUBLIC_KEY=$(echo "$KEY_JSON"  | awk -F': ' '/Password/  {print $2}')
  UUID=$(cat /proc/sys/kernel/random/uuid)
  SHORT_ID=$(gen_short_id)

  # 写入配置
cat > "$XRAY_CONF" <<EOF
{
    "log": {
    "loglevel": "debug"                  
  },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": $PORT,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID", 
                        "flow": "xtls-rprx-vision" 
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false, 
                    "target": "$SNI:443", 
                    "xver": 0, 
                    "serverNames": [
                        "$SNI"
                    ],
                    "privateKey": "$PRIVATE_KEY",
                    "minClientVer": "", 
                    "maxClientVer": "", 
                    "maxTimeDiff": 0, 
                    "shortIds": [ 
                        "$SHORT_ID"
                    ],
                    "mldsa65Seed": ""
                    }
                }
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
  ]
}
EOF

  # 保存元数据
cat > "$META_FILE" <<EOF
UUID="$UUID"
PORT="$PORT"
SNI="$SNI"
PRIVATE_KEY="$PRIVATE_KEY"
PUBLIC_KEY="$PUBLIC_KEY"
SHORT_ID="$SHORT_ID"
EOF
  chmod 600 "$META_FILE"

  write_service
  systemctl enable --now xray

  sleep 1
  systemctl is-active --quiet xray && ok "Xray 已启动" || { err "Xray 启动失败，使用查看日志菜单排查。"; }

  IP=$(public_ip)
  URL="vless://$UUID@$IP:$PORT?type=tcp&security=reality&pbk=$PUBLIC_KEY&fp=chrome&sni=$SNI&sid=$SHORT_ID&flow=xtls-rprx-vision#$SNI"
  echo
  ok "安装完成！以下为连接 URL："
  echo "$URL"
  echo
}

uninstall_xray() {
  need_root
  systemctl disable --now xray >/dev/null 2>&1 || true
  rm -f "$XRAY_SVC"
  systemctl daemon-reload
  rm -f "$XRAY_BIN"
  rm -rf "$XRAY_DIR"
  ok "已卸载 Xray 并移除配置。"
}

show_url() {
  if [ ! -f "$META_FILE" ]; then
    err "未检测到已安装的元数据：$META_FILE"
    exit 1
  fi
  # shellcheck source=/dev/null
  . "$META_FILE"
  IP=$(public_ip)
  URL="vless://$UUID@$IP:$PORT?type=tcp&security=reality&pbk=$PUBLIC_KEY&fp=chrome&sni=$SNI&sid=$SHORT_ID&flow=xtls-rprx-vision#$SNI"
  echo "$URL"
}

show_status() {
  systemctl status xray --no-pager
}

show_logs() {
  journalctl -u xray -e --no-pager
}

menu() {
  echo "============================"
  echo " Xray VLESS + Reality 管理"
  echo "============================"
  echo "1) 安装/重装"
  echo "2) 卸载"
  echo "3) 显示连接 URL"
  echo "4) 查看 Xray 状态"
  echo "5) 查看 Xray 日志"
  echo "0) 退出"
  echo "----------------------------"
  read -rp "请选择: " ans
  case "$ans" in
    1) install_xray ;;
    2) uninstall_xray ;;
    3) show_url ;;
    4) show_status ;;
    5) show_logs ;;
    0) exit 0 ;;
    *) warn "无效选项";;
  esac
}

main() {
  need_root
  while true; do
    menu
    echo
  done
}

main
