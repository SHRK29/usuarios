#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://192.168.40.10:30784}"
COUNT="${2:-50}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl no esta instalado" >&2
  exit 1
fi

echo "Insertando ${COUNT} usuarios en ${BASE_URL}/api/usuarios"

for i in $(seq 1 "${COUNT}"); do
  username="user$(printf '%03d' "$i")"
  email="${username}@example.com"
  name="Usuario $(printf '%03d' "$i")"

  http_code="$(
    curl -s -o /tmp/seed-usuario-response.json -w "%{http_code}" \
      -X POST "${BASE_URL}/api/usuarios" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"${name}\",\"username\":\"${username}\",\"email\":\"${email}\"}"
  )"

  if [[ "${http_code}" =~ ^2 ]]; then
    echo "OK ${i}/${COUNT}: ${username}"
  else
    echo "WARN ${i}/${COUNT}: ${username} HTTP ${http_code}"
    cat /tmp/seed-usuario-response.json
    echo
  fi
done

echo "Total actual:"
curl -s "${BASE_URL}/api/usuarios"
echo
