#!/bin/bash

systemctl stop trojan
systemctl stop caddy
systemctl stop xray
systemctl disable trojan
systemctl disable caddy
systemctl disable xray
rm -rf /etc/systemd/system/caddy.service /etc/systemd/system/trojan.service /etc/systemd/system/xray.service /root/caddy* /root/trojan* /root/xray* /root/Caddyfile /root/example
systemctl daemon-reload
apt purge nginx -y
apt autoremove -y
