#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  sudo bash ./scripts/vm-first-boot.sh ROLE INTERFAZ ENV_FILE

Roles:
  master | node1 | node2 | db

Ejemplos casa:
  sudo bash ./scripts/vm-first-boot.sh master enp0s8 ./scripts/lab-ips.env
  sudo bash ./scripts/vm-first-boot.sh node1  enp0s8 ./scripts/lab-ips.env

Ejemplos universidad:
  sudo bash ./scripts/vm-first-boot.sh master enp0s8 ./scripts/uptc-ips.env
  sudo bash ./scripts/vm-first-boot.sh db     enp0s8 ./scripts/uptc-ips.env

Hace:
  - Configura hostname.
  - Reescribe /etc/hosts con las IPs del ENV_FILE.
  - Desactiva YAMLs viejos de netplan para evitar doble IP/rutas duplicadas.
  - Configura una sola IP estatica en la interfaz indicada.
  - Habilita SSH si ya esta instalado; intenta instalarlo sin romper el script.
  - Si existe kubelet, fija --node-ip para Kubernetes.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  usage
  exit 0
fi

ROLE="$1"
IFACE="${2:-}"
ENV_FILE="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${ENV_FILE}" ]]; then
  if [[ -f "${SCRIPT_DIR}/uptc-ips.env" ]]; then
    ENV_FILE="${SCRIPT_DIR}/uptc-ips.env"
  else
    ENV_FILE="${SCRIPT_DIR}/lab-ips.env"
  fi
fi

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  echo "No existe ENV_FILE: ${ENV_FILE}" >&2
  exit 1
fi

LAB_NET_PREFIX="${LAB_NET_PREFIX:-192.168.40}"
NETMASK_CIDR="${NETMASK_CIDR:-24}"
GATEWAY="${GATEWAY:-${LAB_NET_PREFIX}.1}"
DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,1.1.1.1}"

MASTER_IP="${MASTER_IP:-${LAB_NET_PREFIX}.10}"
NODE1_IP="${NODE1_IP:-${LAB_NET_PREFIX}.11}"
NODE2_IP="${NODE2_IP:-${LAB_NET_PREFIX}.12}"
DB_IP="${DB_IP:-${LAB_NET_PREFIX}.13}"

case "${ROLE}" in
  master) VM_IP="${MASTER_IP}"; HOSTNAME_VALUE="master" ;;
  node1) VM_IP="${NODE1_IP}"; HOSTNAME_VALUE="node1" ;;
  node2) VM_IP="${NODE2_IP}"; HOSTNAME_VALUE="node2" ;;
  db) VM_IP="${DB_IP}"; HOSTNAME_VALUE="db" ;;
  *)
    echo "Rol no valido: ${ROLE}" >&2
    usage
    exit 1
    ;;
esac

if [[ -z "${IFACE}" ]]; then
  IFACE="$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')"
fi

if [[ -z "${IFACE}" ]]; then
  echo "No pude detectar la interfaz. Pasala como segundo parametro." >&2
  ip -o link show >&2
  exit 1
fi

if ! ip link show "${IFACE}" >/dev/null 2>&1; then
  echo "La interfaz no existe: ${IFACE}" >&2
  ip -br addr >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta con sudo: sudo bash $0 ${ROLE} ${IFACE} ${ENV_FILE}" >&2
  exit 1
fi

echo "[1/6] Hostname: ${HOSTNAME_VALUE}"
hostnamectl set-hostname "${HOSTNAME_VALUE}"

echo "[2/6] /etc/hosts"
cp /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
cat > /etc/hosts <<EOF
127.0.0.1 localhost
127.0.1.1 ${HOSTNAME_VALUE}

${MASTER_IP} master
${NODE1_IP} node1
${NODE2_IP} node2
${DB_IP} db

::1 ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

echo "[3/6] Netplan ${IFACE} -> ${VM_IP}/${NETMASK_CIDR}"
mkdir -p /etc/netplan/backups-lab "/etc/netplan/disabled-$(date +%Y%m%d%H%M%S)"
BACKUP_DIR="/etc/netplan/backups-lab/$(date +%Y%m%d%H%M%S)"
DISABLED_DIR="/etc/netplan/disabled-$(date +%Y%m%d%H%M%S)"
mkdir -p "${BACKUP_DIR}" "${DISABLED_DIR}"
cp -a /etc/netplan/*.yaml "${BACKUP_DIR}/" 2>/dev/null || true

# Evita el error que tuvimos en la universidad: dos IPs y dos default routes
# activas en enp0s8. Se desactivan todos los YAML existentes y se deja uno solo.
for file in /etc/netplan/*.yaml; do
  [[ -e "${file}" ]] || continue
  mv "${file}" "${DISABLED_DIR}/"
done

NETPLAN_FILE="/etc/netplan/99-${ROLE}-static.yaml"
if [[ -n "${GATEWAY}" ]]; then
  cat > "${NETPLAN_FILE}" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${VM_IP}/${NETMASK_CIDR}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF
else
  cat > "${NETPLAN_FILE}" <<EOF
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses:
        - ${VM_IP}/${NETMASK_CIDR}
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF
fi
chmod 600 "${NETPLAN_FILE}"
netplan generate
netplan apply

echo "[4/6] SSH"
if command -v sshd >/dev/null 2>&1 || [[ -x /usr/sbin/sshd ]]; then
  systemctl enable --now ssh || systemctl enable --now sshd || true
else
  echo "openssh-server no esta instalado. Intentando instalarlo; si apt esta roto, se continua."
  apt update || true
  apt --fix-broken install -y || true
  apt install -y openssh-server || true
  systemctl enable --now ssh || systemctl enable --now sshd || true
fi

echo "[5/6] Kubelet node-ip si existe"
if command -v kubelet >/dev/null 2>&1 || [[ -d /var/lib/kubelet ]]; then
  echo "KUBELET_EXTRA_ARGS=--node-ip=${VM_IP}" > /etc/default/kubelet
  if [[ -f /var/lib/kubelet/kubeadm-flags.env ]]; then
    sed -i -E 's/ --node-ip=[^ ]+//g; s/^KUBELET_KUBEADM_ARGS="/KUBELET_KUBEADM_ARGS="/' /var/lib/kubelet/kubeadm-flags.env || true
  fi
  systemctl daemon-reload
  systemctl restart kubelet || true
fi

echo "[6/6] Verificacion"
ip -br addr show "${IFACE}" || true
ip route || true
systemctl status ssh --no-pager || systemctl status sshd --no-pager || true
echo
echo "Listo. Prueba desde MobaXterm:"
echo "  ssh $(logname 2>/dev/null || echo master)@${VM_IP}"
