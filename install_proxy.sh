#!/bin/bash

set -e

echo "[🔧] Cài đặt gói cần thiết..."
dnf install -y git gcc make curl unzip wget net-tools iproute iptables > /dev/null

echo "[⬇️] Tải và biên dịch 3proxy mới nhất..."
cd /opt
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux
mkdir -p /usr/local/etc/3proxy/bin
cp src/3proxy /usr/local/etc/3proxy/bin/

echo "[📁] Tạo thư mục làm việc..."
WORKDIR="/home/proxy-installer"
mkdir -p $WORKDIR
WORKDATA="$WORKDIR/data.txt"

echo "[🌐] Lấy địa chỉ IPv4 & Prefix IPv6..."
IP4=$(curl -4 -s icanhazip.com)
IP6_PREFIX=$(curl -6 -s icanhazip.com | cut -d ':' -f1-4)

read -p "[❓] Bạn muốn tạo bao nhiêu proxy? " COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT - 1))

echo "[🔢] Tạo dữ liệu proxy..."
gen64() {
    hextet() {
        printf "%x%x" $((RANDOM % 16)) $((RANDOM % 16))
    }
    echo "${IP6_PREFIX}:$(hextet):$(hextet):$(hextet):$(hextet)"
}

random() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c5
}

> $WORKDATA

for ((port=FIRST_PORT; port<=LAST_PORT; port++)); do
    USER="usr$(random)"
    PASS="pass$(random)"
    IPV6=$(gen64)
    echo "$USER/$PASS/$IP4/$port/$IPV6" >> $WORKDATA
done

echo "[🧩] Gán IPv6 vào interface eth0..."
awk -F '/' '{print "ip -6 addr add "$5"/64 dev eth0"}' $WORKDATA | bash

echo "[⚙️] Tạo file cấu hình 3proxy..."
cat <<EOF > /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 2000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong
users $(awk -F '/' '{printf "%s:CL:%s ", $1, $2}' $WORKDATA)
EOF

awk -F '/' '{
    print "auth strong"
    print "allow " $1
    print "proxy -6 -n -a -p" $4 " -i" $3 " -e" $5
    print "flush\n"
}' $WORKDATA >> /usr/local/etc/3proxy/3proxy.cfg

echo "[📦] Tạo systemd service cho 3proxy..."
cat <<EOF > /etc/systemd/system/3proxy.service
[Unit]
Description=3proxy proxy server
After=network.target

[Service]
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "[🚀] Khởi động 3proxy..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

echo "[📄] Xuất danh sách proxy..."
awk -F '/' '{print $3 ":" $4 ":" $1 ":" $2}' $WORKDATA > $WORKDIR/proxy.txt
echo "[✅] Đã tạo $COUNT proxy thành công!"
echo "[📄] File proxy: $WORKDIR/proxy.txt"
