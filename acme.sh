#!/bin/bash
cd /root
apt update -y
apt install socat -y
wget -qO- https://get.acme.sh|bash
read -p "input domain:" dom

/root/.acme.sh/acme.sh --set-default-ca  --server letsencrypt

/root/.acme.sh/acme.sh --register-account -m lineair069@gmail.com
/root/.acme.sh/acme.sh --issue -d ${dom} --standalone -k ec-256
/root/.acme.sh/acme.sh --install-cert -d ${dom} --fullchain-file /root/plugin.crt --key-file /root/plugin.key --ecc
