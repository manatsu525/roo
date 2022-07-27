#!/bin/bash

read -p "domain:" domain

cd /root
wget https://dl.google.com/go/go1.18.1.linux-amd64.tar.gz
tar -zxvf go1.18.1.linux-amd64.tar.gz -C /usr/local/bin/

echo "export GOROOT=/usr/local/bin/go" >> ~/.bashrc
echo "export GOPATH=$HOME/go" >> ~/.bashrc
echo "export PATH=$GOROOT/bin:$PATH" >> ~/.bashrc
echo "export PATH=$PATH:$GOPATH/bin" >> ~/.bashrc
echo "export GO111MODULE=on" >> ~/.bashrc
source ~/.bashrc
