#!/bin/bash

set -e

# ===== CONFIG =====
PROXY_COUNT=0
PROXY_PORT_START=10000
INSTALL_DIR="/opt/3proxy"
WORK_DIR="/opt/proxygen"
BIN_DIR="/usr/local/bin"
IPV6_INTERFACE="eth0"

# ===== FUNCTIONS =====
random() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c5
  echo
}

ip64() {
  printf "%x%x:%x%x" $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16))
}

gen_ipv6() {
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

gen_data() {
  for i in $(seq 0 $((PROXY_COUNT-1))); do
    port=$((PROXY_PORT_START+i))
    user="usr$(random)"
    pass="pass$(random)"
    ipv6=$(gen_ipv6 "$IPV6_PREFIX")
    echo "$user/$pass/$IPV4/$port/$ipv6"
  done > "$WORK_DIR/data.txt"
}

gen_config_3proxy() {
  cat > "$INSTALL_DIR/3proxy.cfg" <<EOF
daemon
maxconn 1000
auth strong
users $(awk -F"/" '{print $1":CL:"$2}' "$WORK_DIR/data.txt" | paste -sd" ")
$(awk -F"/" '{print "auth strong\nallow "$1"\nproxy -6 -n -a -p"$4" -i"$3" -e"$5"\nflush\n"}' "$WORK_DIR/data.txt")
EOF
}

gen_ifconfig_commands() {
  awk -F"/" -v iface="$IPV6_INTERFACE" '{print "ip -6 addr add "$5"/64 dev "iface}' "$WORK_DIR/data.txt" > "$WORK_DIR/assign_ipv6.sh"
  chmod +x "$WORK_DIR/assign_ipv6.sh"
}

gen_firewall_rules() {
  awk -F"/" '{print "firewall-cmd --permanent --add-port="$4"/tcp"}' "$WORK_DIR/data.txt" > "$WORK_DIR/firewall.sh"
  chmod +x "$WORK_DIR/firewall.sh"
}

gen_proxy_txt() {
  awk -F"/" '{print $3":"$4":"$1":"$2}' "$WORK_DIR/data.txt" > "$WORK_DIR/proxy.txt"
}

upload_to_transfersh() {
  PASS=$(random)
  zip -P "$PASS" -j "$WORK_DIR/proxy.zip" "$WORK_DIR/proxy.txt"
  URL=$(curl --silent --upload-file "$WORK_DIR/proxy.zip" "https://transfer.sh/proxy.zip")
  echo "[✅] Proxy upload thành công!"
  echo "🔗 Link tải: $URL"
  echo "🔐 Mật khẩu giải nén: $PASS"
}

install_requirements() {
  echo "[🔧] Đang cài đặt gói cần thiết..."
  dnf install -y git make gcc curl zip >/dev/null
}

install_3proxy() {
  echo "[⬇️] Tải và biên dịch 3proxy mới nhất..."
  rm -rf "$INSTALL_DIR"
  git clone https://github.com/z3APA3A/3proxy.git "$INSTALL_DIR"
  make -C "$INSTALL_DIR" -f Makefile.Linux
  ln -sf "$INSTALL_DIR/bin/3proxy" /usr/local/bin/3proxy
}

create_systemd_service() {
  cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
ExecStart=/usr/local/bin/3proxy $INSTALL_DIR/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reexec
  systemctl enable 3proxy
}

# ===== MAIN =====

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

install_requirements
install_3proxy
create_systemd_service

IPV4=$(curl -4 -s icanhazip.com)
IPV6_PREFIX=$(curl -6 -s icanhazip.com | cut -d':' -f1-4)

echo "[🌐] Lấy địa chỉ IPv4 và prefix IPv6..."
echo "IPv4: $IPV4"
echo "IPv6 Prefix: $IPV6_PREFIX"

read -p "[❓] Bạn muốn tạo bao nhiêu proxy? " PROXY_COUNT

echo "[🔢] Sinh dữ liệu proxy..."
gen_data
gen_config_3proxy
gen_ifconfig_commands
gen_firewall_rules
gen_proxy_txt

echo "[🧩] Gán IPv6 vào interface $IPV6_INTERFACE..."
bash "$WORK_DIR/assign_ipv6.sh"

echo "[🔥] Mở port với firewalld..."
bash "$WORK_DIR/firewall.sh"
firewall-cmd --reload

echo "[🚀] Khởi động 3proxy..."
systemctl restart 3proxy

echo "[📦] Xuất file proxy.txt..."
cat "$WORK_DIR/proxy.txt"

echo "[☁️] Upload proxy.txt lên transfer.sh..."
upload_to_transfersh
