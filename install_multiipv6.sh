#!/bin/bash
set -euo pipefail

WORKDIR="/opt/multiipv6"
CNT=${1:-}
FIRST_PORT=${2:-10000}

function random_pw() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c8
}

function gen_ipv6_suffix() {
  printf "%04x%04x%04x%04x" $((RANDOM&0xffff)) $((RANDOM&0xffff)) $((RANDOM&0xffff)) $((RANDOM&0xffff))
}

function install_packages() {
  dnf install -y curl wget iproute network-manager iptables-services firewalld
}

function detect_if() {
  IP4=$(curl -4 -s icanhazip.com)
  IP6_PREFIX=$(curl -6 -s icanhazip.com | cut -d: -f1-4)
  IFACE=$(ip -o addr show to $IP4 | awk '{print $2}' | head -n1)
}

function gen_data() {
  echo "# ip4:port:user:pass"
  for ((i=0; i<CNT; i++)); do
    port=$((FIRST_PORT + i))
    suffix=$(gen_ipv6_suffix)
    addr="${IP6_PREFIX}:${suffix}"
    user="u${port}"
    pass=$(random_pw)
    echo "${IP4}:${port}:${user}:${pass}:${addr}"
  done
}

function config_firewall() {
  firewall-cmd --permanent --add-port=${FIRST_PORT}-$(($FIRST_PORT + CNT -1))/tcp
  firewall-cmd --reload
}

function config_ifup() {
  # tạo file systemd-network generator script
  cat >${WORKDIR}/add_ipv6.sh <<EOF
#!/bin/bash
ip link add dummy-mipv6 type dummy
ip link set dummy-mipv6 up
EOF
  chmod +x ${WORKDIR}/add_ipv6.sh
  cat >> /etc/rc.d/rc.local <<EOF
${WORKDIR}/boot_ifconfig.sh
EOF
  chmod +x /etc/rc.d/rc.local
}

function gen_boot_ifconfig() {
  cat >${WORKDIR}/boot_ifconfig.sh <<EOF
#!/bin/bash
ip addr flush dev $IFACE
EOF
  while read IP4 PORT USER PASS IPV6; do
    echo "ip addr add ${IP4}/32 dev $IFACE" >>${WORKDIR}/boot_ifconfig.sh
    echo "ip addr add ${IPV6}/128 dev $IFACE" >>${WORKDIR}/boot_ifconfig.sh
  done <${WORKDIR}/data.txt
  chmod +x ${WORKDIR}/boot_ifconfig.sh
}

function gen_3proxy_cfg() {
  mkdir -p /usr/local/etc/3proxy
  cat > /usr/local/etc/3proxy/3proxy.cfg <<EOF
daemon
maxconn 10000
nserver 1.1.1.1
timeouts 1 5 30 60 180 1800 15 60
users \$(cut -d: -f3,4 ${WORKDIR}/data.txt | tr ':' '\\:')
auth strong
allow * * * *
EOF
  while read IP4 PORT USER PASS IPV6; do
    cat >> /usr/local/etc/3proxy/3proxy.cfg <<EOL
proxy -6 -p${PORT} -a -i${IP4} -e${IPV6} -u${USER} -P${PASS}
EOL
  done <${WORKDIR}/data.txt
}

function install_3proxy() {
  # ví dụ compile hoặc từ repo
  dnf install -y 3proxy
}

function service_3proxy() {
  cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now 3proxy
}

# main
install_packages
detect_if

if [[ -z "$CNT" ]]; then
  read -rp "How many proxies to create? " CNT
fi

mkdir -p "$WORKDIR"
gen_data >"${WORKDIR}/data.txt"

config_firewall
gen_boot_ifconfig
install_3proxy
gen_3proxy_cfg
service_3proxy

echo "Proxies generated in ${WORKDIR}/data.txt"
echo "3proxy running."
