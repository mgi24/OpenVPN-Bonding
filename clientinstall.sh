#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Harus root"
  exit 1
fi

# =========================
# CONFIG (HARDCODE + VAR)
# =========================
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-168.110.213.113}"

VPN_PROTO="${VPN_PROTO:-udp}"
VPN_NETMASK="${VPN_NETMASK:-255.255.255.0}"

# bonding config
TUN_NUM=2
VPN_SERVER_IP_BASE="10.9.0"
VPN_CLIENT_IP_BASE="10.9.0"

# interface WAN client
IFACE1="eth0"
IFACE2="eth1"

echo "[STEP 1] Install paket"
apt update
apt -y install openvpn iproute2

echo "[STEP 2] Siapkan direktori"
mkdir -p /etc/openvpn/client

echo "[STEP 3] Validasi key"
if [ ! -f /etc/openvpn/ta.key ]; then
  echo "❌ /etc/openvpn/ta.key tidak ada"
  echo "Copy dari server dulu!"
  exit 1
fi
chmod 600 /etc/openvpn/ta.key
echo "✔ key OK"

echo "[STEP 4] Generate config client bonding"

for i in $(seq 1 ${TUN_NUM}); do

  PORT=$((1190 + i))
  TAP="tap${i}"

  CONF="/etc/openvpn/client/client${i}.conf"

  echo "  -> ${CONF}"

  cat > ${CONF} <<EOF
dev ${TAP}
proto ${VPN_PROTO}
remote ${SERVER_PUBLIC_IP} ${PORT}
secret /etc/openvpn/ta.key

cipher AES-256-CBC
data-ciphers AES-256-CBC
auth SHA256

persist-key
persist-tun

# keepalive biar tidak drop
ping 10
ping-restart 60
ping-timer-rem
resolv-retry infinite

explicit-exit-notify 3

verb 3
EOF

done

echo "[STEP 5] Setup routing table"

for i in $(seq 1 ${TUN_NUM}); do
  TABLE_ID=$((10 + i))

  if grep -q "${TABLE_ID} vpn${i}" /etc/iproute2/rt_tables; then
    echo "  -> vpn${i} sudah ada"
  else
    echo "${TABLE_ID} vpn${i}" >> /etc/iproute2/rt_tables
    echo "  -> tambah vpn${i}"
  fi
done

echo
echo "[STEP 6] Summary config"

ls -lah /etc/openvpn/client/

echo
echo "======================================"
echo "CLIENT INSTALL DONE"
echo "======================================"
echo "TUNNEL: ${TUN_NUM}"
echo "SERVER: ${SERVER_PUBLIC_IP}"
echo "PORT  : 1191 - 119${TUN_NUM}"
echo
echo "NEXT:"
echo "-> jalankan clientstart.sh"