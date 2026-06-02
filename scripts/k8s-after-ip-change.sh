#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso en el master, despues de cambiar la IP de la VM:
  sudo bash ./scripts/k8s-after-ip-change.sh ENV_FILE OLD_MASTER_IP

Ejemplos:
  sudo bash ./scripts/k8s-after-ip-change.sh ./scripts/uptc-ips.env 192.168.40.10
  sudo bash ./scripts/k8s-after-ip-change.sh ./scripts/lab-ips.env 192.168.137.10

Corrige:
  - /etc/kubernetes/*.conf
  - manifests staticos de control-plane y etcd
  - certificado apiserver para la nueva IP
  - ~/.kube/config del usuario que invoco sudo
  - scheduler/controller-manager recreados
  - ConfigMap y DaemonSet kube-proxy
  - DB_URL del Deployment usuarios-api si existe
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit 0
fi

ENV_FILE="$1"
OLD_MASTER_IP="$2"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "No existe ENV_FILE: ${ENV_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

LAB_NET_PREFIX="${LAB_NET_PREFIX:-192.168.40}"
MASTER_IP="${MASTER_IP:-${LAB_NET_PREFIX}.10}"
DB_IP="${DB_IP:-${LAB_NET_PREFIX}.13}"
PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"

SUDO_USER_HOME="$(getent passwd "${SUDO_USER:-master}" | cut -d: -f6 || true)"
[[ -n "${SUDO_USER_HOME}" ]] || SUDO_USER_HOME="/home/master"

echo "[1/8] Backup /etc/kubernetes"
cp -a /etc/kubernetes "/etc/kubernetes.bak-ipchange-$(date +%Y%m%d%H%M%S)"

echo "[2/8] Reemplazando ${OLD_MASTER_IP} -> ${MASTER_IP}"
find /etc/kubernetes -type f \( -name '*.conf' -o -name '*.yaml' \) -print0 \
  | xargs -0 sed -i "s/${OLD_MASTER_IP}/${MASTER_IP}/g"

echo "[3/8] Regenerando certificado apiserver para ${MASTER_IP}"
mkdir -p /etc/kubernetes/pki/backup-ipchange
cp -f /etc/kubernetes/pki/apiserver.crt "/etc/kubernetes/pki/backup-ipchange/apiserver.crt.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
cp -f /etc/kubernetes/pki/apiserver.key "/etc/kubernetes/pki/backup-ipchange/apiserver.key.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
kubeadm init phase certs apiserver --apiserver-advertise-address="${MASTER_IP}"

echo "[4/8] Reiniciando kubelet/control-plane"
systemctl daemon-reload
systemctl restart kubelet
sleep 30

echo "[5/8] Reinstalando kubeconfig local"
mkdir -p "${SUDO_USER_HOME}/.kube"
cp -f /etc/kubernetes/admin.conf "${SUDO_USER_HOME}/.kube/config"
chown "${SUDO_USER:-master}:${SUDO_USER:-master}" "${SUDO_USER_HOME}/.kube/config" 2>/dev/null || true

export KUBECONFIG="${SUDO_USER_HOME}/.kube/config"

echo "[6/8] Forzando recreacion de scheduler y controller-manager"
for manifest in kube-scheduler.yaml kube-controller-manager.yaml; do
  if [[ -f "/etc/kubernetes/manifests/${manifest}" ]]; then
    mv "/etc/kubernetes/manifests/${manifest}" "/tmp/${manifest}.ipchange"
    sleep 12
    mv "/tmp/${manifest}.ipchange" "/etc/kubernetes/manifests/${manifest}"
  fi
done
sleep 30

echo "[7/8] Corrigiendo kube-proxy"
if kubectl -n kube-system get cm kube-proxy >/dev/null 2>&1; then
  kubectl -n kube-system get cm kube-proxy -o yaml > /tmp/kube-proxy-cm.yaml
  sed -i "s/${OLD_MASTER_IP}/${MASTER_IP}/g" /tmp/kube-proxy-cm.yaml
  kubectl apply -f /tmp/kube-proxy-cm.yaml
fi
kubectl -n kube-system rollout restart daemonset kube-proxy || true

echo "[8/8] Corrigiendo DB_URL de usuarios-api si existe"
if kubectl -n usuarios get deployment usuarios-api >/dev/null 2>&1; then
  kubectl -n usuarios set env deployment/usuarios-api "DB_URL=jdbc:postgresql://${DB_IP}:${PGBOUNCER_PORT}/usuariosdb"
  kubectl -n usuarios rollout restart deployment usuarios-api
fi

echo
echo "Verificacion sugerida:"
echo "  kubectl get nodes -o wide"
echo "  kubectl -n kube-system get pods -o wide"
echo "  kubectl -n usuarios get pods -o wide"
echo "  nc -vz ${DB_IP} ${PGBOUNCER_PORT}"
