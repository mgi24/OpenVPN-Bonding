#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Harus root"
  exit 1
fi

echo "[STEP 1] Load bonding module"
modprobe bonding
lsmod | grep bonding || { echo "❌ bonding module gagal"; exit 1; }
echo "✔ bonding loaded"

echo "[STEP 2] Prepare bond0 (idempotent)"

if ip link show bond0 >/dev/null 2>&1; then
  echo "  -> bond0 sudah ada, cleanup dulu"

  # detach slave kalau ada
  for i in $(seq 1 2); do
    ip link set tap${i} nomaster 2>/dev/null || true
  done

  # down bond
  ip link set bond0 down || true

  # hapus bond lama
  ip link delete bond0 || true
fi

echo "  -> create bond0 baru"
ip link add bond0 type bond

echo "[STEP 3] Set bonding mode (round-robin)"

# bond harus DOWN dan belum ada slave
ip link set bond0 down
echo 0 > /sys/class/net/bond0/bonding/mode

cat /sys/class/net/bond0/bonding/mode

echo "[STEP 4] Create TAP & attach ke bond"

TUN_NUM=2

echo "[CLEANUP] remove old tap (jika ada)"
for i in $(seq 1 ${TUN_NUM}); do
  ip link set tap${i} down 2>/dev/null || true
  openvpn --rmtun --dev tap${i} 2>/dev/null || true
done

for i in $(seq 1 ${TUN_NUM}); do
  echo "  -> tap${i}"

  openvpn --mktun --dev tap${i} || true

  # pastikan DOWN sebelum enslave
  ip link set tap${i} down || true

  # attach ke bond
  ip link set tap${i} master bond0
done

echo "[STEP 5] Start OpenVPN instances"

for i in $(seq 1 ${TUN_NUM}); do
  CONF="/etc/openvpn/server/server${i}.conf"

  echo "  -> start ${CONF}"

  openvpn --config ${CONF} --daemon

  sleep 1
done

echo "[FIX] Remove IP dari TAP (harus bonding only)"

for i in $(seq 1 ${TUN_NUM}); do
  ip addr flush dev tap${i}
done

echo "[STEP 6] Bring up bond0 + set MTU"
ip link set bond0 up mtu 1440

echo "[STEP 7] Assign IP ke bond0"
ip addr add 10.9.0.254/24 dev bond0 || true

ip a show bond0

echo "[STEP 8] Detect WAN interface (hardcoded enp0s6)"
WAN_IFACE="enp0s6"

ip link show ${WAN_IFACE} > /dev/null || { echo "❌ WAN iface tidak ada"; exit 1; }

echo "✔ WAN = ${WAN_IFACE}"

echo "[STEP 9] Enable IP forward (runtime)"
sysctl -w net.ipv4.ip_forward=1

echo "[STEP 10] Setup iptables NAT"

iptables -C FORWARD -i bond0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i bond0 -j ACCEPT
iptables -C FORWARD -o bond0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o bond0 -j ACCEPT
iptables -t nat -C POSTROUTING -o ${WAN_IFACE} -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o ${WAN_IFACE} -j MASQUERADE

echo "✔ NAT OK"

echo "[STEP 11] Final check"

ip a show bond0
ip a | grep tap
ip route

echo
echo "======================================"
echo "SERVER RUNNING"
echo "======================================"
echo "TAP: tap1, tap2"
echo "BOND: bond0 (10.9.0.254)"
echo "PORT: 1191, 1192"
echo
echo "CHECK:"
echo "-> ss -lunp | grep 119"
echo "-> ip a"
echo "-> ip route"