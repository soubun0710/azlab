#!/usr/bin/env bash
set -euo pipefail
umask 077

. /etc/profile.d/ope-proxy.sh

timeout 30s az login \
  --identity \
  --allow-no-subscriptions \
  --output none

export GITHUB_PAT="$(
  az keyvault secret show \
    --vault-name azlab-jissou-ope-kv \
    --name github-pat \
    --query value \
    --output tsv
)"

export SWA_ALLOWED_IP_RANGES="$(
  az keyvault secret show \
    --vault-name azlab-jissou-ope-kv \
    --name swa-allowed-ip-ranges \
    --query value \
    --output tsv
)"

export SWA_DEPLOYMENT_TOKEN="$(
  az staticwebapp secrets list \
    --resource-group azlab-jissou-ap-rg \
    --name azlab-jissou-swa \
    --query properties.apiKey \
    --output tsv
)"

: "${SWA_ALLOWED_IP_RANGES:?Set SWA_ALLOWED_IP_RANGES to comma-separated IPv4 CIDR blocks before deploying}"

export GIT_ASKPASS=/tmp/azlab-git-askpass

cleanup() {
  if [[ -n "${GIT_ASKPASS:-}" ]]; then
    rm -f "$GIT_ASKPASS"
  fi
  rm -rf -- /work/azlab
  unset GIT_ASKPASS GIT_TERMINAL_PROMPT GITHUB_PAT SWA_DEPLOYMENT_TOKEN SWA_ALLOWED_IP_RANGES
}
trap cleanup EXIT

cat > "$GIT_ASKPASS" <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' 'soubun0710' ;;
  *Password*) printf '%s\n' "$GITHUB_PAT" ;;
esac
EOF

chmod 700 "$GIT_ASKPASS"
export GIT_TERMINAL_PROMPT=0

rm -rf /work/azlab
git clone https://github.com/soubun0710/azlab.git /work/azlab

unset GIT_TERMINAL_PROMPT GITHUB_PAT

SWA_CONFIG=/work/azlab/app/frontend/staticwebapp.config.json
SWA_ALLOWED_IP_RANGES="$SWA_ALLOWED_IP_RANGES" SWA_CONFIG="$SWA_CONFIG" node <<'NODE'
const fs = require('node:fs');

const configPath = process.env.SWA_CONFIG;
const allowedIpRanges = process.env.SWA_ALLOWED_IP_RANGES
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);

if (allowedIpRanges.length === 0) {
  throw new Error('SWA_ALLOWED_IP_RANGES must contain at least one CIDR block');
}

const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
config.networking = {
  ...(config.networking ?? {}),
  allowedIpRanges,
};
fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
NODE

if ! npx --yes @azure/static-web-apps-cli@latest deploy \
  /work/azlab/app/frontend \
  --deployment-token "$SWA_DEPLOYMENT_TOKEN" \
  --env production \
  --verbose; then
  printf 'SWA deployment failed.\n' >&2
  exit 1
fi

printf 'SWA deployment completed successfully.\n'
