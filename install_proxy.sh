#!/bin/bash

echo "[🔧] Đang cài đặt gói cần thiết..."
yum install -y epel-release gcc make git zip curl net-tools wget >/dev/null

echo "[⬇️] Tải và biên dịch 3proxy mới nhất..."
rm -rf /opt/3proxy
git clone https://github.com/z3APA3A/3proxy.git /opt/3proxy >/dev/null 2>&1
cd /opt/3proxy
make -f Makefile.Linux >/dev/null
mkdir -p /usr/local/etc/3proxy/bin
cp bin/3proxy /usr/local/etc/3proxy/bin/

echo "[🧩] Tạo systemd service..."
cat <<EOF >/etc/systemd/system/3proxy.service
[Unit]
Description=3Proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload

echo "[🌐] Lấy địa chỉ IPv4 và prefix IPv6..."
IP4=$(curl -4 -s icanhazip.com)
IP6_PREFIX=$(curl -6 -s icanhazip.com | cut -d':' -f1-4)

read -p "[❓] Bạn muốn tạo bao nhiêu proxy? " COUNT

WORKDIR="/root/ipv6proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

# Random gen
gen64() {
    printf "$IP6_PREFIX:%x%x:%x%x:%x%x:%x%x\n" \
        $((RANDOM % 16)) $((RANDOM % 16)) \
        $((RANDOM % 16)) $((RANDOM % 16)) \
        $((RANDOM % 16)) $((RANDOM % 16)) \
        $((RANDOM % 16)) $((RANDOM % 16))
}

random_str() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c5
}

echo "[🔢] Sinh dữ liệu proxy..."
> $WORKDATA
for ((port=FIRST_PORT; port<LAST_PORT; port++)); do
    user="usr$(random_str)"
    pass="pwd$(random_str)"
    ip6=$(gen64)
    echo "$user/$pass/$IP4/$port/$ip6" >> $WORKDATA
done

echo "[🧩] Gán IPv6 vào interface eth0..."
while IFS=/ read -r user pass ip4 port ip6; do
    ip -6 addr add "$ip6/64" dev eth0 || echo "❌ Không thể gán $ip6"
done < <(cat $WORKDATA)

echo "[⚙️] Tạo file cấu hình 3proxy..."
cat <<EOF > /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong
users $(awk -F/ '{printf "%s:CL:%s ", $1, $2}' $WORKDATA)
$(awk -F/ '{printf "auth strong\nallow %s\nproxy -6 -n -a -p%s -i%s -e%s\nflush\n", $1, $4, $3, $5}' $WORKDATA)
EOF

echo "[📦] Khởi động 3proxy..."
systemctl enable 3proxy --now

echo "[📄] Tạo file proxy.txt..."
awk -F/ '{print $3 ":" $4 ":" $1 ":" $2}' $WORKDATA > proxy.txt

echo "[☁️] Upload proxy.txt lên transfer.sh..."
PASS=$(random_str)
zip --password $PASS proxy.zip proxy.txt
URL=$(curl --upload-file proxy.zip https://transfer.sh/proxy.zip)

echo
echo "[✅] Proxy đã sẵn sàng!"
echo "🔗 Link tải: $URL"
echo "🔑 Mật khẩu: $PASS"
