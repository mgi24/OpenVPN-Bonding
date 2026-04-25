#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Harus root"
  exit 1
fi

echo "[STEP 1] Install dependency"
apt update
apt -y install openvpn iptables iproute2

echo "[STEP 2] Prepare directory"
mkdir -p /etc/openvpn/server

echo "[STEP 3] Generate static key"
if [ ! -f /etc/openvpn/ta.key ]; then
  openvpn --genkey secret /etc/openvpn/ta.key
  chmod 600 /etc/openvpn/ta.key
  echo "✔ ta.key dibuat"
else
  echo "✔ ta.key sudah ada"
fi

echo "[STEP 4] Generate config (2 tunnel)"

# HARD CODED PARAM
TUN_NUM=2

for i in $(seq 1 ${TUN_NUM}); do
  DEV="tap${i}"
  PORT="119${i}"
  SERVER_IP="10.9.0.${i}"

  CONF="/etc/openvpn/server/server${i}.conf"

  echo "  -> ${CONF}"

  cat > ${CONF} <<EOF
port ${PORT}
proto udp
dev ${DEV}

secret /etc/openvpn/ta.key

# OpenVPN 2.6 compatible
data-ciphers AES-256-CBC
data-ciphers-fallback AES-256-CBC
auth SHA256
disable-dco

ifconfig ${SERVER_IP} 255.255.255.0

keepalive 10 60
persist-key
persist-tun

user nobody
group nogroup

verb 3
EOF

done

echo "[STEP 5] Enable IP forwarding"
sysctl -w net.ipv4.ip_forward=1

if grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf; then
  sed -i 's/^net\.ipv4\.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
else
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi

echo "✔ IP forwarding aktif"

echo
echo "======================================"
echo "INSTALL SELESAI (BELUM START)"
echo "======================================"
echo "Config:"
ls -lah /etc/openvpn/server/
echo
echo "NEXT:"
echo "-> jalankan serverstart.sh"