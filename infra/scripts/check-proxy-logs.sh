#!/usr/bin/env bash
set -euo pipefail

log_file="/var/log/squid/access.log"
lines="${1:-100}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if ! [[ "${lines}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: $0 [number_of_recent_lines]" >&2
  exit 1
fi

if [[ ! -f "${log_file}" ]]; then
  echo "Squid access log was not found: ${log_file}" >&2
  exit 1
fi

printf '%s\n' '=== Squid service ==='
systemctl is-active squid || true
systemctl --no-pager --full status squid | sed -n '1,12p'

printf '%s\n' '' '=== Listening socket ==='
ss -ltnp | awk '$4 ~ /:3128$/ { print }'

printf '%s\n' '' '=== Configuration check ==='
if squid -k parse 2>&1; then
  echo 'Squid configuration: OK'
else
  echo 'Squid configuration: INVALID'
fi

printf '%s\n' '' '=== Recent access log ==='
tail -n "${lines}" "${log_file}"

printf '%s\n' '' '=== Recent denied requests ==='
awk '$4 ~ /TCP_DENIED/ { print }' "${log_file}" | tail -n "${lines}"

printf '%s\n' '' '=== Recent requests from Function integration subnet ==='
awk '$3 ~ /^10\.0\.3\./ { print }' "${log_file}" | tail -n "${lines}"

printf '%s\n' '' '=== Destination summary ==='
awk '
{
  destination = $7
  sub(/^https?:\/\//, "", destination)
  sub(/\/.*/, "", destination)
  if (destination != "-") count[destination]++
}
END {
  for (destination in count) print count[destination], destination
}
' "${log_file}" | sort -nr | head -n 30

printf '%s\n' '' '=== Relevant destination requests ==='
grep -E 'graph\.microsoft\.com|login\.microsoftonline\.com|azurewebsites\.net|staticapps\.net' "${log_file}" | tail -n "${lines}" || true

printf '%s\n' '' '=== Interpretation ==='
echo '1. No requests from 10.0.3.0/26: Function did not reach this Proxy, or the log format/source differs.'
echo '2. TCP_DENIED for Function traffic: Squid ACL or destination allowlist rejected the request.'
echo '3. TCP_MISS/TCP_TUNNEL with 2xx/3xx: Proxy accepted the request; investigate the next hop or SWA/Function path.'
