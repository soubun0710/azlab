# Function App ARMデプロイ設計

## 1. 目的

SWA管理のFunctionではなく、独立したAzure FunctionsのFunction AppをARMテンプレートで作成する。SWAのAPIバックエンドには、この独立Functionを統合する。

Function Appの実行時にプロキシ経由でインターネットへ接続するため、Function AppをVNet統合する。アプリケーションはビルド後にZIPとしてFunction Appへデプロイする。

この構成は、会社で使用している独立Function Appの構成と、SWA管理のFunctionではVNet統合を利用できないという制約を再現するためのものである。

## 2. SWA管理Functionを使用しない理由

SWAに組み込まれた管理Functionは、SWAのバックエンド機能として提供される。独立したFunction Appリソースではないため、Function App側でVNet統合やApp Serviceのネットワーク設定を管理する構成にはできない。

プロキシ経由の外部通信が必要なFunctionをVNet統合するため、`Microsoft.Web/sites`として独立したFunction Appを作成する。

```text
SWA
  └─ 静的Webコンテンツを提供

独立Function App
  └─ APIやバックエンド処理を実行
  └─ VNet統合
  └─ VNet経由でプロキシへ接続

SWA
  └─ /api/* を独立Function Appへ転送
```

## 3. 作成するリソース

ARMテンプレートで次のリソースを作成する。

| リソース | 種類 | 用途 |
| --- | --- | --- |
| App Service Plan | `Microsoft.Web/serverfarms` | Function Appの実行基盤 |
| Function用Storage Account | `Microsoft.Storage/storageAccounts` | Functionsランタイム、トリガー、デプロイ資材など |
| Functionデプロイ用Blobコンテナー | `Microsoft.Storage/storageAccounts/blobServices/containers` | Flex Consumptionのデプロイパッケージ保存 |
| VNet統合用サブネット | `Microsoft.Network/virtualNetworks/subnets` | Function AppからVNetへ接続 |
| Function App | `Microsoft.Web/sites` | 独立したFunction App |
| SWA APIバックエンドリンク | `Microsoft.Web/staticSites/linkedBackends` | SWAから独立Function AppへAPIを転送 |
| Log Analytics Workspace | `Microsoft.OperationalInsights/workspaces` | Application Insightsのログ格納先 |
| Application Insights | `Microsoft.Insights/components` | 実行ログと監視（必要時） |

Function用Storage Accountは、OPE VMのパッケージ搬送用Storage Accountとは分離する。用途と権限を分け、Functionランタイム用Storageをアプリケーション運用から独立して管理する。
Flex Consumptionのデプロイパッケージを格納するBlobコンテナー`function-deploy`も同じ先行ARMで作成する。

## 4. 配置先

| 項目 | 値 |
| --- | --- |
| リソースグループ | `azlab-jissou-ap-rg` |
| Function App名 | `azlab-jissou-func` |
| Flex Consumptionプラン名 | `azlab-jissou-func-plan` |
| Function用Storage Account名 | `azlabjissoufuncst` |
| リージョン | `japaneast` |
| VNet | `azlab-jissou-vnet` |
| VNetのリソースグループ | `azlab-jissou-network-rg` |
| Function統合用サブネット | `azlab-jissou-func-snet` |
| Function統合用サブネットのアドレス | `10.0.3.0/26` |
| App Service Plan SKU | `FC1`（Flex Consumption） |
| OS | Linux |
| Functionランタイム | Node.js 22 |
| SWA API統合 | `azlab-jissou-swa`から`azlab-jissou-func`へリンク |

既存の`azlab-jissou-ap-snet`はOPE VMなどのアプリケーション用、`azlab-jissou-pe-snet`はPrivate Endpoint用として使用している。Function AppのVNet統合には専用サブネットを使用し、Private Endpoint用サブネットやOPE VM用サブネットと共有しない。

## 5. VNet統合用サブネット

Function AppのVNet統合用サブネットには、App Serviceの委任を設定する。

```text
Subnet: azlab-jissou-func-snet
CIDR: 10.0.3.0/26
Delegation: Microsoft.App/environments
```

VNet統合用サブネットには、Private Endpoint用の`privateEndpointNetworkPolicies`を設定しない。Private Endpoint用サブネットとは用途が異なるため、同じサブネットを使用しない。

Function AppからプロキシVMへ接続するには、VNet PeeringとNSGの通信許可が必要である。プロキシVMの待受アドレスとポートは会社構成に合わせる。

```text
Function App
  ↓ VNet統合
10.0.3.0/26
  ↓ VNet Peering
172.16.1.4:3128
```

Function Appのアプリケーション設定には、必要に応じて次のプロキシ環境変数を設定する。

```text
HTTP_PROXY=http://172.16.1.4:3128
HTTPS_PROXY=http://172.16.1.4:3128
```

実行するライブラリがプロキシ環境変数を使用することを確認する。Azure Functionsのすべての通信が自動的にプロキシを通るわけではないため、アプリケーションまたは利用ライブラリ側のプロキシ対応も検証する。

### NSGとProxy ACL

VNet統合はFunctionからのアウトバウンド接続をVNetへ出す機能であり、Function統合用サブネットへ外部から接続を受ける機能ではない。そのため、Function統合用サブネットには、動作確認を兼ねてInboundの最優先に全拒否ルールを配置する。SWAからFunction AppへのHTTPリクエストは、Function Appの公開エンドポイントおよびSWAのlinked backendで処理され、VNet統合サブネットのInbound NSGルールは経由しない。

Proxy VM側の`azlab-tousei-nsg`は、会社構成に合わせて実装側VNet全体からProxy VMのTCP 3128へのInboundを許可する。Function用に個別のNSGルールは追加せず、送信元を`10.0.0.0/16`とする。

```text
Source: 10.0.0.0/16（実装側VNet全体）
Destination: 172.16.1.4
Protocol: TCP
Destination port: 3128
Direction: Inbound（Proxy VM側）
Access: Allow
```

Function統合用サブネット側のOutboundは、NSGで明示的に拒否していなければAzureの既定ルールで許可される。今回の全拒否ルールはInboundだけなので、Proxy VMへのOutbound通信には影響しない。Proxy VMのNSGがVNet全体を許可していても、SquidのACLは別の制御であるため、`10.0.3.0/26`からの接続が許可されていることを確認する。NSGだけ許可しても、Squid ACLが拒否すればProxy通信は成立しない。

## 6. ARMテンプレートの構成

Function AppのARMテンプレートは、先行リソースの作成後に適用する。SWA API統合のリンクは、Function Appの作成後にSWA側のリソースとして作成する。

```text
先行ARM（`12-jissou-function-prerequisites.json`）: Storage Account / Blobコンテナー / Log Analytics / Application Insights
  ↓
Function用Storage Account
        ↓
App Service Plan
        ↓
Function App
        ↓
VNet統合設定
  ↓
SWA APIバックエンドリンク
```

Flex Consumptionでは、従来のPremium用プランではなく、`Microsoft.Web/serverfarms`の`FC1`プランを使用する。Function Appは`Microsoft.Web/sites`として作成し、次の設定を行う。Flex ConsumptionのVNet統合には、サブスクリプションで`Microsoft.App`リソースプロバイダーを登録しておく。

```text
kind: functionapp,linux
reserved: true
serverFarmId: App Service PlanのリソースID
siteConfig: HTTPS、アプリケーション設定
functionAppConfig: Node.js 22、Flex用デプロイStorage、スケール設定
Microsoft.Web/sites/virtualNetworkConnections: VNet統合用サブネットのリソースID
```

Flex ConsumptionのデプロイStorageは、通常の`WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`ではなく、Flex用の`functionAppConfig.deployment.storage`で指定する。ARMテンプレートでは、Storage Account、Blobコンテナー、Function Appのシステム割り当てManaged Identity、およびBlob Data Owner相当の権限を依存関係付きで定義する。

VNet統合は`Microsoft.Web/sites/virtualNetworkConnections`の子リソースで指定する。`virtualNetworkSubnetId`をFunction App本体の`siteConfig`へ記載する方式は採用しない。Flex Consumptionの統合先サブネットは`Microsoft.App/environments`へ委任する。

### SWA API統合

SWAの`/api/*`へのリクエストを独立Functionへ転送するため、SWAの`linkedBackends`を使用する。リンク先は`azlab-jissou-func`のリソースIDとし、Function側のHTTPトリガーをAPIの入口にする。

```text
Browser
  ↓
SWA /api/*
  ↓ linkedBackends
独立Function App（Node.js 22 / Flex Consumption）
  ↓ VNet統合
Proxy VM（172.16.1.4:3128）
```

現在のSWAは`eastus2`、既存VNetとFunctionの配置候補は`japaneast`である。SWAのlinked backendにリージョン制約がある場合、この組み合わせでは直接統合できない。その場合は、SWAとFunctionを同一リージョンへ揃えるか、SWAとFunctionの間にAPI Managementなどの公開API入口を置く。ARM適用前に、対象APIバージョンで`Microsoft.Web/staticSites/linkedBackends`が異なるリージョンのFunctionを受け付けるか確認する。

Storage Accountの接続情報などの秘密値はARMテンプレートへ直接記載しない。Managed IdentityとKey Vault参照を優先し、どうしても必要なデプロイパラメーターは保護されたパラメーターとして扱う。

## 7. ARMデプロイの確認

ARMテンプレートの適用前に、Cloud Shellなど許可された実行環境からvalidateとwhat-ifを実行する。

```bash
az deployment group validate \
  --resource-group azlab-jissou-ap-rg \
  --template-file function-app.json \
  --parameters @function-app.parameters.json

az deployment group what-if \
  --resource-group azlab-jissou-ap-rg \
  --template-file function-app.json \
  --parameters @function-app.parameters.json
```

what-ifで予期しない削除や変更がないことを確認した後、ARMテンプレートを適用する。

```bash
az deployment group create \
  --resource-group azlab-jissou-ap-rg \
  --template-file function-app.json \
  --parameters @function-app.parameters.json
```

## 8. VNet統合の確認

Function Appが想定したサブネットへ統合されていることを確認する。

```bash
az functionapp vnet-integration list \
  --resource-group azlab-jissou-ap-rg \
  --name azlab-jissou-func \
  --output table
```

VNet側では、Function統合用サブネットの委任とアドレス範囲を確認する。

```bash
az network vnet subnet show \
  --resource-group azlab-jissou-network-rg \
  --vnet-name azlab-jissou-vnet \
  --name azlab-jissou-func-snet \
  --query '{addressPrefix:addressPrefix,delegations:delegations[].serviceName}'
```

## 9. ZIPデプロイ

Function Appのインフラ作成後、OPE VMでGitHubから対象リポジトリを`clone`し、デプロイ用のソースZIPを作成してAzure CLIでデプロイする。依存パッケージのインストールとビルドはAzure側で実行するため、OPE VMからnpmレジストリへの通信は不要とする。

```text
OPE VMでProxy設定を読み込む
  ↓
GitHubから対象リポジトリをclone
  ↓
Function App用のソースZIPを作成
  ↓
az functionapp deployment source config-zip
```

OPE VMからZIPをアップロードする場合は、OPE VMのプロキシ設定を読み込んでAzure CLIへログインする。これはFunction Appの実行時通信とは別の経路である。

```bash
. /etc/profile.d/ope-proxy.sh
timeout 30s az login --identity --allow-no-subscriptions --output none

az functionapp deployment source config-zip \
  --resource-group azlab-jissou-ap-rg \
  --name azlab-jissou-func \
  --src /work/function-app.zip \
  --build-remote true
```

ZIPとビルド作業領域はジョブ単位の一時ディレクトリへ配置し、成功・失敗にかかわらず終了時に削除する。デプロイログにはFunction Appのキー、Storage接続文字列、Key Vaultのシークレットを出力しない。

## 10. 通信経路の確認

Function Appの実行時に外部通信が必要な場合、次の経路を成立させる。

```text
Function App
  ↓ VNet統合
azlab-jissou-vnet / azlab-jissou-func-snet
  ↓ VNet Peering
azlab-tousei-vnet
  ↓
azlab-tousei-proxy-vm（172.16.1.4:3128）
  ↓
インターネット
```

VNet統合だけでは通信が自動的にプロキシ経由にはならない。アプリケーション設定、ライブラリの挙動、プロキシVMのNSG、VNet Peering、ルートおよびプロキシ設定を個別に確認する。

## 11. 確認項目

- 独立したFunction Appとして作成されている
- Function App名が`azlab-jissou-func`である
- Flex Consumptionの`FC1`プランで作成されている
- Node.js 22で起動している
- Function Appが`azlab-jissou-func-snet`へVNet統合されている
- サブネットが`10.0.3.0/26`である
- サブネットに`Microsoft.App/environments`の委任がある
- Function統合用サブネットNSGのpriority `100`でInbound全拒否が設定されている
- Proxy VM側NSGで`10.0.0.0/16`からTCP 3128へのInboundが許可されている
- Squid ACLで`10.0.3.0/26`からの接続が許可されている
- SWAの`/api/*`が独立Function Appへ転送される
- SWAとFunctionのリージョン制約を満たしている
- Function Appの実行時にProxy設定が使用される
- Proxy VMのNSGでFunction統合用サブネットからの通信が許可される
- GitHubから取得したアプリケーションをビルドできる
- ZIPをFunction Appへアップロードできる
- ZIPデプロイ後にFunctionが起動する
- 秘密情報がARMテンプレート、ZIP、ログへ出力されていない
