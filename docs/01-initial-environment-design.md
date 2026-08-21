# 初期環境設計書

## 1. 目的

Azureの個人検証環境で、ネットワーク制約下における構成を部分的に再現する。
まずは、ネットワーク接続、明示的プロキシ経由の外部通信、Azure CLI操作、ビルド、デプロイに必要な初期環境を構築する。

本設計書では、初期段階で作成するリソースと命名規則を定義する。

## 2. 前提

- 無料試用版サブスクリプションを使用する
- 統制側と実装側でVNetを分ける
- VNet間はVNet Peeringで接続する
- 最初はVHub、NAT Gateway、UDR、強制トンネリングを使用しない
- 外部通信は、統制側に配置するプロキシVMを明示的に指定して検証する
- 統制側の構成は最小限にする
- 将来構成の完全な再現ではなく、検証に必要な最小構成とする

## 3. リソースグループ

| リソースグループ | 用途 | 主な配置リソース |
| --- | --- | --- |
| `azlab-tousei-rg` | 統制・共通基盤側 | 統制側VNet、サブネット、NSG、プロキシVM、Public IPなど |
| `azlab-jissou-network-rg` | 実装側ネットワーク | 実装側VNet、サブネット、NSG、VNet Peeringなど |
| `azlab-jissou-ap-rg` | 実装・検証対象 | 検証用VM、Static Web Apps、Function Appなど |

統制側は初期検証では1つのリソースグループにまとめる。
実装側は、ネットワークとアプリケーションを分ける。

## 4. ネットワーク構成

```text
azlab-tousei-rg
└─ azlab-tousei-vnet
   └─ azlab-tousei-snet
      └─ azlab-tousei-nsg

             ⇅ VNet Peering

azlab-jissou-network-rg
└─ azlab-jissou-vnet
   ├─ azlab-jissou-ap-snet
   │  └─ azlab-jissou-ap-nsg
   └─ azlab-jissou-pe-snet
      └─ azlab-jissou-pe-nsg

azlab-jissou-ap-rg
└─ 実装・検証対象リソース
```

### 4.1 VNet

| VNet | 配置先 | CIDR | 用途 |
| --- | --- | --- | --- |
| `azlab-tousei-vnet` | `azlab-tousei-rg` | `172.16.0.0/16` | プロキシVMを配置する統制側ネットワーク |
| `azlab-jissou-vnet` | `azlab-jissou-network-rg` | `10.0.0.0/16` | 検証対象を配置する実装側ネットワーク |

`tousei` は `172.16.0.0/16`、`jissou` は `10.0.0.0/16` とし、アドレス範囲が視覚的に区別できるようにする。

### 4.2 サブネットとNSG

統制側はサブネットとNSGを1つずつ作成する。

実装側は用途を分け、次の2つのサブネットとNSGを作成する。

| サブネット | NSG | CIDR | 用途 |
| --- | --- | --- | --- |
| `azlab-tousei-snet` | `azlab-tousei-nsg` | `172.16.1.0/24` | プロキシVMなど統制側の実行環境 |
| `azlab-jissou-ap-snet` | `azlab-jissou-ap-nsg` | `10.0.1.0/24` | アプリケーションや検証用VM |
| `azlab-jissou-pe-snet` | `azlab-jissou-pe-nsg` | `10.0.2.0/24` | Private Endpoint |

### 4.3 NSGルール

初期段階では、プロキシ通信に加えて、将来作成予定のApplication GatewayからStatic Web Apps Private Endpointへの通信を想定したルールを定義する。

| NSG | 方向 | ルール名 | 優先度 | プロトコル／ポート | 接続元 | 接続先 | アクション |
| --- | --- | --- | ---: | --- | --- | --- | --- |
| `azlab-tousei-nsg` | 受信 | `allow-proxy-from-jissou` | 100 | TCP / 3128 | `10.0.1.0/24` | `172.16.1.0/24` | 許可 |
| `azlab-jissou-pe-nsg` | 受信 | `allow-appgw-to-swa-pe` | 100 | TCP / 80 | `172.16.1.0/24` | `10.0.2.0/24` | 許可 |

### 4.4 VNet Peering

次の双方向Peeringを作成する。

- `azlab-tousei-vnet` から `azlab-jissou-vnet`
- `azlab-jissou-vnet` から `azlab-tousei-vnet`

PeeringはVNet間の到達性を提供するが、実装側の通信を自動的にプロキシ経由へ変更するものではない。外部通信の検証では、検証用VMや実行環境に明示的なプロキシ設定を行う。

## 5. 命名規則

Azure上の作成対象リソースは、すべて `azlab` を先頭に付ける。

```text
azlab-<役割>-<用途>-<リソース種別>
```

| 要素 | 意味 |
| --- | --- |
| `azlab` | 検証環境の識別子 |
| `tousei` | 統制・共通基盤側 |
| `jissou` | 実装・検証対象側 |
| `network` | ネットワーク関連 |
| `ap` | アプリケーション関連 |
| `pe` | Private Endpoint関連 |
| `rg` | リソースグループ |

例:

```text
azlab-tousei-rg
azlab-jissou-network-rg
azlab-jissou-ap-rg
azlab-jissou-ap-snet
azlab-jissou-pe-nsg
```

## 6. 初期構築の順序

1. 無料試用版サブスクリプションを確認する
2. `01-resource-groups.json` をサブスクリプションスコープで適用し、3つのリソースグループを作成する。Portalのデプロイリージョンには `Japan East` を指定する
3. `02-tousei-network.json` を `azlab-tousei-rg` に適用し、統制側VNet、サブネット、NSGを作成する
4. `03-jissou-network.json` を `azlab-jissou-network-rg` に適用し、実装側VNet、サブネット、NSGを作成する
5. `04-tousei-peering.json` と `05-jissou-peering.json` をそれぞれ対象のリソースグループに適用する
6. プロキシVMとPublic IPを作成する
7. 実装側の検証用VMまたは実行環境から、プロキシ経由の外部通信を確認する
8. Azure CLI、パッケージ取得、ビルド、デプロイを順に検証する

## 7. ARMテンプレートの適用方針

初期環境のリソース定義は `infra/arm` にARM JSONとして作成し、ARMテンプレートを初期構築の正本とする。実行環境の制約によりBicepをCLIで適用することが難しいため、ARMテンプレートをAzure Portalから適用する。

リソースグループ作成用の `01-resource-groups.json` のみサブスクリプションスコープで適用する。ネットワークとPeering用のテンプレートは、作成済みの対象リソースグループを指定して適用する。

## 8. 対象外

初期段階では、次の構成を作成しない。

- VHub
- NAT Gateway
- UDRや強制トンネリング
- Application Gateway
- Private Endpoint接続
- 通知機能

検証結果を確認し、必要性と費用を見た上で段階的に追加する。
