#!/bin/bash

service(){
cat > brook.service <<-EOF
[Unit]
Description=Brook(/etc/systemd/system/brook.service)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/root/brook wsserver -l value:port -p passwd
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
}


cd /root
echo -e "0.  install brook      1.  remove brook"
read -p "请选择（仅填数字）:" num
   
if [[ "${num}" == "0" ]];then
    rm -rf /root/brook*
    wget https://github.com/manatsu525/brook/releases/download/v20200501/brook
    chmod +x brook

    service

    read -p "请输入监听地址（default:0.0.0.0）:" value
    [[ -z ${value} ]] && value="0.0.0.0"

    read -p "请输入端口（default:8080）:" port
    [[ -z ${port} ]] && port="8080"

    read -p "请输入密码:" passwd
    [[ -z ${passwd} ]] && passwd="tsukasakuro"

    sed -i "s/value/${value}/g" brook.service
    sed -i "s/port/${port}/g" brook.service
    sed -i "s/passwd/${passwd}/g" brook.service

    mv brook.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable brook.service
    systemctl start brook
    systemctl status brook
elif [[ "${num}" == "1" ]];then
    killall brook
    systemctl stop brook
    systemctl disable brook.service
    rm -rf /root/brook* /root/install.log /etc/systemd/system/brook.service
fi
