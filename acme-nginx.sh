#!/bin/bash
cd /root
apt update -y
apt install socat -y
wget -qO- https://get.acme.sh|bash

/root/.acme.sh/acme.sh --issue -d ${domain} --nginx -k ec-256
/root/.acme.sh/acme.sh --install-cert -d ${domain} --fullchain-file /root/plugin.crt --key-file /root/plugin.key --ecc
systemctl restart nginx
