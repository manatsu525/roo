service(){
cat > gost.service <<-EOF
[Unit]
Description=gost(/etc/systemd/system/gost.service)
After=network.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/root/gost -L=ss+wss://AEAD_AES_256_GCM:passwd@:8443?path=/sumire
Restart=on-failure
RestartSec=10s
[Install]
WantedBy=multi-user.target
EOF
}


cd /root
echo -e "0.  install gost      1.  remove gost"
read -p "请选择（仅填数字）:" num
   
if [[ "${num}" == "0" ]];then
    rm -rf /root/gost*
    wget -O gost.gz "https://github.com/manatsu525/gost/releases/download/v2.11.1/gost-linux-amd64-2.11.1.gz" && gzip -d gost.gz && chmod +x gost

    service

    read -p "method:" value
    [[ -z ${value} ]] && value="wss"

    read -p "请输入端口（default:8443）:" port
    [[ -z ${port} ]] && port="8443"

    read -p "请输入密码:" passwd
    [[ -z ${passwd} ]] && passwd="sumire"
    
    read -p "请输入path:" path
    [[ -z ${path} ]] && path="sumire"
    
    sed -i "s/wss/${value}/g" brook.service
    sed -i "s/8443/${port}/g" brook.service
    sed -i "s/sumire/${path}/g" brook.service
    sed -i "s/passwd/${passwd}/g" brook.service

    mv gost.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable gost.service
    systemctl start gost
    systemctl status gost
elif [[ "${num}" == "1" ]];then
    killall gost
    systemctl stop gost
    systemctl disable gost.service
    rm -rf /root/gost* /root/install.log /etc/systemd/system/gost.service
fi
