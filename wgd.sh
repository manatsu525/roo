#!/bin/bash
cd /root

echo -e "0.install  1.remove"
read -p "请选择（仅填数字）:" num

case ${num} in
	0 ) echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list 
      printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable 
      apt update -y
      apt install wireguard-tools --no-install-recommends -y
      
      wget https://github.com/manatsu525/roo/releases/download/1/wireguard-go
      chmod +x wireguard-go
      ./wireguard-go wg
      
      wg genkey | tee sprivatekey | wg pubkey > spublickey
      wg genkey | tee cprivatekey | wg pubkey > cpublickey
      
      cat >/etc/wireguard/wg0.conf <<-EOF
      [Interface] 
      Address = 10.123.0.2 
      PrivateKey = $(cat sprivatekey) 
      ListenPort = 19018

      [Peer] 
      PublicKey = $(cat cpublickey) 
      AllowedIPs = 10.123.0.1/32 
      Endpoint = 198.51.100.1:19018
EOF
      
      echo "cprivatekey:$(cat cprivatekey)"
      echo "spublickey:$(cat spublickey)"
  ;;
  1 ) apt purge wireguard-tools -y
      killall wireguard-go
  ;;
esac

