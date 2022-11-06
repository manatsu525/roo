#!/bin/bash

systemctl stop trojan
systemctl stop caddy
systemctl stop xray
systemctl stop shadowtls
systemctl disable trojan
systemctl disable caddy
systemctl disable xray
systemctl disable shadowtls
systemctl stop v2ray && systemctl disable v2ray

#systemctl stop hysteria
#systemctl disable hysteria
#rm -rf /etc/systemd/system/hysteria.service /root/hysteria
rm -rf /etc/systemd/system/caddy.service /etc/systemd/system/trojan.service /etc/systemd/system/xray.service /etc/systemd/system/v2ray.service /etc/systemd/system/shadowtls.service /root/v2ray* /root/caddy* /root/trojan* /root/xray* /root/Caddyfile /root/example /root/shadowtls
systemctl daemon-reload
apt purge nginx -y
apt autoremove -y
