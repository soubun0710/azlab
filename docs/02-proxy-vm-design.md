# プロキシ設計書

## 1. 目的

統制側VNetに明示的プロキシを配置し、実装側の検証用実行環境からプロキシ経由で外部通信できる構成を作る。

本設計書では、プロキシVMとその通信経路、アクセス制御、初期検証範囲を定義する。

## 2. 構成

プロキシは統制側VNetの `azlab-tousei-snet` に配置する。

```text
実装側の検証用実行環境
  └─ HTTP／HTTPSプロキシ設定: 172.16.1.4:3128
       └─ VNet Peering
            └─ 統制側のプロキシVM（Squid）
                 └─ Public IPを送信元とする外向き通信
                      └─ 外部サービス
```

VNet PeeringはVNet間の到達性を提供するだけで、通信を自動的にプロキシ経由へ変更しない。実装側の検証用実行環境や各ツールにプロキシを明示設定する。

## 3. リソース

| リソース | 名称 | 配置先 | 用途 |
| --- | --- | --- | --- |
| 仮想マシン | `azlab-tousei-proxy-vm` | `azlab-tousei-rg` | Squidを実行するプロキシサーバー |
| ネットワークインターフェース | `azlab-tousei-proxy-nic` | `azlab-tousei-rg` | プロキシVMを`azlab-tousei-snet`へ接続 |
| Public IP | `azlab-tousei-proxy-pip` | `azlab-tousei-rg` | プロキシVMの外向き通信の送信元 |
| Auto-shutdownスケジュール | `shutdown-computevm-azlab-tousei-proxy-vm` | `azlab-tousei-rg` | 毎日12:00（日本時間）にプロキシVMを停止（割り当て解除） |

Auto-shutdownスケジュール名は、ARMの一般仕様でこの形式が必須と確認できたものではない。
ただし、今回のAzure環境では別の名前を指定すると`InvalidScheduleId`になったため、現状はAzure側が要求しているらしい`shutdown-computevm-<VM名>`形式を使用する。
原因は未特定であり、PortalまたはAuto-shutdown機能側の内部的な関連付けによる可能性がある。

プロキシVMへのSSH接続は使用しない。VMの管理操作やSquidの設定変更は、Azure PortalのRunShellScriptを使用する。

## 4. 仮想マシン

| 項目 | 設定 |
| --- | --- |
| OS | Ubuntu 22.04 LTS Server |
| 用途 | SquidによるHTTP／HTTPSプロキシ |
| プロキシソフトウェア | Squid |
| 待受ポート | TCP 3128 |
| プライベートIP | `172.16.1.4` 固定 |
| 配置サブネット | `azlab-tousei-snet` |
| VMサイズ | 無料枠と試用クレジットを確認して決定 |

## 5. NSGルール

| NSG | 方向 | ルール名 | 優先度 | プロトコル／ポート | 接続元 | 接続先 | アクション |
| --- | --- | --- | ---: | --- | --- | --- | --- |
| `azlab-tousei-nsg` | 受信 | `allow-proxy-from-jissou` | 100 | TCP / 3128 | `10.0.1.0/24` | `172.16.1.0/24` | 許可 |

## 6. Squid設定

初期段階では、Squidを明示的HTTP／HTTPSプロキシとして使用する。プロキシVM上で設定ファイルを管理し、許可する接続元と宛先ポートを限定する。

### 6.1 基本設定

| 項目 | 設定 |
| --- | --- |
| 待受ポート | TCP 3128 |
| 許可する接続元 | `10.0.1.0/24` |
| 許可する宛先ポート | HTTP 80、HTTPS 443 |
| 認証 | 初期段階では使用しない |
| 透過プロキシ | 使用しない |
| ログ | Squidのアクセスログを使用する |

### 6.2 ACL定義

Squidでは、jissou側の許可FQDNを1つのACL `jissou_allowlist` として管理する。許可対象が増えた場合は、jissou許可リストへFQDNを1行ずつ追加する。

#### 接続元ACL

| ACL名 | CIDR | 用途 |
| --- | --- | --- |
| `jissou_network` | `10.0.1.0/24` | 実装側サブネットからの要求 |

#### jissou許可リスト

| FQDN | 用途 |
| --- | --- |
| `github.com` | Gitリポジトリのclone |
| `graph.microsoft.com` | Microsoft Graph API |
| `login.microsoftonline.com` | Microsoft Entra ID認証 |
| `fukuoka-fg.ghe.com` | GitHub Enterprise |
| `management.azure.com` | Azure Resource Manager API |
| `management.core.windows.net` | Azure管理API |
| `registry.npmjs.org` | npmレジストリ |
| `*.azurewebsites.net` | Azure App Service関連通信 |
| `aka.ms` | Microsoft短縮URL・リダイレクト |
| `*.azurefd.net` | Azure Front Door関連通信 |
| `json.schemastore.org` | JSONスキーマ取得 |
| `*.azureedge.net` | Azure CDN関連通信 |
| `*.azurestaticapps.net` | Azure Static Web Apps関連通信 |

上記のFQDNを `jissou_allowlist` ACLに登録する。許可対象を追加する場合は、この一覧にFQDNを追加する。

#### 宛先ポートACL

| ACL名 | ポート | 用途 |
| --- | ---: | --- |
| `allowed_http_ports` | 80 | HTTP通信 |
| `allowed_https_ports` | 443 | HTTPSのCONNECT通信 |

### 6.3 許可ルール

許可ルールは、1つの通信ポリシーにつき1行で管理する。

| ルール名 | 接続元ACL | FQDN ACL | 宛先ポートACL | HTTPメソッド | アクション | 用途 |
| --- | --- | --- | --- | --- | --- | --- |
| `allow-jissou-allowlist-http` | `jissou_network` | `jissou_allowlist` | `allowed_http_ports` | すべて | 許可 | jissou許可リストへのHTTP通信 |
| `allow-jissou-allowlist-https` | `jissou_network` | `jissou_allowlist` | `allowed_https_ports` | `CONNECT` | 許可 | jissou許可リストへのHTTPS通信 |
| `deny-others` | すべて | すべて | すべて | すべて | 拒否 | 定義外の通信 |

Squidの設定ファイルでは、表の順序で`http_access`を定義する。`http_access`は上から評価されるため、広い拒否ルールは最後に配置する。

ACL追加など設定変更時は、設定ファイルの構文チェックを実行してから `squid -k reconfigure` で設定を再読み込みする。設定変更だけではSquidプロセスを再起動しない。
Squidの接続元ACLも `10.0.1.0/24` のみを許可し、Public IP経由のプロキシ利用は拒否する。

### 6.4 初期段階の対象外

- プロキシ認証
- URLフィルタリング
- SSLインスペクション
- 透過プロキシ
- 複数プロキシ間の連携

## 7. プロキシ設定

実装側の検証用実行環境では、次のプロキシを明示的に設定する。

```text
HTTP_PROXY=http://172.16.1.4:3128
HTTPS_PROXY=http://172.16.1.4:3128
```

Azure CLI、パッケージマネージャー、ビルドツールなど、外部通信を行う各ツールで設定が反映されていることを確認する。

## 8. 検証項目

1. 実装側の検証用実行環境からプロキシVMのTCP 3128へ接続できること
2. プロキシVMから外部サービスへ接続できること
3. 実装側の検証用実行環境からプロキシ経由で外部サービスへ接続できること
4. プロキシを指定しない通信が、意図した経路にならないことを確認する
5. Azure CLI、パッケージ取得、ビルドに必要な通信を確認する

## 9. 費用と運用

VM、OSディスク、Public IPには費用が発生する可能性がある。無料枠と試用クレジットの残量を確認し、検証しない時間帯はVMを停止する。

初期段階では、NAT Gateway、UDR、強制トンネリング、Azure Firewallは使用しない。

## 10. ARMテンプレート

プロキシVMと関連リソースは、`infra/arm/06-proxy-vm.json` を `azlab-tousei-rg` に適用して作成する。

Portalから適用するときは、次のパラメーターを指定する。

| パラメーター | 内容 |
| --- | --- |
| `location` | `japaneast` |
| `adminUsername` | Linux VMの管理者ユーザー名 |
| `adminPassword` | Linux VMの管理者パスワード |

`adminUsername` と `adminPassword` はVM作成時のOSユーザー設定に使用する。運用中の管理接続には使用しない。

テンプレートはPublic IP、NIC、Linux VMを作成する。

cloud-initの設定は `infra/conf/proxy-cloud-init.yml` に定義する。そのYAMLの内容をBase64エンコードし、ARMテンプレートの `customData` に埋め込む。

## 11. ACL変更

既存のプロキシVMにACLを追加する場合は、Azure Portalで対象VMを開き、**操作**から**コマンドの実行**を選択する。`RunShellScript` でSquidの設定ファイルを変更し、構文チェック後に設定を再読み込みする。

RunShellScriptはAzure VMエージェント経由でコマンドを実行するため、SSH用の受信NSGルールは必要ない。

```bash
sudo sed -i '/acl jissou_allowlist/a acl jissou_allowlist dstdomain registry.npmjs.org' /etc/squid/squid.conf
sudo squid -k parse
sudo squid -k reconfigure
```

ACLの追加だけであれば、プロキシVMを作り直す必要はない。まずRunShellScriptで既存VMのSquid設定へ手動で反映し、設定変更をすぐに有効化する。

その後、同じACL追加内容を `infra/conf/proxy-cloud-init.yml` に反映し、YAMLをBase64エンコードした値でARMテンプレートの `customData` も更新する。これにより、既存VMへ手動反映した内容と、ARMテンプレートから新しく作成するVMの初期設定に差分が出ないようにする。

ARMテンプレートを更新しても、既存VMの初回起動時に実行された`customData`は再実行されない。そのため、テンプレートを更新しただけで既存VMへ反映する必要はない。`customData`の内容を既存VMへ適用し直す場合は、プロキシVMを削除して再作成する。
