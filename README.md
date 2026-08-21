# azlab

Azureのサービスや構成を試しながら、認証・ネットワーク・ビルド・デプロイ・運用などを検証するためのラボ用リポジトリです。

## 実行環境

接続元に制約がある環境でも、Azureリソースの構築やアプリケーションのデプロイを行える方法を検証します。

- ローカルPCのPowerShellからはAzureへ接続しない
- パブリックなCloud Shellは使用しない
- Azure Portalのカスタムデプロイ、またはネットワーク制御下のAzure実行環境を使用する

## 構成

```text
infra/
	arm/          ARMテンプレート
	bicep/        Bicep定義
app/
	frontend/     フロントエンド
	api/          API
docs/           検証手順・結果・申請事項
```

## 主な検証テーマ

- Azureサービスの基本操作と構成
- リソース間のネットワーク接続
- ネットワーク制約下でのプロキシ経由の外部通信
- Azure CLIによるリソース操作
- パッケージ取得とアプリケーションビルド
- Static Web AppsとFunction Appへのデプロイ
