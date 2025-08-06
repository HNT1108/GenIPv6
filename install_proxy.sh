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

# Tự động lấy interface và prefix IPv6 hợp lệ
IFACE=$(ip -6 addr | awk '/inet6/ && /scope global/ {print $NF; exit}')
FULL_IP6=$(ip -6 addr show dev "$IFACE" | awk '/inet6/ && /global/ {print $2; exit}')
IP6_PREFIX=$(echo $FULL_IP6 | cut -d':' -f1-4)

if [[ -z "$IP6_PREFIX" ]]; then
    echo "❌ Không thể lấy prefix IPv6. Kiểm tra kết nối IPv6."
    exit 1
fi

read -p "[❓] Bạn muốn tạo bao nhiêu proxy? " COUNT

WORKDIR="/root/ipv6proxy"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

gen64() {
    # Sinh ra địa chỉ IPv6 dạng PREFIX:x:x:x:x
    printf "$IP6_PREFIX:%x:%x:%x:%x\n" \
        $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536))
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

echo "[🧩] Gán IPv6 vào interface $IFACE..."
while IFS=/ read -r user pass ip4 port ip6; do
    ip -6 addr add "$ip6/64" dev $IFACE || echo "❌ Không thể gán $ip6"
done < $WORKDATA

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
zip --password "$PASS" proxy.zip proxy.txt >/dev/null

# Kiểm tra kết nối transfer.sh
curl -s https://transfer.sh/ --head >/dev/null
if [[ $? -eq 0 ]]; then
    URL=$(curl --upload-file proxy.zip https://transfer.sh/proxy.zip)
    echo
    echo "[✅] Proxy đã sẵn sàng!"
    echo "🔗 Link tải: $URL"
    echo "🔑 Mật khẩu: $PASS"
else
    echo "❌ Không thể kết nối tới transfer.sh. Vui lòng thử lại sau."
fi
