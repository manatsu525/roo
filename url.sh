#!/bin/bash
vmess="vmess://$(cat /root/vmess_qr.json | base64 -w 0)"
echo $vmess
