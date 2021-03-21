#!/bin/bash
systemctl disable trojan
systemctl disable caddy
rm -rf /etc/systemd/system/caddy.service /etc/systemd/system/trojan.service /root/caddy* /root/trojan* /root/Caddyfile /root/example
systemctl daemon-reload
