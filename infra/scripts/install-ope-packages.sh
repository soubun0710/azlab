#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE_ROOT="/opt/azlab/packages"

log() {
  printf '[install-ope-packages] %s\n' "$*"
}

fail() {
  printf '[install-ope-packages] ERROR: %s\n' "$*" >&2
  exit 1
}

find_debs() {
  local directory="$1"
  find "$directory" -type f -name '*.deb' -print0 2>/dev/null
}

install_nodejs() {
  local directory="$PACKAGE_ROOT/node"
  local archives=()
  local archive

  [[ -d "$directory" ]] || fail "Node.jsの資材ディレクトリがありません: ${directory}"
  while IFS= read -r -d '' archive; do
    archives+=("$archive")
  done < <(find "$directory" -maxdepth 1 -type f -name 'node-v*-linux-x64.tar.xz' -print0 2>/dev/null)

  ((${#archives[@]} == 1)) || fail "Node.jsのlinux-x64 tar.xzを1つだけ配置してください: ${directory}"
  log "Node.jsを取得済みのtar.xzからインストールします"
  rm -rf /opt/nodejs
  install -d -m 0755 /opt/nodejs
  tar -xJf "${archives[0]}" --strip-components=1 -C /opt/nodejs
  ln -sfn /opt/nodejs/bin/node /usr/local/bin/node
  ln -sfn /opt/nodejs/bin/npm /usr/local/bin/npm
  ln -sfn /opt/nodejs/bin/npx /usr/local/bin/npx
}

install_node_headers() {
  local directory="$PACKAGE_ROOT/node-headers"
  local archives=()
  local archive
  local node_version

  [[ -d "$directory" ]] || fail "Node.jsヘッダーの資材ディレクトリがありません: ${directory}"
  node_version="$(node --version)"
  while IFS= read -r -d '' archive; do
    archives+=("$archive")
  done < <(find "$directory" -maxdepth 1 -type f -name "node-${node_version}-headers.tar.gz" -print0 2>/dev/null)

  ((${#archives[@]} == 1)) || fail "Node.js ${node_version}対応のヘッダーtar.gzを1つだけ配置してください: ${directory}"
  log "Node.jsヘッダーを取得済みのtar.gzからインストールします"
  rm -rf /opt/nodejs-headers
  install -d -m 0755 /opt/nodejs-headers
  tar -xzf "${archives[0]}" --strip-components=1 -C /opt/nodejs-headers
  [[ -f /opt/nodejs-headers/include/node/node.h ]] || fail "Node.jsヘッダーが正しく展開されていません"
}

install_bicep() {
  local directory="$PACKAGE_ROOT/bicep"
  local binaries=()
  local binary

  [[ -d "$directory" ]] || fail "Bicep CLIの資材ディレクトリがありません: ${directory}"
  while IFS= read -r -d '' binary; do
    binaries+=("$binary")
  done < <(find "$directory" -maxdepth 1 -type f -name 'bicep-linux-x64' -print0 2>/dev/null)

  ((${#binaries[@]} == 1)) || fail "Bicep CLIのlinux-x64バイナリを1つだけ配置してください: ${directory}"
  binary="${binaries[0]}"
  log "Bicep CLIを取得済みのバイナリからインストールします"
  install -d -m 0755 /opt/bicep /root/.azure/bin
  install -m 0755 "$binary" /opt/bicep/bicep
  ln -sfnT /opt/bicep/bicep /usr/local/bin/bicep
  ln -sfnT /opt/bicep/bicep /root/.azure/bin/bicep
  [[ -x /usr/local/bin/bicep ]] || fail "Bicep CLIのリンクを作成できません"
  [[ -x /root/.azure/bin/bicep ]] || fail "Azure CLI用Bicep CLIのリンクを作成できません"
}

install_swa_cli() {
  export PATH="/opt/nodejs/bin:$PATH"
  log "SWA CLIをnpmからインストールします"
  npm install --global \
    --allow-scripts=keytar \
    --build-from-source \
    --nodedir=/opt/nodejs-headers \
    @azure/static-web-apps-cli
  install -d -m 0755 /usr/local/bin
  ln -sfnT /opt/nodejs/bin/swa /usr/local/bin/swa
  [[ -x /usr/local/bin/swa ]] || fail "SWA CLIのリンクを作成できません"
}

install_deb_group() {
  local name="$1"
  local directory="$2"
  local debs=()

  [[ -d "$directory" ]] || fail "${name}の資材ディレクトリがありません: ${directory}"
  while IFS= read -r -d '' deb; do
    debs+=("$deb")
  done < <(find_debs "$directory")

  ((${#debs[@]} > 0)) || fail "${name}のdebパッケージがありません: ${directory}"
  log "${name}を取得済みのdebファイルからインストールします"
  dpkg --unpack "${debs[@]}" || true
  dpkg --configure -a
}

verify_command() {
  local name="$1"
  local command_name="$2"

  command -v "$command_name" >/dev/null 2>&1 || fail "${name}のコマンドが見つかりません: ${command_name}"
  log "${name}: $($command_name --version 2>&1 | head -n 1)"
}

[[ -d "$PACKAGE_ROOT" ]] || fail "パッケージ格納先がありません: ${PACKAGE_ROOT}"

export DEBIAN_FRONTEND=noninteractive
install_nodejs
install_node_headers
install_bicep
install_deb_group "Node.jsネイティブモジュールビルドツール" "$PACKAGE_ROOT/build-tools"
install_deb_group "zip" "$PACKAGE_ROOT/zip"
install_deb_group "unzip" "$PACKAGE_ROOT/unzip"
install_deb_group "Azure CLI" "$PACKAGE_ROOT/azure-cli"
install_swa_cli

verify_command "Git" git
verify_command "zip" zip
verify_command "unzip" unzip
verify_command "Node.js" node
verify_command "npm" npm
verify_command "Bicep CLI" bicep
verify_command "SWA CLI" swa
verify_command "Python 3" python3
verify_command "gcc" gcc
verify_command "g++" g++
verify_command "make" make
verify_command "pkg-config" pkg-config
pkg-config --exists libsecret-1 || fail "libsecret-1のpkg-config定義が見つかりません"
log "libsecret-1: $(pkg-config --modversion libsecret-1)"
az version >/dev/null
log "Azure CLI: $(az version --query '"azure-cli"' -o tsv)"
az bicep version >/dev/null
log "すべてのパッケージの導入と確認が完了しました"