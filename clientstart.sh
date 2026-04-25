#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Harus root"
  exit 1
fi

# =========================
# CONFIG
# =========================
TUN_NUM=2
BOND_IF="bond0"

IFACE1="eth0"
IFACE2="eth1"

BOND_IP="10.9.0.253"
REMOTE_BOND_IP="10.9.0.254"

echo "[STEP 1] Load bonding module"
modprobe bonding
lsmod | grep bonding || { echo "❌ bonding gagal"; exit 1; }

echo "[STEP 2] Cleanup lama (idempotent)"

pkill openvpn 2>/dev/null || true

for i in $(seq 1 ${TUN_NUM}); do
  ip link set tap${i} down 2>/dev/null || true
  openvpn --rmtun --dev tap${i} 2>/dev/null || true
done

if ip link show ${BOND_IF} >/dev/null 2>&1; then
  ip link set ${BOND_IF} down || true
  ip link delete ${BOND_IF} || true
fi

echo "[STEP 3] Create bond0"
ip link add ${BOND_IF} type bond

echo "[STEP 4] Set bonding mode RR"
ip link set ${BOND_IF} down
echo 0 > /sys/class/net/${BOND_IF}/bonding/mode
cat /sys/class/net/${BOND_IF}/bonding/mode

echo "[STEP 5] Create TAP & attach"

for i in $(seq 1 ${TUN_NUM}); do
  echo "  -> tap${i}"

  openvpn --mktun --dev tap${i}
  ip link set tap${i} down
  ip link set tap${i} master ${BOND_IF}
done

echo "[STEP 6] Routing policy per interface"

INTERFACES=(${IFACE1} ${IFACE2})

for i in $(seq 1 ${TUN_NUM}); do
  IFACE=${INTERFACES[$((i-1))]}

  echo "  -> bind ke ${IFACE}"

  IP=$(ip -4 addr show ${IFACE} | awk '/inet / {print $2}' | cut -d/ -f1)
  GW=$(ip route show default dev ${IFACE} | awk '{print $3}')

  echo "     IP=${IP} GW=${GW}"

  TABLE="vpn${i}"

  ip rule add from ${IP} table ${TABLE} 2>/dev/null || true
  ip route add default via ${GW} dev ${IFACE} table ${TABLE} 2>/dev/null || true

  CONF="/etc/openvpn/client/client${i}.conf"

  sed -i '/^local /d' ${CONF}
  echo "local ${IP}" >> ${CONF}
done

echo "[STEP 7] Bring up bond"

ip link set ${BOND_IF} up mtu 1440
ip addr add ${BOND_IP}/24 dev ${BOND_IF} || true

ip a show ${BOND_IF}

echo "[STEP 8] Flush route cache"
ip route flush cache

echo "[STEP 9] Start OpenVPN (daemon)"

for i in $(seq 1 ${TUN_NUM}); do
  CONF="/etc/openvpn/client/client${i}.conf"

  echo "  -> start ${CONF}"

  openvpn --daemon --config ${CONF}

  sleep 2
done

echo "[STEP 10] Flush IP TAP (bond only)"

for i in $(seq 1 ${TUN_NUM}); do
  ip addr flush dev tap${i}
done

echo "[STEP 11A] Pastikan route ke server lewat WAN"

ip route add 168.110.213.113 via 192.168.0.1 dev eth0 2>/dev/null || true
ip route add 168.110.213.113 via 192.168.0.1 dev eth1 2>/dev/null || true

echo "[STEP 11] Set default route via bond (clean)"

# hapus semua default lama
while ip route | grep -q "^default"; do
  ip route del default || true
done

# tambah default ke VPN
ip route add default via ${REMOTE_BOND_IP}

echo "[STEP 12] Final check"

ip a show ${BOND_IF}
ip route
ss -lunp | grep openvpn || true

echo
echo "======================================"
echo "CLIENT RUNNING"
echo "======================================"
echo "BOND: ${BOND_IF} (${BOND_IP})"
echo "REMOTE: ${REMOTE_BOND_IP}"
echo
echo "CHECK:"
echo "-> ip a"
echo "-> ip route"
echo "-> ping 10.9.0.254"
echo "-> curl -4 ifconfig.me"