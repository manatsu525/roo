#!/usr/bin/env bash
# natsu.sh - V2Ray/VLESS + Nginx (ws+tls, mkcp) interactive manager for Debian
# Author: you
# Requirements: Debian 10/11/12 (root), no firewall config (per request)

set -euo pipefail

V2RAY_URL="https://github.com/manatsu525/roo/releases/download/1/v2ray-linux-64.zip"
INSTALL_DIR="/usr/local/natsu"
BIN_DIR="/usr/local/bin"
CONF_DIR="/etc/natsu"
V2_CONF="/etc/natsu/v2ray.json"
META_CONF="/etc/natsu/natsu.conf"
SYSTEMD_UNIT="/etc/systemd/system/v2ray.service"
DOWNLOAD_DIR="/usr/downloads"
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABL="/etc/nginx/sites-enabled"
EMAIL_DEFAULT="lineair069@gmail.com"
WS_PATH="/natsu"
FILE_URI="/file"

bold() { echo -e "\e[1m$*\e[0m"; }
green() { echo -e "\e[32m$*\e[0m"; }
red()   { echo -e "\e[31m$*\e[0m"; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    red "请以 root 运行：sudo ./natsu.sh"
    exit 1
  fi
}

ensure_deps() {
  apt-get update -y
  apt-get install -y wget unzip jq uuid-runtime curl ca-certificates \
                     nginx certbot python3-certbot-nginx
}

ensure_dirs() {
  mkdir -p "$INSTALL_DIR" "$CONF_DIR" "$DOWNLOAD_DIR"
  chmod 755 "$DOWNLOAD_DIR"
}

install_v2ray_bin() {
  tmp="$(mktemp -d)"
  wget -O "$tmp/v2ray.zip" "$V2RAY_URL"
  unzip -o "$tmp/v2ray.zip" -d "$tmp"
  if [[ -f "$tmp/v2ray" ]]; then
    install -m 755 "$tmp/v2ray" "$BIN_DIR/v2ray"
  elif [[ -f "$tmp/v2ray-linux-64/v2ray" ]]; then
    install -m 755 "$tmp/v2ray-linux-64/v2ray" "$BIN_DIR/v2ray"
  else
    red "未在压缩包中找到 v2ray 可执行文件。"
    exit 1
  fi
  rm -rf "$tmp"
}

write_systemd() {
cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=V2Ray Service (natsu)
After=network.target

[Service]
Type=simple
ExecStart=$BIN_DIR/v2ray -config $V2_CONF
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

obtain_cert() {
  local domain="\$1"
  # use certbot with nginx installer (simplest); it will create a temp 80 vhost
  certbot --nginx -d "\$domain" -m "$EMAIL_DEFAULT" --agree-tos --redirect --non-interactive || true
}

gen_nginx_conf() {
  local domain="\$1"
  local ws_port="\$2"
  local site_conf="$NGINX_AVAIL/\$domain.conf"

cat > "\$site_conf" <<'NGX'
server {
    listen 80;
    listen [::]:80;
    server_name DOMAIN_PLACEHOLDER;
    # Certbot may keep http challenge here
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;

    ssl_certificate /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN_PLACEHOLDER/privkey.pem;

    # 安全与性能可再优化
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;

    # 伪装站：反代 www.honda.com
    location / {
        proxy_pass https://www.honda.com;
        proxy_set_header Host www.honda.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_ssl_server_name on;
    }

    # /file → 文件服务器
    location ^~ /file/ {
        alias /usr/downloads/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    # /natsu → WS 回源
    location /natsu {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:WS_PORT_PLACEHOLDER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
NGX

  sed -i "s/DOMAIN_PLACEHOLDER/\$domain/g" "\$site_conf"
  sed -i "s/WS_PORT_PLACEHOLDER/\$ws_port/g" "\$site_conf"
  ln -sf "\$site_conf" "$NGINX_ENABL/\$domain.conf"
  nginx -t
  systemctl reload nginx
}

setup_bimonthly_renew() {
  # 每两个月的 1 号 03:15 触发 renew（1,3,5,7,9,11）
  local cronf="/etc/cron.d/natsu-cert-renew"
  cat > "\$cronf" <<'CR'
# natsu: bimonthly certbot renew & reload
15 3 1 1,3,5,7,9,11 * root certbot renew --quiet && systemctl reload nginx || true
CR
}

save_meta() {
  # 统一保存元信息便于展示/修改
  mkdir -p "$(dirname "$META_CONF")"
  cat > "$META_CONF" <<EOF
mode=$MODE            # 1: vmess(ws+tls)+vmess(mkcp)  2: vless(ws+tls)
domain=$DOMAIN
ws_port=$WS_PORT
tls_port=443
mkcp_port=${MKCP_PORT:-0}
uuid=$UUID
mkcp_header=${MKCP_HEADER:-none}
mkcp_seed=${MKCP_SEED:-}
EOF
}

gen_v2_config_mode1() {
  # vmess + ws + tls  与  vmess + mkcp 共存
  # WS 入站走本地 127.0.0.1:$WS_PORT，由 Nginx TLS 回源
  cat > "$V2_CONF" <<EOF
{
  "inbounds": [
    {
      "port": $WS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "$UUID", "alterId": 0 }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH", "headers": { "Host": "$DOMAIN" } }
      }
    },
    {
      "port": $MKCP_PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [{ "id": "$UUID", "alterId": 0 }]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 20,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": { "type": "$MKCP_HEADER" },
          "seed": "$MKCP_SEED"
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
}

gen_v2_config_mode2() {
  # vless + ws + tls
  cat > "$V2_CONF" <<EOF
{
  "inbounds": [
    {
      "port": $WS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [{ "id": "$UUID" }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH", "headers": { "Host": "$DOMAIN" } }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom", "settings": {} }]
}
EOF
}

restart_services() {
  systemctl enable v2ray
  systemctl restart v2ray
  systemctl enable nginx
  systemctl restart nginx
}

show_links() {
  if [[ ! -f "$META_CONF" ]]; then
    red "未找到元配置：$META_CONF"
    return
  fi
  # shellcheck disable=SC1090
  source "$META_CONF"

  echo
  bold "==== 连接信息 ===="

  if [[ "$mode" == "1" ]]; then
    # vmess ws+tls
    vmess_ws_json=$(jq -n \
      --arg v "2" \
      --arg ps "natsu-vmess-ws" \
      --arg add "$domain" \
      --arg port "443" \
      --arg id "$uuid" \
      --arg aid "0" \
      --arg net "ws" \
      --arg type "none" \
      --arg host "$domain" \
      --arg path "$WS_PATH" \
      --arg tls "tls" \
      --arg sni "$domain" \
      '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, net:$net, type:$type, host:$host, path:$path, tls:$tls, sni:$sni}')
    vmess_ws_link="vmess://$(echo -n "$vmess_ws_json" | base64 -w 0)"

    # vmess mkcp
    vmess_kcp_json=$(jq -n \
      --arg v "2" \
      --arg ps "natsu-vmess-kcp" \
      --arg add "$domain" \
      --arg port "$mkcp_port" \
      --arg id "$uuid" \
      --arg aid "0" \
      --arg net "kcp" \
      --arg type "$mkcp_header" \
      --arg host "" \
      --arg path "" \
      --arg tls "" \
      '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, net:$net, type:$type, host:$host, path:$path, tls:$tls}')
    vmess_kcp_link="vmess://$(echo -n "$vmess_kcp_json" | base64 -w 0)"

    echo "VMess (WS+TLS): $vmess_ws_link"
    echo "VMess (mKCP):   $vmess_kcp_link"
    echo
    echo "提示：mKCP 客户端需在 kcp 设置里选择 headerType=$mkcp_header，并设置 seed=$mkcp_seed"
  else
    # vless ws+tls
    vless_link="vless://$uuid@$domain:443?encryption=none&type=ws&host=$domain&path=$(urlencode "$WS_PATH")&security=tls&sni=$domain#natsu-vless-ws"
    echo "VLESS (WS+TLS): $vless_link"
  fi

  echo
  echo "下载目录映射： https://$domain$FILE_URI → $DOWNLOAD_DIR"
  echo "伪装落地页：   https://$domain/  (反代 www.honda.com)"
}

# URL encode helper inside bash
urlencode() {
  local LANG=C i c e s="$1"
  for (( i=0; i<${#s}; i++ )); do
    c=${s:$i:1}
    case $c in
      [a-zA-Z0-9.~_-]) e="$c" ;;
      *) printf -v e '%%%02X' "'$c" ;;
    esac
    printf '%s' "$e"
  done
}

install_flow() {
  need_root
  ensure_deps
  ensure_dirs
  install_v2ray_bin
  write_systemd

  echo
  bold "选择模式："
  echo "  1) vmess+ws+tls 与 vmess+mkcp 共存"
  echo "  2) vless+ws+tls"
  read -rp "请输入 1 或 2: " MODE

  read -rp "请输入你的域名(已解析到此机): " DOMAIN
  read -rp "WS 本地监听端口(建议 10000-20000，默认 10086): " WS_PORT
  WS_PORT=${WS_PORT:-10086}

  UUID=$(uuidgen)

  if [[ "$MODE" == "1" ]]; then
    read -rp "mKCP 监听端口(UDP，默认 40000): " MKCP_PORT
    MKCP_PORT=${MKCP_PORT:-40000}
    echo "可选 mKCP 伪装类型：none / srtp / utp / wechat-video / dtls / wireguard"
    read -rp "mKCP 伪装类型(默认 wechat-video): " MKCP_HEADER
    MKCP_HEADER=${MKCP_HEADER:-wechat-video}
    read -rp "mKCP seed(任意字符串，默认 auto 随机): " MKCP_SEED
    MKCP_SEED=${MKCP_SEED:-"natsu-$(uuidgen | tr -d '-')"}
    gen_v2_config_mode1
  else
    gen_v2_config_mode2
  fi

  obtain_cert "$DOMAIN"
  gen_nginx_conf "$DOMAIN" "$WS_PORT"
  setup_bimonthly_renew
  save_meta
  restart_services

  green "安装完成。"
  show_links
}

modify_flow() {
  if [[ ! -f "$META_CONF" ]]; then red "未安装。"; exit 1; fi
  source "$META_CONF"

  echo
  bold "当前模式：$mode  域名：$domain"
  echo "1) 切换/重建配置"
  echo "2) 仅修改 WS 本地端口 (当前 $ws_port)"
  if [[ "$mode" == "1" ]]; then
    echo "3) 修改 mKCP 端口/伪装类型/seed (当前 $mkcp_port/$mkcp_header/$mkcp_seed)"
  fi
  read -rp "选择: " CH

  case "$CH" in
    1)
      install_flow
      ;;
    2)
      read -rp "新 WS 端口: " WS_PORT
      WS_PORT=${WS_PORT:-$ws_port}
      WS_PATH="$WS_PATH" DOMAIN="$domain" UUID="$uuid"
      if [[ "$mode" == "1" ]]; then
        MKCP_PORT=${mkcp_port} MKCP_HEADER=${mkcp_header} MKCP_SEED=${mkcp_seed}
        gen_v2_config_mode1
      else
        gen_v2_config_mode2
      fi
      gen_nginx_conf "$domain" "$WS_PORT"
      sed -i "s/^ws_port=.*/ws_port=$WS_PORT/" "$META_CONF"
      systemctl restart v2ray && systemctl reload nginx
      ;;
    3)
      if [[ "$mode" != "1" ]]; then red "当前不是模式1。"; exit 1; fi
      read -rp "新 mKCP 端口(回车保留 $mkcp_port): " MKCP_PORT
      MKCP_PORT=${MKCP_PORT:-$mkcp_port}
      read -rp "新 mKCP 伪装类型(回车保留 $mkcp_header): " MKCP_HEADER
      MKCP_HEADER=${MKCP_HEADER:-$mkcp_header}
      read -rp "新 mKCP seed(回车保留 $mkcp_seed): " MKCP_SEED
      MKCP_SEED=${MKCP_SEED:-$mkcp_seed}
      WS_PORT=${ws_port}
      DOMAIN="$domain" UUID="$uuid"
      gen_v2_config_mode1
      sed -i "s/^mkcp_port=.*/mkcp_port=$MKCP_PORT/" "$META_CONF"
      sed -i "s/^mkcp_header=.*/mkcp_header=$MKCP_HEADER/" "$META_CONF"
      sed -i "s/^mkcp_seed=.*/mkcp_seed=$MKCP_SEED/" "$META_CONF"
      systemctl restart v2ray
      ;;
    *)
      ;;
  esac

  green "修改完成。"
  show_links
}

uninstall_flow() {
  need_root
  echo
  bold "确认卸载？这将移除 V2Ray、Nginx 站点和 Nginx 包（证书将保留）。"
  read -rp "输入 YES 确认: " ok
  if [[ "$ok" != "YES" ]]; then echo "已取消"; exit 0; fi

  systemctl stop v2ray || true
  systemctl disable v2ray || true
  rm -f "$SYSTEMD_UNIT"
  systemctl daemon-reload

  rm -f "$V2_CONF" || true
  rm -f "$BIN_DIR/v2ray" || true
  rm -rf "$INSTALL_DIR" || true

  if [[ -f "$META_CONF" ]]; then
    source "$META_CONF" || true
    rm -f "$NGINX_ENABL/$domain.conf" "$NGINX_AVAIL/$domain.conf" || true
  fi

  # 移除 Nginx 包（仅保留证书目录 /etc/letsencrypt）
  systemctl stop nginx || true
  apt-get remove -y nginx nginx-common || true
  apt-get purge -y nginx nginx-common || true
  apt-get autoremove -y || true

  rm -f /etc/cron.d/natsu-cert-renew || true
  rm -rf "$CONF_DIR" || true

  green "卸载完成。证书已保留在 /etc/letsencrypt。"
}

menu() {
  bold "==== Natsu 管理脚本 ===="
  echo "1) 安装/重新安装"
  echo "2) 修改配置"
  echo "3) 显示链接(URL)"
  echo "4) 卸载并清理(Nginx+V2Ray)，保留证书"
  echo "5) 重启服务"
  echo "0) 退出"
  read -rp "选择: " ch
  case "$ch" in
    1) install_flow ;;
    2) modify_flow ;;
    3) show_links ;;
    4) uninstall_flow ;;
    5) systemctl restart v2ray && systemctl restart nginx && green "已重启";;
    0) exit 0 ;;
    *) echo "无效选项" ;;
  esac
}

main() {
  need_root
  menu
}

main "$@"
