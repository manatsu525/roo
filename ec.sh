read -p "input domain:" domain

[[ ! -a xray ]] && wget -O xray.zip https://github.com/manatsu525/roo/releases/download/1/Xray-linux-64.zip && unzip xray.zip

./xray tls cert -ca -domain=${domain} -name=KUMA -org=KUMA -expire=87600h -file=./
mv _cert.pem plugin.crt
mv _key.pem plugin.key
rm -rf *.pem
