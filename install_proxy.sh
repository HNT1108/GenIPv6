#!/bin/bash

set -e

echo "[🔧] Đang cài đặt gói cần thiết..."
dnf install -y git curl gcc make net-tools zip > /dev/null

echo "[⬇️] Tải và biên dịch 3proxy mới nhất..."
cd /opt || exit 1
rm -rf 3proxy
git clone https://github.com/z3APA3A/3proxy.git
cd 3proxy
make -f Makefile.Linux
mkdir -p /usr/local/etc/3proxy/bin
cp bin/3proxy /usr/local/etc/3proxy/bin/

echo "[🛠️] Tạo systemd service cho 3proxy..."
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
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

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p "$WORKDIR"

# Random helpers
random() {
	tr -dc A-Za-z0-9 </dev/urandom | head -c 5
	echo
}

# Fix IPv6 prefix gen (must return a full /64 addr)
gen64() {
	suffix=$(hexdump -n 8 -e '/1 ":%02X"' /dev/urandom)
	echo "$1${suffix,,}"
}

echo "[🌐] Lấy địa chỉ IPv4 và prefix IPv6..."
IP4=$(curl -4 -s icanhazip.com)
IP6_PREFIX=$(curl -6 -s icanhazip.com | cut -f1-4 -d':' | tr -d '\n')
IP6_PREFIX="${IP6_PREFIX}:"

echo "[❓] Bạn muốn tạo bao nhiêu proxy?"
read -r COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT - 1))

echo "[🔢] Sinh dữ liệu proxy..."
seq $FIRST_PORT $LAST_PORT | while read -r port; do
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 "$IP6_PREFIX")"
done > "$WORKDATA"

echo "[🧩] Gán IPv6 vào interface eth0..."
awk -F "/" '{print $5}' "$WORKDATA" | while read -r ip; do
    ip -6 addr add "$ip/64" dev eth0 || true
done

echo "[🔁] Cấu hình iptables..."
awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' "$WORKDATA" > "${WORKDIR}/boot_iptables.sh"
chmod +x "${WORKDIR}/boot_iptables.sh"
bash "${WORKDIR}/boot_iptables.sh"

echo "[⚙️] Tạo file cấu hình cho 3proxy..."
cat > /usr/local/etc/3proxy/3proxy.cfg <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" '{printf "%s:CL:%s ", $1, $2}' "$WORKDATA")

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5 "\n" \
"flush\n"}' "$WORKDATA")
EOF

echo "[💾] Ghi file proxy.txt..."
awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' "$WORKDATA" > "$WORKDIR/proxy.txt"

echo "[☁️] Upload proxy.txt lên transfer.sh..."
ZIPPASS=$(random)
cd "$WORKDIR" || exit
zip --password "$ZIPPASS" proxy.zip proxy.txt > /dev/null
UPLOAD_URL=$(curl --silent --upload-file proxy.zip https://transfer.sh/proxy.zip || true)

echo
echo "✅ Proxy đã được tạo thành công!"
echo "📄 File: proxy.txt (IP:PORT:USER:PASS)"
echo "🔗 Link tải: $UPLOAD_URL"
echo "🔐 Mật khẩu giải nén: $ZIPPASS"

echo "[🚀] Bật dịch vụ 3proxy..."
systemctl enable --now 3proxy

