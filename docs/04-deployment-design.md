# デプロイ設計書

## 1. 目的

ネットワーク制約のある環境から、GitHubのソースを取得してビルドし、Azureへデプロイする方式を定義する。
対象とする処理は、初回作成時のBicepによるインフラ適用、Static Web Appsへのデプロイ、Function AppへのZIPデプロイとする。
作成後のSWA設定変更はBicepで管理せず、Azureポータルから手動で行う。

本構成では、GitHubのIP制限に対応するため、GitHubへの接続をOPE VMから固定IPのプロキシ経由で行う。現環境ではAzure DevOps Pipelineは採用せず、Azure PortalのRun CommandからOPE VM内のスクリプトを実行する。

## 2. 基本構成

```text
Azure Portal Run Command
  ↓ Azure Resource Manager
OPE VM
  ├─ プロキシ経由でGitHubからclone
  ├─ ビルド・デプロイ処理
  └─ Managed IdentityでAzureへ接続
       ↓ HTTP／HTTPSプロキシ
固定IPのプロキシVM
       ↓ 固定された送信元IP
GitHub
```

OPE VMからAzureリソースを操作する通信は、VMのシステム割り当てManaged Identityで認証する。GitHubへの認証方式はPATを採用し、その値はKey Vaultで管理する。PATをスクリプトやURLへ直接記載しない。

## 3. 実行方式

### 3.1 検証段階

検証段階では、Azure PortalのRun CommandからOPE VM上のスクリプトを実行する。Run Commandは実行ごとに独立したシェルであるため、Azure CLIを使用する処理では毎回プロキシ設定を読み込み、Managed Identityでログインする。

デプロイ用スクリプトはAzure PortalのRun CommandからOPE VM上で実行する。OPE VMからGitHubへは固定IPのプロキシ経由で接続し、PATはKey VaultからManaged Identityで取得する。

```bash
. /etc/profile.d/ope-proxy.sh
timeout 30s az login --identity --allow-no-subscriptions --output none
```

GitHubからcloneする処理では、`/etc/profile.d/ope-proxy.sh`を読み込んだシェルからGitを実行する。作業終了後は、成果物を保存してから作業領域を削除する。

### 3.2 Azure DevOps Pipelineの扱い

Azure DevOps Pipelineは、現環境では保留とする。Hosted Agentは会社環境の利用許可がなく、Self-hosted AgentはOPE VMから`dev.azure.com`への通信許可を申請できないため、どちらも実行基盤として成立しない。

Pipelineは現環境の検証手順には含めない。Pipelineを再検討する条件は、Hosted Agentの利用許可、またはOPE VMからAzure DevOps関連エンドポイントへのアウトバウンド通信経路が会社の正式な手続きで確保された場合とする。

現時点の実行経路は次のとおりである。

```text
Azure Portal Run Command
  ↓ Azure Resource Manager
OPE VM上のスクリプト
  ↓ 固定IPプロキシ
GitHub
```

## 4. GitHub接続とシークレット管理

GitHubへの接続は、OPE VMから固定IPのプロキシVMを経由する。GitHubのホスト名は`NO_PROXY`へ設定せず、プロキシを経由させる。
PATを保管するKey VaultはPrivate EndpointとPrivate DNSを使用する。また、Azure Portalのブラウザーからシークレットを登録・確認できるよう、公開ネットワークアクセスも有効にする。

Key Vault名は`azlab-jissou-ope-kv`とする。Key Vaultは`infra/arm/10-jissou-ope-keyvault.json`で作成し、Key Vault用のPrivate EndpointとPrivate DNSは`infra/arm/11-jissou-ope-keyvault-private-endpoint.json`で作成する。

GitHub接続用のPATはKey Vaultのシークレットとして保管する。PATを登録・更新する管理者または管理用Pipelineには、対象Key Vaultに対する`Key Vault Secrets Officer`などのシークレット書き込み権限を付与する。
OPE VMのManaged Identityには、シークレット取得専用の`Key Vault Secrets User`を付与する。

PATは、次の場所へ出力・保存しない。

```text
Git URL
Pipelineログ
Run Command本文
cloud-initのcustomData
```

Git cloneはKey Vaultから取得したPATを一時的な認証ヘルパー経由で使用し、処理終了時に認証ヘルパーとPATを保持する環境変数を破棄する。

## 5. 作業領域と後処理

Gitの作業ツリー、中間生成物、デプロイ用ZIPは、ジョブ単位の一時ディレクトリへ配置する。

```text
/work/jobs/<job-id>/
├─ source/
├─ build/
└─ output/
```

OSディスクの肥大化を防ぐため、作業完了時だけでなく、成功・失敗のどちらでも作業領域を削除する。スクリプトでは終了処理を登録して必ず削除する。

```bash
WORK_DIR="/work/jobs/${JOB_ID}"
trap 'rm -rf -- "$WORK_DIR"' EXIT
```

調査に必要なログやデプロイ成果物は、削除前にBlob Storageへ保存する。Blobのパスにはリポジトリ、ブランチ、コミットID、ジョブIDなどを含め、成果物を上書きしないようにする。

```text
artifacts/<repository>/<branch>/<commit-id>/<job-id>/
```

`/tmp`は小規模な検証には利用できるが、本番のビルド領域には使用しない。容量とI/O性能を確保するため、専用データディスクを`/work`へマウントする。

## 6. Bicepの初回適用

BicepはSWAなどのインフラを初回作成するときに使用する。初回適用は管理者が手動で実行し、Bicepの適用とアプリケーションデプロイは別の作業として扱う。

```text
管理者が対象ブランチを取得
  ↓
az bicep build
  ↓
az deployment group validate
  ↓
az deployment group what-if
  ↓
管理者がwhat-ifを確認
  ↓
az deployment group create
  ↓
az deployment group create
```

Azure CLIを使用するため、各ジョブで次を実行する。

```bash
. /etc/profile.d/ope-proxy.sh
timeout 30s az login --identity --allow-no-subscriptions --output none
```

`what-if`で想定外の削除（`-`）や変更（`~`）が検出された場合は、初回作成を停止する。内容を確認した管理者が`az deployment group create`を手動実行する。
作成後のSWA設定変更はBicepで再適用せず、Azureポータルで行う。PipelineによるBicep適用はこの設計の対象外とする。

デプロイモードは原則として`Incremental`を使用する。禁止するリージョン、リソース種別、設定はAzure Policyでも制御する。

## 7. Static Web Appsデプロイ

```text
GitHubから指定ブランチをclone
  ↓
npm install / npm run build
  ↓
SWA CLIでデプロイ
  ↓
作業領域削除
```

SWA CLIはOPE VMへオフライン資材とプロキシ経由のnpmインストールで導入済みとする。デプロイ用トークンはKey Vaultから取得し、ログへ出力しない。

SWA CLIの実行時も、GitHubからのcloneとnpmなど外部接続を伴う処理ではプロキシ設定を読み込む。デプロイ処理の実行方法やトークンの渡し方は、対象のStatic Web Appsの認証方式に合わせて決定する。

## 8. Function App ZIPデプロイ

```text
GitHubから指定ブランチをclone
  ↓
npm install / npm run build
  ↓
Function App用ZIPを作成
  ↓
az functionapp deployment source config-zip
  ↓
作業領域削除
```

Azure CLIによるデプロイなので、プロキシ設定を読み込み、Managed Identityでログインしてから実行する。

```bash
. /etc/profile.d/ope-proxy.sh
timeout 30s az login --identity --allow-no-subscriptions --output none
az functionapp deployment source config-zip \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --src <function-app.zip>
```

Managed Identityには、対象Function Appのデプロイに必要な権限だけを付与する。検証では対象リソースグループに限定した権限を使用し、本番では対象リソースや操作に合わせて権限を細分化する。

## 9. 必要なAzure権限

| 用途 | 対象 | 権限の例 |
| --- | --- | --- |
| 資材取得 | パッケージ用Storage Account | `Storage Blob Data Reader` |
| GitHub用PAT登録・更新 | Key Vault | `Key Vault Secrets Officer`など |
| GitHub用PAT取得 | Key Vault | `Key Vault Secrets User` |
| リソース参照・What-if | 対象サブスクリプションまたはリソースグループ | `Reader`相当 |
| Bicepデプロイ | 対象リソースグループ | `Contributor`またはカスタムロール |
| Function App ZIPデプロイ | 対象Function App | 必要なWeb App操作権限 |
| SWAデプロイ | 対象Static Web Apps | トークンまたは対象リソースの必要権限 |

`Owner`や`User Access Administrator`をOPE VMのManaged Identityへ付与しない。RBACの割り当ては、管理者が別の管理経路から実施する。

## 10. 障害時の停止条件

次のいずれかに該当する場合は、デプロイを実行せず停止する。

- GitHubのcloneに失敗した
- PATまたはデプロイトークンを取得できない
- Bicepのbuildまたはvalidateに失敗した
- What-ifで想定外の削除・変更が検出された
- 対象ブランチ、コミットID、デプロイ先が特定できない
- ビルドまたはZIP作成に失敗した
- Azure CLIの認証に失敗した

失敗時は、秘密情報を含まない実行ログとエラー情報だけを保存し、作業領域を削除する。

## 11. 段階的な導入

最初は、現在のOPE VMでRun CommandからGit clone、BicepのWhat-if、SWA CLI、Function App ZIPデプロイを個別に検証する。
検証が完了したら、ジョブ用スクリプトへ共通処理をまとめ、引き続きAzure PortalのRun Commandから実行する。Azure DevOps Pipelineへの移行は、会社環境で必要な通信と実行基盤の許可が得られた場合に改めて検討する。
