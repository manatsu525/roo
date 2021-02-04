cat > kcp <<-EOF
{
    "key": "tsukasakuro",
    "crypt": "salsa20",
    "mode": "fast",
    "mtu" : 512,
    "sndwnd": 2048,
    "rcvwnd": 2048,
    "datashard": 30,
    "parityshard": 15,
    "dscp": 0,
    "nocomp": true,
    "acknodelay": false,
    "nodelay": 0,
    "interval": 20,
    "resend": 0,
    "nc": 0,
    "sockbuf": 4194304,
    "keepalive": 10,
    "snmplog": "",
    "snmpperiod": 60,
    "tcp": false
}
EOF
