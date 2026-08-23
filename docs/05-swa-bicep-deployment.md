# Static Web Apps Bicepデプロイ手順

## 1. 目的

会社で実際に発生した構成を再現するため、公開Cloud ShellからStatic Web Apps（SWA）本体、SWA用Private Endpoint、およびPrivate DNSをBicepで作成する。

会社では公開Cloud Shellの利用が禁止されているが、当時はその統制を把握しておらず、SWA関連リソースだけを公開Cloud Shellから作成していた。この手順は、会社の推奨手順ではなく、その状態を検証環境で再現するためのものである。

## 2. 使用するファイル

```text
infra/bicep/main.bicep
infra/bicep/main.parameters.json
infra/bicep/static-web-app.bicep
infra/bicep/static-web-app-private-endpoint.bicep
```

`main.bicep`をデプロイの入口とし、`main.parameters.json`で環境ごとの値を指定する。SWA本体とPrivate Endpointは、mainからモジュールとしてまとめて実行する。

`static-web-app.bicep`はSWA本体を作成する。

`static-web-app-private-endpoint.bicep`は、既存のVNetとPrivate Endpoint用サブネットを参照してSWA用Private Endpointを作成する。

## 3. 前提条件

次のリソースが事前に存在していることを確認する。

| 項目 | 値 |
| --- | --- |
| SWAのリソースグループ | `azlab-jissou-ap-rg` |
| SWA名 | `azlab-jissou-swa` |
| SWA用Private Endpointのリソースグループ | `azlab-jissou-ap-rg` |
| SWA用Private Endpoint名 | `azlab-jissou-swa-pe` |
| SWAのリージョン | `eastus2` |
| SWA用Private Endpointのリージョン | `japaneast` |
| VNet | `azlab-jissou-vnet` |
| VNetのリソースグループ | `azlab-jissou-network-rg` |
| Private Endpoint用サブネット | `azlab-jissou-pe-snet` |
| Private DNS Zone | `privatelink.azurestaticapps.net` |
| SWA用Private Endpointの接続グループ | `staticSites` |

SWA本体とSWA用Private Endpointは、実装側のリソースグループ`azlab-jissou-ap-rg`へ作成する。VNetとサブネットだけはネットワーク用リソースグループ`azlab-jissou-network-rg`に存在するため、Private Endpoint用Bicepから別リソースグループの既存VNetを参照する。

会社の構成に合わせ、SWA本体は`eastus2`に作成する。Private Endpointは接続先サブネットのある既存VNet側に作成するため、`privateEndpointLocation`は`japaneast`とする。実際の会社構成でSWAの配置リージョンが別途決まっている場合は、パラメータファイルの`location`をそのリージョンへ変更する。

Bicep CLIとAzure CLIが実行できる公開Cloud Shellを使用する。この手順ではOPE VM、固定IPプロキシ、RunShellScriptは使用しない。

```bash
az account show
bicep --version
az version --query '"azure-cli"' --output tsv
```

## 4. デプロイ順序

`main.bicep`を1回適用し、SWA本体とPrivate Endpointをまとめて作成する。内部ではSWA本体を先に作成し、その完了後にPrivate Endpointを作成する。

```text
main.bicep
  ↓
static-web-app.bicep（モジュール）
  ↓
SWA本体
  ↓
static-web-app-private-endpoint.bicep（モジュール）
  ↓
Private Endpoint、Private DNS Zone、VNetリンク
```

Private Endpoint用モジュールは作成されたSWAリソースを参照するため、`main.bicep`ではSWA本体のモジュールへの依存関係を設定している。

## 5. Bicepのビルド

公開Cloud ShellでGitHubから対象ブランチをcloneした後、mainテンプレートをJSONへビルドする。

```bash
bicep build infra/bicep/main.bicep \
  --outfile /work/swa-main.json
```

ビルドに失敗した場合は、validateやwhat-ifを実行せずに停止する。

## 6. SWAとPrivate Endpointのデプロイ

mainテンプレートとパラメータファイルを指定して、SWA本体とPrivate Endpointをまとめてvalidateする。

```bash
az deployment group validate \
  --resource-group azlab-jissou-ap-rg \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.parameters.json
```

次に、what-ifで一括変更内容を確認する。

```bash
az deployment group what-if \
  --resource-group azlab-jissou-ap-rg \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.parameters.json
```

変更内容に問題がなければ、createを1回実行する。

```bash
az deployment group create \
  --resource-group azlab-jissou-ap-rg \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.parameters.json
```

現行の`main.bicep`は、SWAとPrivate Endpointを`azlab-jissou-ap-rg`へ作成する構成を対象とする。

## 8. 作成後の確認

SWA本体とPrivate Endpointの状態を確認する。

```bash
az staticwebapp show \
  --name azlab-jissou-swa \
  --resource-group azlab-jissou-ap-rg \
  --query '{id:id,defaultHostname:defaultHostname,sku:sku.name}'

az network private-endpoint-connection list \
  --name azlab-jissou-swa \
  --resource-group azlab-jissou-ap-rg \
  --type Microsoft.Web/staticSites
```

Private DNS ZoneがVNetへリンクされていることも確認する。

```bash
az network private-dns link vnet list \
  --resource-group <Private DNS Zoneのリソースグループ> \
  --zone-name privatelink.azurestaticapps.net
```

## 9. アプリケーションデプロイとの分離

SWA本体とPrivate Endpointの作成後、アプリケーションはSWA CLIでデプロイする。インフラ用Bicepの実行とアプリケーションデプロイは別ジョブとして扱う。

```text
Bicep
  → SWA本体、Private Endpoint、Private DNS

SWA CLI
  → ビルド済みアプリケーション
```

SWA CLIのデプロイトークンはKey Vaultなどから取得し、Bicepファイル、Git URL、RunShellScript本文、実行ログへ記載しない。
