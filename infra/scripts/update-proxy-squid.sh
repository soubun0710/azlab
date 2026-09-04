#!/usr/bin/env bash
set -euo pipefail

config_file="/etc/squid/squid.conf"
backup_file="${config_file}.bak.$(date +%Y%m%d%H%M%S)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if ! command -v squid >/dev/null 2>&1; then
  echo "Squid is not installed." >&2
  exit 1
fi

if [[ -f "${config_file}" ]]; then
  cp "${config_file}" "${backup_file}"
fi

cat > "${config_file}" <<'SQUID_CONFIG'
http_port 3128

acl jissou_network src 10.0.1.0/24
acl jissou_denylist dstdomain identity.7.azurestaticapps.net
acl jissou_allowlist dstdomain github.com
acl jissou_allowlist dstdomain graph.microsoft.com
acl jissou_allowlist dstdomain login.microsoftonline.com
acl jissou_allowlist dstdomain management.azure.com
acl jissou_allowlist dstdomain management.core.windows.net
acl jissou_allowlist dstdomain registry.npmjs.org
acl jissou_allowlist dstdomain .azurewebsites.net
acl jissou_allowlist dstdomain aka.ms
acl jissou_allowlist dstdomain .azurefd.net
acl jissou_allowlist dstdomain json.schemastore.org
acl jissou_allowlist dstdomain .azureedge.net
acl jissou_allowlist dstdomain .azurestaticapps.net
acl jissou_allowlist dstdomain .blob.core.windows.net
acl jissou_allowlist dstdomain nodejs.org
acl jissou_allowlist dstdomain release-assets.githubusercontent.com
acl allowed_http_ports port 80
acl allowed_https_ports port 443
acl CONNECT method CONNECT

http_access deny jissou_network jissou_denylist
http_access allow jissou_network jissou_allowlist allowed_http_ports
http_access allow jissou_network jissou_allowlist allowed_https_ports CONNECT
http_access deny all

access_log /var/log/squid/access.log
SQUID_CONFIG

if ! squid -k parse; then
  if [[ -f "${backup_file}" ]]; then
    cp "${backup_file}" "${config_file}"
    echo "Squid configuration is invalid. Restored ${backup_file}." >&2
  fi
  exit 1
fi

systemctl enable squid
systemctl restart squid
echo "Applied the cloud-init Squid configuration."
if [[ -f "${backup_file}" ]]; then
  echo "Backup: ${backup_file}"
fi
