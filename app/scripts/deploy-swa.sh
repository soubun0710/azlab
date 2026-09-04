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

export SWA_DEPLOYMENT_TOKEN="$(
  az staticwebapp secrets list \
    --resource-group azlab-jissou-ap-rg \
    --name azlab-jissou-swa \
    --query properties.apiKey \
    --output tsv
)"

export GIT_ASKPASS=/tmp/azlab-git-askpass

cleanup() {
  if [[ -n "${GIT_ASKPASS:-}" ]]; then
    rm -f "$GIT_ASKPASS"
  fi
  rm -rf -- /work/azlab
  unset GIT_ASKPASS GIT_TERMINAL_PROMPT GITHUB_PAT SWA_DEPLOYMENT_TOKEN
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

if ! npx --yes @azure/static-web-apps-cli@latest deploy \
  /work/azlab/app/frontend \
  --deployment-token "$SWA_DEPLOYMENT_TOKEN" \
  --env production \
  --verbose; then
  printf 'SWA deployment failed.\n' >&2
  exit 1
fi

printf 'SWA deployment completed successfully.\n'
