read -p "input domain:" domain
wget -O xray.zip https://github.com/manatsu525/roo/releases/download/1/Xray-linux-64.zip
unzip xray.zip
./xray tls cert -ca -domain=${domain} -name=KUMA -org=KUMA -expire=87600h -file=./
openssl x509 -in _cert.pem -out plugin.crt
openssl ec -in _key.pem -out plugin.key
rm -rf xray* *.pem
