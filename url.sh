#!/bin/bash
vmess="vmess://$(cat /etc/v2ray/vmess_qr.json | base64 -w 0)"
echo $vmess
