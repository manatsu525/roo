#!/bin/bash

read -p "input domain:" domain
openssl genrsa -out server.key 4096
wait
openssl req -new -x509 -days 3650 -key server.key -out server.crt -subj "/C=JP/ST=TOKYO/L=TOKYO/O=KUMA/OU=KUMA/CN=${domain}"

