#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  sudo ./scripts/set-vm-static-ip.sh ROLE [INTERFAZ]

Roles:
  master | node1 | node2 | db

Ejemplos:
  sudo ./scripts/set-vm-static-ip.sh master
  sudo ./scripts/set-vm-static-ip.sh node1 enp0s8
  sudo LAB_NET_PREFIX=192.168.40 GATEWAY=192.168.40.1 ./scripts/set-vm-static-ip.sh db

El script lee scripts/lab-ips.env si existe.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

ROLE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/lab-ips.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

LAB_NET_PREFIX="${LAB_NET_PREFIX:-192.168.56}"
NETMASK_CIDR="${NETMASK_CIDR:-24}"
GATEWAY="${GATEWAY:-}"
DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,1.1.1.1}"

MASTER_IP="${MASTER_IP:-${LAB_NET_PREFIX}.10}"
NODE1_IP="${NODE1_IP:-${LAB_NET_PREFIX}.11}"
NODE2_IP="${NODE2_IP:-${LAB_NET_PREFIX}.12}"
DB_IP="${DB_IP:-${LAB_NET_PREFIX}.13}"

case "${ROLE}" in
  master) VM_IP="${MASTER_IP}" ;;
  node1) VM_IP="${NODE1_IP}" ;;
  node2) VM_IP="${NODE2_IP}" ;;
  db) VM_IP="${DB_IP}" ;;
  *)
    echo "Rol no valido: ${ROLE}" >&2
    usage
    exit 1
    ;;
esac

IFACE="${2:-}"
if [[ -z "${IFACE}" ]]; then
  IFACE="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | while read -r candidate; do
    if ip -4 addr show "$candidate" | grep -q "${LAB_NET_PREFIX}\."; then
      echo "$candidate"
      break
    fi
  done)"
fi

if [[ -z "${IFACE}" ]]; then
  echo "No pude detectar automaticamente la interfaz host-only ${LAB_NET_PREFIX}.x." >&2
  echo "Interfaces disponibles:" >&2
  ip -o link show | awk -F': ' '$2 != "lo" {print "  " $2}' >&2
  echo "Pasala como segundo parametro, por ejemplo:" >&2
  echo "  sudo $0 ${ROLE} enp0s8" >&2
  exit 1
fi

NETPLAN_FILE="/etc/netplan/99-lab-${ROLE}.yaml"
BACKUP_DIR="/etc/netplan/backups-lab"

sudo mkdir -p "${BACKUP_DIR}"
sudo cp -a /etc/netplan/*.yaml "${BACKUP_DIR}/" 2>/dev/null || true

TMP_FILE="$(mktemp)"

if [[ -n "${GATEWAY}" ]]; then
  cat > "${TMP_FILE}" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${VM_IP}/${NETMASK_CIDR}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF
else
  cat > "${TMP_FILE}" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses:
        - ${VM_IP}/${NETMASK_CIDR}
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF
fi

sudo mv "${TMP_FILE}" "${NETPLAN_FILE}"
sudo chmod 600 "${NETPLAN_FILE}"

echo "Aplicando IP ${VM_IP}/${NETMASK_CIDR} en ${IFACE} para rol ${ROLE}..."
sudo netplan generate
sudo netplan apply

echo "Listo. IP configurada:"
ip -4 addr show "${IFACE}"
