# ope VM設計書

## 1. 目的

実装側VNetに検証用VMを作成し、閉域内からプロキシ経由でパッケージをインストールできるか確認する。
また、外部環境で取得・作成した資材やビルド成果物をStorage Account経由で搬送し、`ope` VMから利用できる構成を検証する。

今回は、まず通常のインストールを試す。インストールできない場合の対応は、検証結果を確認してから決める。

## 2. 構成

```text
実装側VNet
└─ azlab-jissou-ap-snet (10.0.1.0/24)
  └─ azlab-jissou-ope-vm
       ↓ VNet Peering
統制側VNet
└─ azlab-tousei-snet
  └─ azlab-tousei-proxy-vm
    └─ 172.16.1.4:3128
```

`ope` VMからプロキシVMを明示的に指定して外部通信する。VNet Peeringだけで自動的にプロキシ経由になるわけではない。

## 3. VM設定

| 項目 | 設定 |
| --- | --- |
| VM名 | `azlab-jissou-ope-vm` |
| リソースグループ | `azlab-jissou-ap-rg` |
| OS | Ubuntu 24.04 LTS Server |
| VMサイズ | `Standard_B2ts_v2`（検証用） |
| サブネット | `azlab-jissou-ap-snet` |
| Public IP | 付与しない |
| 用途 | パッケージ導入の検証 |
| 管理方法 | Azure PortalのRun Command |
| 自動停止 | 毎日12:00（日本時間） |

アプリケーションをこのVM上で常駐実行することは、今回の対象外とする。

`Standard_B2ts_v2`は検証用のサイズであり、本運用ではそのまま使用しない。SWA CLIの実行、Bicepの適用、Azure CLIによるデプロイ、ビルド処理などを同一VMで実行する場合は、CPU・メモリに余裕のあるサイズへ変更する。
最低でも4 GiBメモリ相当（例：`Standard_B2ls_v2`）を目安とし、複数処理の同時実行や大きなビルドを想定する場合は8 GiBメモリ相当（例：`Standard_B2s_v2`）以上を推奨する。最終的なサイズは、実際の処理量、同時実行数、実行時間およびコストを考慮して決定する。

cloud-initの設定は`infra/conf/ope-cloud-init.yml`に定義し、その内容をBase64エンコードして`infra/arm/09-jissou-ope-vm.json`の`customData`に埋め込む。cloud-initを変更した場合は`customData`も更新する。既存VMには自動反映されないため、変更を適用する場合は`ope` VMを再作成する。

## 4. プロキシ設定

`ope` VMでは、次のプロキシを設定する。

```text
HTTP_PROXY=http://172.16.1.4:3128
HTTPS_PROXY=http://172.16.1.4:3128
```

VMへの接続・操作はSSHを使用せず、Azure PortalのRun Commandで行う。
プロキシ環境変数は初期構築時に`/etc/profile.d/ope-proxy.sh`へ設定する。Azure PortalのRun Commandはログインシェルではないため、外部接続が必要なコマンドでは`. /etc/profile.d/ope-proxy.sh`を先に実行して利用する。

Azure PortalのRun Commandは実行ごとに独立したシェルで起動する。そのため、Azure CLIでAzureリソースを操作する場合は、各Run Commandでプロキシ設定を読み込み、VMのシステム割り当てマネージドIDでログインしてからコマンドを実行する。

```bash
. /etc/profile.d/ope-proxy.sh
timeout 30s az login --identity --allow-no-subscriptions --output none
az account show -o table
```

Metadata Service（`169.254.169.254`）およびPrivate Endpoint経由で接続するStorage AccountのBlobエンドポイント（`azlabjissouopestorage.blob.core.windows.net`）は`NO_PROXY`に設定し、プロキシを経由させない。

## 5. パッケージ導入の確認

GitはUbuntu 24.04 LTSのVMイメージに初期導入済みであることを確認したため、Blobからの導入対象には含めず、利用可能であることだけ確認する。
その他のパッケージはBlobから取得した資材を使用してインストールできるか試す。これらのインストールでは、OPE VMからパッケージ配布元へインターネット経由でアクセスしない。

```text
zip
unzip
azure-cli
Node.js/npm
Bicep CLI
SWA CLI
```

確認する内容は、Gitの利用可否、Blobからの資材取得、インストールの成否、失敗した場合のエラー内容だけとする。zip、unzip、Azure CLI、Node.js/npmの導入ではプロキシ経由の外部通信は行わない。

Bicep CLIは、インターネット接続可能な外部環境でAzure公式GitHub ReleasesからLinux x64版を取得し、Blob Storageの`packages/bicep/bicep-linux-x64`へアップロードする。
OPE VMではパッケージ取得後、インストーラーが`/opt/bicep/bicep`へ配置し、`/usr/local/bin/bicep`および`/root/.azure/bin/bicep`から実行できるようにする。

SWGのルート証明書は、今回の初回検証には含めない。SWA CLIはNode.js/npmの導入後、初期構築時に承認済みのnpmレジストリへプロキシ経由で接続して導入する。

Storage経由の資材取得は、Storage AccountのPrivate Endpoint、Private DNS、`ope` VMのマネージドID、Blob Data ReaderロールをARMテンプレートで設定する。
VMの初回起動時にcloud-initがManaged Identityで認証し、`packages`コンテナーの内容を自動取得する。

```bash
sudo /usr/local/sbin/download-ope-packages
```

上記コマンドは、初回起動時の自動取得が失敗した場合に再実行するための手動確認用である。このスクリプトはManaged IdentityでAzure Storage REST APIを認証し、`packages`コンテナーの内容を`/opt/azlab/packages`へ取得する。

## 6. 資材保管用Storage Account

外部環境で事前に取得したパッケージ、ツール、ビルド成果物などを保管し、閉域側の`ope` VMへ搬送するために、実装側のリソースグループへStorage Accountを作成する。

| 項目 | 設定 |
| --- | --- |
| ARMテンプレート | `07-jissou-ope-storage.json` |
| リソースグループ | `azlab-jissou-ap-rg` |
| 種別 | `StorageV2` |
| SKU | `Standard_LRS` |
| Blob公開アクセス | 無効 |
| パブリックネットワークアクセス | 無効 |
| 認証 | Microsoft Entra IDによるOAuth/RBAC |
| 接続方式 | `azlab-jissou-pe-snet`へのPrivate Endpoint |
| Blobコンテナー | `packages`（非公開） |

`ope` VMからStorage Accountへ接続するため、Storage Accountの作成後にBlob用Private EndpointとPrivate DNSを追加する。Private Endpointが接続されるまでは、`ope` VMから資材を取得できない。

資材搬送の基本的な流れは次のとおりとする。

```text
外部環境
  └─ 資材・ビルド成果物をStorage Accountへ配置
       ↓ Private Endpoint
実装側VNet
  └─ ope VMから資材を取得して利用
```

`ope` VMにはマネージドIDを付与し、Storage AccountのBlobデータ閲覧者など、必要最小限のRBACロールを割り当てる。共有キーやStorage Accountキーは使用しない。

### 6.1 配置する資材

接続可能な環境で資材を取得し、Storage Accountへ配置する。`ope` VMではStorage Accountから取得した資材を使用し、閉域側からパッケージ配布元へ直接アクセスしない。

| 資材 | 用途 | 取得元 | 保管形式 |
| --- | --- | --- | --- |
| zip | 資材・デプロイパッケージ作成 | [Ubuntu package archive](https://packages.ubuntu.com/noble/zip) | Ubuntu 24.04向けdebパッケージ |
| unzip | ZIP資材の展開 | [Ubuntu package archive](https://packages.ubuntu.com/noble/unzip) | Ubuntu 24.04向けdebパッケージ |
| Azure CLI | Azureリソース操作・認証 | [Azure CLI Linuxインストール手順](https://learn.microsoft.com/ja-jp/cli/azure/install-azure-cli-linux) | debパッケージと依存パッケージ |
| Bicep CLI | Azureリソース定義のビルド・デプロイ | [Bicep Releases](https://github.com/Azure/bicep/releases) | Linux x64バイナリ |
| Node.js/npm | npmを使用するツールの実行環境 | [Node.js公式サイト](https://nodejs.org/ja) | Linux x64バイナリ（npm同梱） |

Azure CLIの公式ドキュメントに明記されている対応OSはUbuntu 22.04と24.04であり、26.04は明記されていない。そのため、本検証では未記載の26.04ではなく、対応が明記されているUbuntu 24.04 LTSを採用する。
これに合わせて、zipとunzipもUbuntu 24.04 LTS向けの資材を使用し、Ubuntu公式パッケージアーカイブの`noble`（24.04 LTS）から取得する。GitはVMイメージに初期導入済みのものを使用することを確認済みである。

使用するバージョンを固定し、`packages`コンテナー内の各製品フォルダー直下に配置する。

```text
packages/
├─ node/node-v*-linux-x64.tar.xz
├─ zip/*.deb
├─ unzip/*.deb
├─ azure-cli/*.deb
└─ bicep/bicep-linux-x64
```
