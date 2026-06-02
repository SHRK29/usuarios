#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./scripts/update-lab-ips.sh [opciones]

Opciones:
  --prefix 192.168.56       Cambia el prefijo de red y recalcula .10 .11 .12 .13
  --master-ip IP            Nueva IP del master
  --node1-ip IP             Nueva IP de node1
  --node2-ip IP             Nueva IP de node2
  --db-ip IP                Nueva IP de la VM db
  --gateway IP              Gateway opcional

Ejemplos:
  ./scripts/update-lab-ips.sh --db-ip 192.168.56.50
  ./scripts/update-lab-ips.sh --prefix 192.168.40 --gateway 192.168.40.1

Actualiza:
  scripts/lab-ips.env
  k8s/03-postgres-external-service.yaml
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      LAB_NET_PREFIX="$2"
      MASTER_IP="${LAB_NET_PREFIX}.10"
      NODE1_IP="${LAB_NET_PREFIX}.11"
      NODE2_IP="${LAB_NET_PREFIX}.12"
      DB_IP="${LAB_NET_PREFIX}.13"
      shift 2
      ;;
    --master-ip) MASTER_IP="$2"; shift 2 ;;
    --node1-ip) NODE1_IP="$2"; shift 2 ;;
    --node2-ip) NODE2_IP="$2"; shift 2 ;;
    --db-ip) DB_IP="$2"; shift 2 ;;
    --gateway) GATEWAY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Opcion no reconocida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

cat > "${ENV_FILE}" <<EOF
LAB_NET_PREFIX=${LAB_NET_PREFIX}
NETMASK_CIDR=${NETMASK_CIDR}
GATEWAY=${GATEWAY}
DNS_SERVERS=${DNS_SERVERS}

MASTER_IP=${MASTER_IP}
NODE1_IP=${NODE1_IP}
NODE2_IP=${NODE2_IP}
DB_IP=${DB_IP}

POD_CIDR=${POD_CIDR}
PGBOUNCER_PORT=${PGBOUNCER_PORT}
EOF

python - "$ROOT_DIR" "$DB_IP" "$PGBOUNCER_PORT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
db_ip = sys.argv[2]
port = sys.argv[3]

replacements = {
    root / "k8s" / "03-postgres-external-service.yaml": [
        (r'- "(?:\d{1,3}\.){3}\d{1,3}"', f'- "{db_ip}"'),
        (r'port: \d+', f'port: {port}'),
        (r'targetPort: \d+', f'targetPort: {port}'),
    ],
}

for path, rules in replacements.items():
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    for pattern, repl in rules:
        text = re.sub(pattern, repl, text)
    path.write_text(text, encoding="utf-8")
PY

echo "IPs actualizadas:"
echo "  master: ${MASTER_IP}"
echo "  node1:  ${NODE1_IP}"
echo "  node2:  ${NODE2_IP}"
echo "  db:     ${DB_IP}"
echo
echo "Recuerda aplicar Kubernetes si cambio DB_IP:"
echo "  kubectl apply -f k8s/03-postgres-external-service.yaml"
echo "  kubectl -n usuarios rollout restart deployment usuarios-api"
