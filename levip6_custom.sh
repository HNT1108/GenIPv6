#!/bin/bash

# ======================== CONFIG =========================
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
PROXY_USER="proxyuser"
PROXY_PASS="proxypass"
FIRST_PORT=10000

# ======================== FUNCTIONS =========================
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_3proxy() {
    echo "[*] Installing 3proxy..."
    URL="https://raw.githubusercontent.com/ngochoaitn/multi_proxy_ipv6/main/3proxy-3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

gen_3proxy_cfg() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
auth strong
users $PROXY_USER:CL:$PROXY_PASS
$(awk -F "/" '{print "auth strong\\n" \
"allow " $1 "\\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\\n" \
"flush\\n"}' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "$PROXY_USER/$PROXY_PASS/$IP4/$port/$(gen64 $IP6)"
    done
}

bind_ipv6() {
    awk -F "/" '{print "ip -6 addr add "$5"/64 dev eth0"}' ${WORKDATA} | bash
}

gen_proxy_file() {
    awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA} > ${WORKDIR}/proxy.txt
}

create_service() {
    cat <<EOF >/etc/systemd/system/3proxy.service
[Unit]
Description=3proxy IPv6 Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable 3proxy
}

# ======================== MAIN =========================
echo "[*] Installing required packages..."
yum -y install gcc net-tools bsdtar zip curl >/dev/null

mkdir -p $WORKDIR && cd $WORKDIR

install_3proxy

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "[*] Detected IPv4: $IP4"
echo "[*] Detected IPv6 prefix: $IP6"

echo -n "Nhập số lượng proxy muốn tạo: "
read COUNT
LAST_PORT=$((FIRST_PORT + COUNT - 1))

gen_data > $WORKDATA
bind_ipv6
gen_3proxy_cfg
gen_proxy_file
create_service

echo "[*] Starting 3proxy..."
systemctl restart 3proxy

echo "[✅] Đã tạo $COUNT proxy thành công!"
echo "[📄] File proxy: $WORKDIR/proxy.txt"
