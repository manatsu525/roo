#!/bin/bash
read -p "domain:" domain
read -p "port:" port
read -p "path:(default /natsu)" path
[[ -z ${path} ]] && path="/natsu"
read -p "page:(default https://www.morinagamilk.co.jp)" page
[[ -z ${page} ]] && page="https://www.morinagamilk.co.jp"

if [[ ! -e nico ]];then
  wget https://github.com/manatsu525/roo/releases/download/1/nico
  chmod +x ./nico
fi

./nico ${domain} ${page} ${domain}${path} http://127.0.0.1:${port} ${domain}/file /usr/downloads &
