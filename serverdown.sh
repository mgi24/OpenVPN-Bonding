#!/usr/bin/env bash
set -euo pipefail

if [ "${EUID}" -ne 0 ]; then
  echo "Harus root"
  exit 1
fi

TUN_NUM=2
WAN_IFACE="enp0s6"

echo "[STEP 1] Stop OpenVPN instances"

# kill semua proses openvpn yang pakai config server
PIDS=$(pgrep -f "openvpn --config /etc/openvpn/server/server")

if [ -n "${PIDS:-}" ]; then
  echo "  -> killing: $PIDS"
  kill $PIDS || true
  sleep 1
else
  echo "  -> tidak ada proses openvpn"
fi

# pastikan mati
pgrep openvpn && echo "⚠️ masih ada openvpn jalan" || echo "✔ openvpn stopped"

 

echo "[STEP 2] Remove iptables NAT & forwarding rules"

iptables -D FORWARD -i bond0 -j ACCEPT 2>/dev/null || echo "  -> skip FORWARD -i bond0"
iptables -D FORWARD -o bond0 -j ACCEPT 2>/dev/null || echo "  -> skip FORWARD -o bond0"
iptables -t nat -D POSTROUTING -o ${WAN_IFACE} -j MASQUERADE 2>/dev/null || echo "  -> skip MASQUERADE"

echo "✔ iptables cleaned"

 

echo "[STEP 3] Flush IP bond0"

ip addr flush dev bond0 2>/dev/null || echo "  -> bond0 tidak ada / sudah bersih"

 

echo "[STEP 4] Bring down TAP interfaces"

for i in $(seq 1 ${TUN_NUM}); do
  echo "  -> tap${i}"

  ip link set tap${i} down 2>/dev/null || true
done

 

echo "[STEP 5] Remove TAP interfaces"

for i in $(seq 1 ${TUN_NUM}); do
  echo "  -> remove tap${i}"

  openvpn --rmtun --dev tap${i} 2>/dev/null || echo "     (skip / tidak ada)"
done

 

echo "[STEP 6] Bring down bond0"

ip link set bond0 down 2>/dev/null || echo "  -> bond0 sudah down / tidak ada"

 

echo "[STEP 7] Delete bond0"

ip link delete bond0 2>/dev/null || echo "  -> bond0 sudah tidak ada"

 

echo "[STEP 8] Final check"

echo "  openvpn  "
pgrep openvpn || echo "✔ tidak ada openvpn"

echo "  interface  "
ip a | grep -E "bond0|tap" || echo "✔ tidak ada tap/bond"

echo "  iptables  "
iptables -t nat -L | grep MASQUERADE || echo "✔ tidak ada NAT rule"

echo
echo "======================================"
echo "SERVER STOPPED CLEAN"
echo "======================================"