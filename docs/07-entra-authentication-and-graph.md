# Entra ID認証とMicrosoft Graph利用設計

## 1. 目的

Azure Static Web Apps（SWA）のカスタム組み込み認証と、Microsoft Graph API利用を検証する。Entra IDアプリ登録の認証設定と委任された権限を設定し、SWAとFunction Appの認証連携を確認する。

- SWAへEntra IDでログインする
- SWAのログイン済みユーザーだけがSWAのAPIを呼び出せる
- SWAとLinked Backendで接続したFunction Appへリクエストを転送する
- Function AppからMicrosoft Graph APIを呼び出す
- Function AppのApp Service Authenticationを有効化した状態で、SWAからFunctionへ到達できることを確認する

## 2. 構成

```text
ブラウザ
  ↓ Entra IDでログイン
Azure Static Web Apps
  ├─ /.auth/*（SWA組み込み認証）
  └─ /api/*
       ↓ Linked Backend
独立Function App
  ├─ App Service Authentication v2
  ├─ Azure Static Web Apps（リンク済み）プロバイダー
  └─ Microsoft Graph呼び出し
       ↓ HTTPS / プロキシ
Microsoft Graph API
```

対象リソースは次の通りとする。

| 項目 | 値 |
| --- | --- |
| SWA | `polite-rock-0a298fc0f.7.azurestaticapps.net` |
| Function App | `azlab-jissou-func` |
| Function API | `/api/hello` |
| SWA APIバックエンド | `azlab-jissou-func` |
| Graph権限 | Delegated `User.Read.All`（管理者同意済み） |
| 認証テナント | 使用するMicrosoft Entraテナント |

## 3. Entra IDアプリ登録

### 3.1 方針

SWAのカスタム組み込み認証に、検証用のEntra IDアプリ登録を使用する。FunctionからGraph APIを呼び出す方式は、SWAの認証連携とは分けて定義する。

### 3.2 アプリ登録の設定

Entra IDで検証用アプリ登録を作成し、次を設定する。

- サポートするアカウントの種類を検証テナントに合わせる
- SWAのカスタムEntra ID認証用リダイレクトURIを登録する
- Microsoft GraphのDelegated permissionsを追加する
- `User.Read`を削除し、`User.Read.All`について管理者同意を行う
- Implicit grant and hybrid flowsのアクセストークンとIDトークンを有効にする
- フロントチャネルのログアウトURLは設定しない
- Client IDとClient SecretをSWAのカスタム認証設定へ登録する

アプリ登録の設定値は次の通りとする。

| 設定項目 | 値 |
| --- | --- |
| アプリケーション名 | `azlab-jissou-entra` |
| サポートするアカウントの種類 | この検証で使用するテナントのアカウントのみ |
| テナントID | 使用するMicrosoft EntraテナントのTenant ID |
| クライアントID | アプリ登録作成後に発行されるApplication (client) ID |
| クライアントシークレット | SWAのカスタム組み込み認証へ登録する値。資料やソースコードには記載しない |
| リダイレクトURI | 下記のSWA callback URL |
| Graph権限 | Delegated `User.Read.All` |
| 管理者同意 | `User.Read.All`に付与済み |
| Implicit grant and hybrid flows | アクセストークン、IDトークンともに有効 |
| フロントチャネルのログアウトURL | 未設定 |

SWAの標準Entra IDログインで使用するコールバックURLは、次の形式とする。

```text
https://polite-rock-0a298fc0f.7.azurestaticapps.net/.auth/login/aad/callback
```

### 3.3 Graph権限

Microsoft Graphに対して次のDelegated permissionを設定し、テナント全体の管理者同意を付与する。`User.Read`は設定しない。

```text
User.Read.All
```

`User.Read.All`は組織内のユーザーの完全なプロフィールを読み取るための権限である。この設計では`User.Read.All`のみを使用する。

### 3.4 認証フロー設定

アプリ登録の「暗黙的な許可およびハイブリッド フロー」は次の状態にする。

```text
アクセストークン: 有効
IDトークン: 有効
フロントチャネルのログアウトURL: 未設定
```

SWAのカスタム組み込み認証は、登録したClient IDとClient Secretを使ってEntra IDと連携し、ブラウザ経由でユーザーをログインさせる。Implicit grantの設定は、IDトークンおよびアクセストークンを取得できるようにするために有効化する。

## 4. SWAカスタム組み込み認証

SWAでは、Client ID、Client Secret、Issuerを指定したカスタムEntra ID認証プロバイダーを使用する。ログイン後に次のエンドポイントでログイン状態を確認する。

```text
/.auth/me
```

ログイン済みの場合、`/.auth/me` からSWAのユーザー情報を取得できる。これはGraphアクセストークンの取得確認ではない。

APIをログイン済みユーザーだけに公開する場合、`staticwebapp.config.json` のAPIルートを次のようにする。

```json
{
  "routes": [
    {
      "route": "/api/*",
      "allowedRoles": ["authenticated"]
    }
  ]
}
```

`allowedRoles` はSWA側で未ログインユーザーをAPIルートから拒否するための設定であり、Graphアクセストークンは生成しない。

## 5. Linked BackendとApp Service Authentication

SWAのProduction環境からFunction AppをLinked Backendとしてリンクする。

リンク時には、Function App側に次のプロバイダーが作成されることを確認する。

```text
Azure Static Web Apps（リンク済み）
```

Function App側ではApp Service Authenticationを有効にし、Azure Static Web Apps（リンク済み）プロバイダーを設定する。未認証リクエストはHTTP 401とする。
現在のAzureポータルのAuthentication設定はv2 API（`authsettingsV2`）を使用するため、v1/v2を選択する操作は行わない。

```text
Platform authentication: Enabled
Identity provider: Azure Static Web Apps（リンク済み）
Unauthenticated requests: HTTP 401
```

## 6. Graph APIの呼び出し方式

SWAのカスタム認証に`rolesSource`として`/api/getroles`を設定し、ログイン完了時にSWAから`getroles` Functionを呼び出す。`getroles` Functionはリクエスト本文に含まれるユーザーの委任アクセストークンを使用してMicrosoft Graphを呼び出す。

```text
ブラウザ
  ↓ Entra IDでログイン
SWA
  ↓ rolesSource POST（accessTokenを含む）
getroles Function
  ↓ Authorization: Bearer <accessToken>
Microsoft Graph
```

この方式のGraph呼び出しは、サインインしたユーザーの委任権限に基づいて実行される。通常の`/api/me`へはGraphアクセストークンを転送せず、SWAが`rolesSource` Functionへ渡すトークンだけをGraph呼び出しに使用する。FunctionのClient IDやClient SecretはこのDelegatedフローでは使用しない。

## 7. プロキシ通信

Function AppからMicrosoft Graphへの通信は、プロキシ経由とする。

```text
Function App
  ↓ VNet統合
Proxy VM: 172.16.1.4:3128
  ↓
login.microsoftonline.com
Microsoft Graph: graph.microsoft.com
```

Squidでは次のドメインを許可する。

```text
login.microsoftonline.com
graph.microsoft.com
```

Entra IDのトークン取得とGraph API呼び出しはHTTPSを使用するため、宛先ポート443とCONNECTを許可する。

## 8. 実装手順

1. Entra IDアプリ登録を作成し、検証用の設定を記録する
2. SWAにEntra IDのカスタム組み込み認証プロバイダーと`rolesSource`を設定し、Client IDとClient Secretを登録する
3. SWAのProductionへFunction AppをLinked Backendとしてリンクする
4. Function App側に `Azure Static Web Apps（リンク済み）` が作成されたことを確認する
5. Function AppのApp Service Authenticationを有効化する。新規作成時はv2 APIが使用されるため、バージョン選択は不要
6. `/.auth/login/aad` からログインする
7. `/.auth/me` がログイン済みユーザー情報を返すことを確認する
8. SWAの `/api/hello` を呼び、Functionログが出ることを確認する
9. 認証なしのFunction直URLが401になることを確認する
10. Delegated `User.Read.All`に管理者同意が付与され、`User.Read`が設定されていないことを確認する
11. Implicit grant and hybrid flowsでアクセストークンとIDトークンが有効になっていることを確認する
12. ログイン時に`getroles` Functionが呼び出され、委任アクセストークンでGraph APIを呼び出せることを確認する
13. GraphへのHTTPS通信がプロキシを通ることを確認する

## 9. 動作確認

### 9.1 SWAログイン

```bash
curl -i https://polite-rock-0a298fc0f.7.azurestaticapps.net/.auth/me
```

`curl`単体ではブラウザのログインCookieがないため、未ログインの結果になる。ログイン状態はブラウザの開発者ツールまたはログイン済みブラウザから確認する。

### 9.2 Function直URL

```bash
curl -i https://azlab-jissou-func.azurewebsites.net/api/hello
```

App Service Authenticationが有効な場合、認証情報なしでは `401 Unauthorized` になることを期待する。

### 9.3 SWA API

ログイン済みブラウザから次を呼ぶ。

```text
https://polite-rock-0a298fc0f.7.azurestaticapps.net/api/hello
```

期待結果は `200 OK` とFunctionのJSONである。`403`の場合は、SWAルート認可、Production backendリンク、Function AppのLinked Backendプロバイダー、App Service Authenticationの設定を確認する。

### 9.4 Graph API

Graph APIの検証では、FunctionからGraph APIを呼び出して結果を確認する。アクセストークンはログへ出力しない。

アプリケーション権限で取得したトークンを、ログやレスポンスへ出力してはならない。

## 10. 検証時の判定

| 確認対象 | 成功条件 |
| --- | --- |
| SWAログイン | `/.auth/me` がログイン済みユーザー情報を返す |
| Function直URL（認証なし） | `401 Unauthorized` |
| SWA `/api/hello` | `200 OK`、Functionログが出る |
| 偽造SWAヘッダー | Functionコードに到達せず401 |
| Graph呼び出し | `getroles` Functionが委任アクセストークンでGraph APIを呼び出せる | 
| Graph権限不足 | Graphが適切な権限エラーを返す |
| プロキシ | Squidログに `graph.microsoft.com` と `login.microsoftonline.com` が記録される |

