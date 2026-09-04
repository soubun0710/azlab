#!/usr/bin/env bash
set -euo pipefail
umask 077

log() {
  printf '[deploy-function] %s\n' "$*"
}

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

export GIT_ASKPASS=/tmp/azlab-git-askpass

cleanup() {
  if [[ -n "${GIT_ASKPASS:-}" ]]; then
    rm -f "$GIT_ASKPASS"
  fi
  rm -rf -- /work/azlab
  rm -f -- /work/function-app.zip
  unset GIT_ASKPASS GIT_TERMINAL_PROMPT GITHUB_PAT
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

log "source commit: $(git -C /work/azlab rev-parse HEAD)"

unset GIT_TERMINAL_PROMPT GITHUB_PAT

cd /work/azlab/app/api

log "node: $(node --version), npm: $(npm --version)"

npm ci --no-audit --no-fund
npm run clean
npm run build
npm prune --omit=dev

log 'built Function files:'
find dist/src/functions -maxdepth 1 -type f -name '*.js' -print | sort

if [[ "$(node -p "require('./package.json').main")" != "dist/src/index.js" ]] || [[ ! -f dist/src/index.js ]]; then
  printf 'Function package main is not configured for the compiled entry point.\n' >&2
  exit 1
fi

log 'validating compiled Function syntax'
node --check dist/src/index.js
find dist/src/functions -maxdepth 1 -type f -name '*.js' -exec node --check {} +

find . -type d -exec chmod 755 {} +
find . -type f -exec chmod 644 {} +

rm -f /work/function-app.zip
zip -r /work/function-app.zip . \
  -x "src/*" \
  -x "tsconfig.json" \
  -x ".git/*"

log 'ZIP Function files:'
unzip -Z1 /work/function-app.zip | grep -E '^(dist/src/index\.js|dist/src/functions/.*\.js|package\.json|host\.json)$' | sort

log 'starting Azure ZIP deployment'
deployment_log=/work/function-deployment.log
rm -f "$deployment_log"

if ! az functionapp deployment source config-zip \
  --resource-group azlab-jissou-ap-rg \
  --name azlab-jissou-func \
  --src /work/function-app.zip \
  --build-remote false \
  --debug 2>&1 | tee "$deployment_log"; then
  printf 'Function deployment failed.\n' >&2

  log 'Function App state:'
  az functionapp show \
    --resource-group azlab-jissou-ap-rg \
    --name azlab-jissou-func \
    --query '{state:state, kind:kind, hostNames:hostNames, defaultHostName:defaultHostName}' \
    --output json || true

  log 'Recent deployment records:'
  az functionapp deployment list \
    --resource-group azlab-jissou-ap-rg \
    --name azlab-jissou-func \
    --query '[0:5].{id:id,status:status,active:active,author:author,message:message,complete:complete,receivedTime:receivedTime}' \
    --output json || true

  log 'Relevant deployment log lines:'
  grep -Ei 'error|exception|fail|trigger|sync|oryx|node|main|function' "$deployment_log" | tail -n 120 || true

  exit 1
fi

log 'Function deployment completed successfully.'
