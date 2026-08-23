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

export GIT_ASKPASS=/tmp/azlab-git-askpass

cleanup() {
  if [[ -n "${GIT_ASKPASS:-}" ]]; then
    rm -f "$GIT_ASKPASS"
  fi
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

unset GIT_TERMINAL_PROMPT GITHUB_PAT

cd /work/azlab/app/api

npm ci --no-audit --no-fund
npm run build
npm prune --omit=dev

find . -type d -exec chmod 755 {} +
find . -type f -exec chmod 644 {} +

rm -f /work/function-app.zip
zip -r /work/function-app.zip . \
  -x "src/*" \
  -x "tsconfig.json"

if ! az functionapp deployment source config-zip \
  --resource-group azlab-jissou-ap-rg \
  --name azlab-jissou-func \
  --src /work/function-app.zip \
  --build-remote false; then
  printf 'Function deployment failed.\n' >&2
  exit 1
fi

printf 'Function deployment completed successfully.\n'
