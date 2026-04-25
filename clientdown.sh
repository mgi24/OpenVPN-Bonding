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

echo "[STEP 1] Stop semua OpenVPN"
pkill openvpn 2>/dev/null || true
sleep 1
echo "✔ OpenVPN stopped"

# =========================
# CAPTURE GATEWAY (PENTING!)
# =========================
echo "[STEP 2] Capture gateway sebelum cleanup"

GW1=$(ip route show default dev ${IFACE1} | awk '{print $3}' | head -n1 || true)
GW2=$(ip route show default dev ${IFACE2} | awk '{print $3}' | head -n1 || true)

echo "  -> ${IFACE1} GW: ${GW1:-NONE}"
echo "  -> ${IFACE2} GW: ${GW2:-NONE}"

# fallback ambil gateway dari routing table yang masih ada
if [ -z "${GW1}" ]; then
  GW1=$(ip route show | awk '/default/ && /'"${IFACE1}"'/ {print $3}' | head -n1)
fi

if [ -z "${GW2}" ]; then
  GW2=$(ip route show | awk '/default/ && /'"${IFACE2}"'/ {print $3}' | head -n1)
fi

# =========================
# REMOVE DEFAULT ROUTE
# =========================
echo "[STEP 3] Hapus semua default route"

while ip route | grep -q "^default"; do
  ip route del default || true
done

# =========================
# RESTORE DEFAULT ROUTE
# =========================
echo "[STEP 4] Restore default route"

if [ -n "${GW1}" ]; then
  ip route replace default via ${GW1} dev ${IFACE1}
  echo "✔ default via ${IFACE1} (${GW1})"
elif [ -n "${GW2}" ]; then
  ip route replace default via ${GW2} dev ${IFACE2}
  echo "✔ default via ${IFACE2} (${GW2})"
else
  echo "❌ Gagal restore default route!"
  echo "⚠️ Coba DHCP ulang..."

  dhclient ${IFACE1} || true
  dhclient ${IFACE2} || true

  sleep 2

  GW1=$(ip route show default dev ${IFACE1} | awk '{print $3}' | head -n1 || true)

  if [ -n "${GW1}" ]; then
    ip route add default via ${GW1} dev ${IFACE1}
    echo "✔ recovered via DHCP (${IFACE1})"
  else
    echo "❌ Masih gagal, cek manual!"
  fi
fi

# =========================
# HAPUS POLICY ROUTING
# =========================
echo "[STEP 5] Hapus policy routing"

for i in $(seq 1 ${TUN_NUM}); do
  TABLE="vpn${i}"

  echo "  -> remove table ${TABLE}"

  ip rule | grep ${TABLE} | while read -r line; do
    PREF=$(echo "$line" | awk '{print $1}' | sed 's/://')
    ip rule del pref ${PREF} 2>/dev/null || true
  done

  ip route flush table ${TABLE} 2>/dev/null || true
done

ip route flush cache
echo "✔ routing policy cleared"

# =========================
# REMOVE TAP (STRONG CLEANUP)
# =========================
echo "[STEP 6] Hapus TAP interface"

for i in $(seq 1 ${TUN_NUM}); do
  echo "  -> tap${i}"

  ip link set tap${i} down 2>/dev/null || true
  ip link delete tap${i} 2>/dev/null || true

  # fallback kalau masih nyangkut
  openvpn --rmtun --dev tap${i} 2>/dev/null || true
done

echo "✔ TAP cleaned"

# =========================
# REMOVE BOND
# =========================
echo "[STEP 7] Hapus bond interface"

if ip link show ${BOND_IF} >/dev/null 2>&1; then
  ip link set ${BOND_IF} down || true
  ip link delete ${BOND_IF} || true
  echo "✔ bond removed"
else
  echo "bond tidak ada"
fi

# =========================
# FINAL CHECK
# =========================
echo "[STEP 8] Final check"

ip a
echo "----------------------"
ip route

echo
echo "======================================"
echo "CLIENT STOPPED CLEANLY"
echo "======================================"
echo "CHECK:"
echo "-> ping 8.8.8.8"
echo "-> ping google.com"
echo "-> curl -4 ifconfig.me"