#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-usuariosdb}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
DB_IP="${DB_IP:-192.168.40.13}"
K8S_CIDR="${K8S_CIDR:-192.168.0.0/16}"

sudo apt update
sudo apt install -y postgresql postgresql-contrib pgbouncer

PG_VERSION="${PG_VERSION:-$(ls /etc/postgresql | sort -V | tail -n 1)}"

sudo sed -i "s/^#listen_addresses =.*/listen_addresses = '${DB_IP}'/" "/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
sudo sed -i "s/^listen_addresses =.*/listen_addresses = '${DB_IP}'/" "/etc/postgresql/${PG_VERSION}/main/postgresql.conf"

sudo systemctl restart postgresql

sudo -u postgres psql <<SQL
ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
SQL

if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  sudo -u postgres createdb "${DB_NAME}"
fi

sudo -u postgres psql -d "${DB_NAME}" < "$(dirname "$0")/../db/init.sql"

if ! sudo grep -q "${K8S_CIDR}" "/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"; then
  echo "host    ${DB_NAME}    ${DB_USER}    ${K8S_CIDR}    scram-sha-256" | sudo tee -a "/etc/postgresql/${PG_VERSION}/main/pg_hba.conf" >/dev/null
fi

sudo tee /etc/pgbouncer/pgbouncer.ini >/dev/null <<EOF
[databases]
${DB_NAME} = host=${DB_IP} port=5432 dbname=${DB_NAME}

[pgbouncer]
listen_addr = ${DB_IP}
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 500
default_pool_size = 50
reserve_pool_size = 10
server_reset_query = DISCARD ALL
ignore_startup_parameters = extra_float_digits
EOF

USER_HASH="$(sudo -u postgres psql -Atc "SELECT rolpassword FROM pg_authid WHERE rolname='${DB_USER}'")"
echo "\"${DB_USER}\" \"${USER_HASH}\"" | sudo tee /etc/pgbouncer/userlist.txt >/dev/null
sudo chown postgres:postgres /etc/pgbouncer/userlist.txt
sudo chmod 640 /etc/pgbouncer/userlist.txt

sudo systemctl restart postgresql
sudo systemctl restart pgbouncer
sudo systemctl enable postgresql pgbouncer

echo "PostgreSQL listo en ${DB_IP}:5432"
echo "PgBouncer listo en ${DB_IP}:6432"
