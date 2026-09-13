※ これはClaudeに作成してもらったZabbix上にホストを作成/更新等を実施するpyスクリプトです。

# zbx-bulk-host — Zabbix ホスト一括登録ツール

CSV / YAML で書いたホスト定義を、Zabbix API 経由で**冪等に**流し込む CLI。
Zabbix 7.0 LTS 以降が対象（6.0 / 6.4 も互換モードで動作）。

```
zabbix-bulk-host/
├── .mise.toml                  mise 設定（このディレクトリ専用の Python + .venv + タスク）
├── .gitignore
├── zbx_bulk_host.py            本体（単一ファイル・依存は requests / PyYAML のみ）
├── requirements.txt
├── docs/
│   ├── 01_requirements.md      要件定義書（調査した参考記事一覧つき）
│   └── 02_design.md            設計書
├── samples/
│   ├── hosts.example.csv       入力サンプル（CSV）
│   └── hosts.example.yaml      入力サンプル（YAML / defaults つき）
└── tests/
    ├── test_zbx_bulk_host.py   単体・結合テスト（63 件、実 Zabbix 不要）
    └── mock_zabbix_server.py   モック Zabbix API サーバー（通しテスト用）
```

## できること

| | |
|---|---|
| 入力 | CSV（Excel から保存した BOM 付き UTF-8 も可）／ YAML（`defaults` で共通値） |
| 設定できる項目 | ホスト名・表示名・ホストグループ・テンプレート・インターフェース（Agent/SNMP/IPMI/JMX）・ユーザーマクロ・ホストタグ・有効／無効・説明・インベントリモード・プロキシ |
| 冪等性 | `host.get` で既存突合 → **CREATE / UPDATE / NOOP** を判定。何度実行しても同じ状態になる |
| 安全性 | 書き込み前に全件バリデーション（1 件でも不正なら書き込みゼロで停止）／ `--dry-run`／既定は加算マージで既存設定を消さない |
| 性能 | 名前→ID 解決は入力全体で **1 リクエスト**（ホスト数に依存しない）／ `host.create` はチャンク配列投入 |
| 失敗時 | チャンクが失敗したら 1 件ずつ再投入して**失敗ホストだけを特定**。通信断時は再確認して二重作成を防ぐ |
| 監査 | JSON レポートに「どのホストに何を変更したか」を記録（secret マクロはマスク） |

## セットアップ

### mise を使う場合（推奨）

`.mise.toml` がこのディレクトリをスコープに Python と `.venv` を用意します。
`cd` するだけで venv が有効になり、`pip` はこのプロジェクト専用のものを指します。

```bash
cd zabbix-bulk-host
mise trust            # 初回のみ（設定ファイルの信頼登録）
mise install          # Python を用意し .venv を自動作成
mise run install      # pip install -r requirements.txt
mise run info         # 使用中の python / pip / venv を確認
```

用意されているタスク（`mise tasks` で一覧）:

| タスク | 内容 |
|---|---|
| `mise run install`（`i`） | pip で依存を導入 |
| `mise run test`（`t`） | 単体・結合テスト（実 Zabbix 不要） |
| `mise run e2e` | モック API に対する通しテスト（apply → 再実行で全件 NOOP） |
| `mise run mock` | モック Zabbix API サーバーを起動 |
| `mise run plan -- hosts.csv --create-groups` | dry-run |
| `mise run apply -- hosts.csv --create-groups` | 適用 |
| `mise run info` / `freeze` / `clean` | 環境確認 / 依存固定 / 生成物削除 |

Python のバージョンは既定 3.12。変えたいときは `PYTHON_VERSION=3.13 mise install`。

> 認証情報（`ZABBIX_TOKEN` / `ZABBIX_PASSWORD`）は `.mise.toml` に**書かないでください**。
> シェルの環境変数か、`.gitignore` 済みの `mise.local.toml` に置きます。

### mise を使わない場合

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # requests（YAML を使うなら PyYAML も）
export ZABBIX_URL="https://zabbix.example.jp"
```

認証方法は 2 通り。どちらでも全機能が使えます。

### A. API トークン（推奨・恒久運用向け）

Zabbix の UI で発行します。**7.0 の画面パス:**

```
Users（ユーザー）→ API tokens（API トークン）→ 右上「Create API token」
  Name        : zbx-bulk-host              ← 任意の識別名
  User        : Admin                       ← トークンを紐づけるユーザー
  Expiration  : 期限なしにするならチェックを外す
  Enabled     : ON
→ 「Add」を押すと Auth token が 1 度だけ表示されるのでコピーして保管する
```

作成直後の画面を閉じると**二度と表示されません**。自分用のトークンなら
`User settings（ユーザー設定）→ API tokens` からも発行できます。

```bash
export ZABBIX_TOKEN="発行したトークン"
python3 zbx_bulk_host.py plan hosts.csv
```

### B. ID / パスワード（トークンが無いとき・単発作業向け）

`--user` を付けると `user.login` でセッションを取得します。トークン発行は不要です。

```bash
# 対話実行なら、パスワードは画面に表示されない形で聞かれる
python3 zbx_bulk_host.py plan hosts.csv --user Admin

# cron / CI など非対話なら環境変数で渡す
export ZABBIX_PASSWORD='...'
python3 zbx_bulk_host.py apply hosts.csv --user Admin --create-groups
```

- パスワードは**コマンドライン引数では受け取りません**（`ps` やシェル履歴に残るため）
- 処理の最後に `user.logout` を呼び、取得したセッションを必ず無効化します
- `-v` を付けてもパスワード・トークン・セッション ID はログに出ません（`***` に置換）

> トークン方式との違いは、セッションが Zabbix の「セッション有効期間」設定に従う点と、
> Admin の実パスワードを渡す必要がある点です。定常運用・自動実行では A を推奨します。

## 使い方

```bash
# 1) まず dry-run で差分を確認する（書き込みは一切行わない）
python3 zbx_bulk_host.py plan samples/hosts.example.csv --create-groups

# 2) 問題なければ適用
python3 zbx_bulk_host.py apply samples/hosts.example.csv --create-groups --report apply.json

# 3) 冪等性の確認（2 回目は全件 NOOP になる）
python3 zbx_bulk_host.py plan samples/hosts.example.csv
```

出力例:

```
=== Plan ===
CREATE     8
UPDATE     0
NOOP       0

=== Apply ===
[CREATE] web01.example.jp     hostid=20005
...
=== Summary ===
created=8 updated=0 noop=0 failed=0  api_calls=7  elapsed=0.3s
```

`api_calls=7` は **ホスト 8 台でも 800 台でも変わらない**（`apiinfo.version` / 認証確認 /
`hostgroup.get` / `hostgroup.create` / `template.get` / `host.get` / `host.create`）。
1 台ごとに `hostgroup.get` を呼ぶ実装との差がここに出る。

### 主なオプション

| オプション | 説明 |
|---|---|
| `--create-groups` | 未存在のホストグループを作成する（**ホストより先に**作られる） |
| `--dry-run` / `plan` | 書き込まずに差分だけ表示 |
| `--prune` | ファイルの内容に**完全一致**させる（既存の余剰グループ・タグ・マクロを削除）。既定は加算マージ |
| `--force-secret` | secret 型マクロを毎回送信する（既定は既存値を触らない＝比較不能なため） |
| `--chunk-size N` | `host.create` のチャンク件数（既定 50） |
| `--report PATH` | JSON レポート出力 |
| `--verify` | 作成後に `host.get` で hostid を検証 |
| `--sleep SEC` | API 呼び出し間隔（フロントエンド負荷を抑えたいとき） |
| `--user USER` | トークンを使わず `user.login` する（パスワードは対話プロンプト or `$ZABBIX_PASSWORD`） |
| `-v` / `-q` | 詳細ログ／サマリのみ |

### 終了コード

| 0 | 全件成功（NOOP を含む） |
|---|---|
| 1 | 1 件以上の適用失敗 |
| 2 | 事前検証エラーで**未実行**（書き込みゼロ） |
| 3 | 認証・接続エラーで開始不能 |
| 130 | 中断（Ctrl-C）。実行済み分はレポートに残る |

## 入力フォーマット

### CSV

- 区切りは `,`。**セル内の複数値は `;`**、キー=値は `=`
  （IP やホスト名にカンマ・空白が混ざっても壊れないようにするため）
- 先頭が `#` の行はコメント（ヘッダより前に置いても可）
- 1 行 = 1 ホスト = 1 インターフェース。複数インターフェースが必要なら YAML を使う

```csv
host,name,groups,templates,interface_ip,interface_port,tags,macros
web01.example.jp,Web 01,Linux servers;Prod/Web,Linux by Zabbix agent,192.168.10.11,10050,env=prod;role=web,{$SITE}=tokyo
```

利用できる列: `host`（必須）, `name`, `groups`（必須）, `templates`,
`interface_type`（agent/snmp/ipmi/jmx）, `interface_useip`, `interface_ip`,
`interface_dns`, `interface_port`, `interface_main`, `snmp_version`,
`snmp_community`, `snmp_bulk`, `tags`, `macros`, `status`（enabled/disabled）,
`description`, `inventory_mode`（disabled/manual/automatic）, `proxy`, `proxy_group`

### YAML

`defaults` に共通値を書き、`hosts[]` で個別に上書きする。

```yaml
defaults:
  groups: [Linux servers]
  templates: [Linux by Zabbix agent]
  interfaces: [{type: agent, useip: true, port: 10050}]
  tags: [{tag: env, value: prod}]
hosts:
  - host: web01.example.jp
    name: Web 01
    groups: [Prod/Web]                 # defaults と結合される
    interfaces: [{ip: 192.168.10.11}]  # type/port は defaults から引き継ぐ
    tags: [{tag: role, value: web}]
```

マージ規則:

| キー | 挙動 |
|---|---|
| `groups` / `templates` | defaults と結合 |
| `tags` | 結合。ただし**同じタグ名**をホスト側が書いたら、その名前は defaults を置き換える（`env=prod` → `env=staging` ができる） |
| `macros` | マクロ名で一意。ホスト側が優先 |
| `interfaces` | ホスト側で置換。省略キーは**同じ `type` の defaults** から引き継ぐ |
| スカラー（`status` など） | ホスト側が優先 |

## 更新時の挙動（重要）

既定は**加算マージ**。運用中の Zabbix には UI から足された正当な設定があるため、
ファイルに書いていないものを勝手に消さない。

| | 既定 | `--prune` |
|---|---|---|
| ホストグループ | 既存 ∪ ファイル | ファイルのみ |
| テンプレート | 既存 ∪ ファイル | ファイルのみ（外す分は `templates_clear`＝**アイテム・履歴も削除**） |
| タグ | 既存 ∪ ファイル | ファイルのみ |
| マクロ | 既存を維持し、ファイル記載分を上書き・追加 | ファイルのみ |
| インターフェース | 種別＋main が一致する既存の `interfaceid` を引き継いで更新。未記載の既存は残す | ファイルのみ |

`--prune` はテンプレートのリンク解除でアイテムと履歴が消えるため、**必ず `plan` で差分を確認してから**使うこと。

## テスト

```bash
# 単体・結合テスト（実 Zabbix 不要 / 63 件）
python3 tests/test_zbx_bulk_host.py

# 通しテスト：モック Zabbix API サーバーに対して CLI を実行する
python3 tests/mock_zabbix_server.py 18080 &
export ZABBIX_URL=http://127.0.0.1:18080 ZABBIX_TOKEN=dummy
python3 zbx_bulk_host.py apply samples/hosts.example.csv --create-groups
python3 zbx_bulk_host.py plan  samples/hosts.example.csv               # → 全件 NOOP

# 6.x 互換モードの確認
MOCK_ZABBIX_VERSION=6.0.30 python3 tests/mock_zabbix_server.py 18081 &
```

検証済みの受け入れ基準（`docs/01_requirements.md` 7 章）:
AC-01 新規登録 / AC-02 再実行で全件 NOOP / AC-03 1 箇所変更 → 1 件だけ UPDATE /
AC-04 未存在グループで exit 2 / AC-05 不正行で書き込みゼロ停止 /
AC-06 チャンク内 1 件失敗の切り分け（他 4 件は成功、exit 1）/
AC-07 レポートに secret マクロの平文が出ない / AC-08 単体テスト全件パス（63 件）/
AC-09 ID/PW 認証だけで登録・更新できる / AC-10 終了時に `user.logout` される /
AC-11 `-v` でもパスワード・トークンの平文が出ない

## 運用ルール（推奨）

1. 入力ファイルは **Git 管理**し、Zabbix 構成の正本とする
2. 本番適用の前に必ず `plan` を実行し、`CREATE`/`UPDATE`/`NOOP` の件数を承認者が確認する
3. API トークンは環境変数（または CI のシークレット）に置き、ファイルに書かない
4. `--prune` は棚卸し作業時のみ。差分を確認してから実行する

## 設計の根拠

要件定義・設計は以下の調査結果に基づく（詳細は `docs/01_requirements.md` 2 章）。

- [Zabbix API でラクにミスなく大量のホストを登録しよう！ — アークシステム](https://devlog.arksystems.co.jp/2019/08/06/8884/)
  … 「認証トークンの切り出し」「ホストグループ → ホストの順序」「グループ名 → ID 変換」の 3 ポイント
- [host.create / host.update / Host object — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/create)
  … オブジェクト配列によるバルク作成、7.0 の `monitored_by` + `proxyid`
- [Use Zabbix API / API tokens — Zabbix Documentation](https://www.zabbix.com/documentation/7.4/en/devel/python/api)
  … 7.0 以降の Bearer トークン認証
- [Supporting bulk operations in REST APIs — Michael Scharhag](https://www.mscharhag.com/api-design/bulk-and-batch-operations)
  … バルク API では「どの要素が失敗したか特定できる設計」が必要
- [community.zabbix.zabbix_host — Ansible](https://docs.ansible.com/projects/ansible/latest/collections/community/zabbix/zabbix_host_module.html)
  … 冪等モジュールのパラメータ体系（入力スキーマの参考）
