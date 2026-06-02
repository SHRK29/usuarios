#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Uso en la VM db, despues de cambiar de red:
  sudo bash ./scripts/db-after-ip-change.sh ENV_FILE OLD_DB_IP

Ejemplos:
  sudo bash ./scripts/db-after-ip-change.sh ./scripts/uptc-ips.env 192.168.40.13
  sudo bash ./scripts/db-after-ip-change.sh ./scripts/lab-ips.env 192.168.137.13

Corrige PgBouncer/PostgreSQL para escuchar la IP nueva de la DB.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then
  usage
  exit 0
fi

ENV_FILE="$1"
OLD_DB_IP="$2"

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
DB_IP="${DB_IP:-${LAB_NET_PREFIX}.13}"
PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"

echo "[1/4] Actualizando PgBouncer ${OLD_DB_IP} -> ${DB_IP}"
if [[ -f /etc/pgbouncer/pgbouncer.ini ]]; then
  cp -f /etc/pgbouncer/pgbouncer.ini "/etc/pgbouncer/pgbouncer.ini.bak.$(date +%Y%m%d%H%M%S)"
  sed -i "s/${OLD_DB_IP}/${DB_IP}/g" /etc/pgbouncer/pgbouncer.ini
fi

echo "[2/4] Actualizando PostgreSQL si tenia IP fija"
if [[ -d /etc/postgresql ]]; then
  find /etc/postgresql -type f \( -name 'postgresql.conf' -o -name 'pg_hba.conf' \) -print0 \
    | xargs -0 -r sed -i "s/${OLD_DB_IP}/${DB_IP}/g"
fi

echo "[3/4] Reiniciando servicios"
systemctl restart postgresql || true
systemctl restart pgbouncer

echo "[4/4] Verificacion"
systemctl status pgbouncer --no-pager || true
ss -lntp | grep -E "5432|${PGBOUNCER_PORT}" || true
echo
echo "Desde master prueba:"
echo "  nc -vz ${DB_IP} ${PGBOUNCER_PORT}"
