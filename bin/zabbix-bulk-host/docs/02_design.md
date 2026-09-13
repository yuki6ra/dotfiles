# 設計書 — Zabbix ホスト一括登録自動化ツール（zbx-bulk-host）

- 対象要件: `docs/01_requirements.md` v1.0
- 対象 Zabbix: 7.0 LTS 以降（6.x 互換モードあり）
- 版数: 1.0

---

## 1. 全体アーキテクチャ

```
                     入力（Git 管理対象）
        ┌──────────────────────────────────────┐
        │  hosts.csv  /  hosts.yaml            │
        └───────────────┬──────────────────────┘
                        │
   ┌────────────────────▼─────────────────────────────────────────┐
   │                    zbx_bulk_host.py                         │
   │                                                              │
   │  ①Loader        CSV/YAML → HostSpec[]（正規化・defaults 展開） │
   │        │                                                     │
   │  ②Validator     必須/書式/重複/整合性を全件検査 ── NG → 終了2  │
   │        │                                                     │
   │  ③Resolver      名前→ID を「まとめて1回」解決してキャッシュ    │
   │        │         hostgroup.get / template.get / proxy.get    │
   │        │         不足グループは hostgroup.create（順序保証）   │
   │  ④Planner       host.get で既存突合 → CREATE/UPDATE/NOOP     │
   │        │                                                     │
   │  ⑤Executor      host.create をチャンク投入（失敗時は単体切分） │
   │        │         host.update を1件ずつ                        │
   │  ⑥Reporter      標準出力サマリ + JSON レポート + 終了コード    │
   └────────────────────┬─────────────────────────────────────────┘
                        │ HTTPS / JSON-RPC 2.0 (Bearer token)
              ┌─────────▼──────────┐
              │ Zabbix Frontend    │
              │ api_jsonrpc.php    │
              └────────────────────┘
```

### 1.1 参考記事に対する設計上の差分（改善点）

| 参考記事の実装 | 本設計 | 理由 |
|---|---|---|
| ホスト 1 台ごとに `hostgroup.get` を呼ぶ（記事 A） | 全入力からグループ名の集合を作り `hostgroup.get` を **1 回** | 300 台なら API 呼び出しを 300 回 → 1 回に削減（NFR-01） |
| `user.login` でパスワードからトークン取得（記事 A） | UI 発行の **API トークンを Bearer ヘッダ**で送信。`user.login` はフォールバック | 7.0 標準方式。パスワードを持たない（NFR-05） |
| `host.create` のみ（記事 A, G） | `host.get` で突合し **create / update / noop** を判定 | 既存ホストで `already exists` 停止しない。再実行可能（NFR-02） |
| 1 リクエスト = 1 ホスト（記事 A, G） | **チャンク配列投入 + 失敗時単体切り分け** | 通信回数削減と失敗要素の特定を両立（記事 E, I） |
| `proxy_hostid`（6.x 以前の記事） | `monitored_by` + `proxyid` / `proxy_groupid`、6.x は互換分岐 | 7.0 での非互換対応（記事 F, NFR-07） |
| 事前検証なし | **全件検証してから書き込み開始** | 「10 台目で落ちて 9 台だけ入った」状態を作らない |

---

## 2. モジュール構成

単一ファイル配布（NFR-06）のため 1 ファイル内でレイヤ分割する。

| # | 要素 | 責務 |
|---|---|---|
| 1 | `ZabbixAPI` | JSON-RPC 2.0 クライアント。認証、リトライ、バージョン検出、シークレットのマスク |
| 2 | `HostSpec` / `InterfaceSpec` | 入力を表す正規化済みデータクラス |
| 3 | `load_specs()` / `_load_csv()` / `_load_yaml()` | 入力パース。`defaults` 展開、`;`/`=` 区切りの分解 |
| 4 | `validate_specs()` | FR-06 の事前検証 |
| 5 | `Resolver` | 名前→ID の一括解決とキャッシュ、不足グループの作成 |
| 6 | `Planner` | 既存ホスト取得と差分計算、API パラメータ組み立て |
| 7 | `Executor` | チャンク投入・単体切り分け・更新実行 |
| 8 | `Reporter` | サマリ出力・JSON レポート・終了コード決定 |
| 9 | `main()` | CLI 引数処理とパイプライン制御 |

---

## 3. 入力スキーマ設計

### 3.1 CSV

区切り文字は `,`（標準 CSV）。**セル内の複数値は `;`**、キー=値は `=`（要件 FR-01-4／記事 A の注意点を踏襲）。

| 列名 | 必須 | 例 | 備考 |
|---|---|---|---|
| `host` | ○ | `web01.example.jp` | 技術名。突合キー |
| `name` | | `Web サーバー 01` | 表示名。空なら `host` と同じ |
| `groups` | ○ | `Linux servers;Prod/Web` | `;` 区切り |
| `templates` | | `Linux by Zabbix agent;HTTP Service` | `;` 区切り |
| `interface_type` | | `agent` | `agent`/`snmp`/`ipmi`/`jmx`、既定 `agent` |
| `interface_useip` | | `1` | 既定 `1` |
| `interface_ip` | | `192.168.10.11` | `useip=1` で必須 |
| `interface_dns` | | `web01.example.jp` | `useip=0` で必須 |
| `interface_port` | | `10050` | 既定は種別別（10050/161/623/12345） |
| `snmp_version` | | `2` | SNMP 時のみ |
| `snmp_community` | | `{$SNMP_COMMUNITY}` | SNMP 時のみ |
| `tags` | | `env=prod;role=web` | `;` 区切り、`=` で tag=value |
| `macros` | | `{$SITE}=tokyo;{$THRESH}=80` | `;` 区切り |
| `status` | | `enabled` | `enabled`/`disabled`（既定 `enabled`） |
| `description` | | `EC 本番 Web` | |
| `inventory_mode` | | `manual` | `disabled`/`manual`/`automatic` |
| `proxy` | | `proxy-tokyo` | 指定時 `monitored_by=1` |
| `proxy_group` | | `pg-tokyo` | 指定時 `monitored_by=2`。7.0 以降のみ |

- 先頭が `#` の行はコメントとして無視
- BOM 付き UTF-8 を許容（Excel からの CSV 保存対策）
- 未知の列は無視せず警告を出す（列名タイポの早期発見）

### 3.2 YAML

`defaults` で共通値を、`hosts[]` で個別値を書き、**ホスト側の指定が defaults を上書き**する（リストは置換ではなくマージ：`groups`/`templates`/`tags`/`macros` は結合、`interfaces` は置換）。

```yaml
defaults:
  groups: ["Linux servers"]
  templates: ["Linux by Zabbix agent"]
  tags:
    - {tag: managed_by, value: zbx-bulk-host}
  macros:
    - {macro: "{$ENV}", value: prod}
  interfaces:
    - {type: agent, useip: true, port: 10050}
  status: enabled
  inventory_mode: manual

hosts:
  - host: web01.example.jp
    name: "Web サーバー 01"
    interfaces:
      - {type: agent, useip: true, ip: 192.168.10.11, port: 10050}
    tags: [{tag: role, value: web}]
    macros: [{macro: "{$SITE}", value: tokyo}]
```

### 3.3 正規化後の内部表現

```python
@dataclass
class InterfaceSpec:
    type: int          # 1=agent 2=snmp 3=ipmi 4=jmx
    main: int          # 0/1
    useip: int         # 0/1
    ip: str
    dns: str
    port: str
    details: dict      # SNMP のみ {version, community, bulk}

@dataclass
class HostSpec:
    host: str
    name: str
    groups: list[str]        # 名前
    templates: list[str]     # 名前
    interfaces: list[InterfaceSpec]
    tags: list[dict]         # {tag, value}
    macros: list[dict]       # {macro, value, type, description}
    status: int              # 0=有効 1=無効
    description: str
    inventory_mode: int      # -1/0/1
    proxy: str | None
    proxy_group: str | None
    source: str              # 由来（ファイル名:行番号）— エラー報告用
```

---

## 4. 認証設計

```
優先順位
 1. --token / 環境変数 ZABBIX_TOKEN
      → UI 発行の API トークンをそのまま使う（推奨・恒久運用）
 2. --user + パスワード
      → user.login でセッション ID を取得して以降のリクエストに使う
      → パスワードの取得順: 環境変数 ZABBIX_PASSWORD → 対話プロンプト(getpass)
      → 処理終了時に user.logout でセッションを無効化する
```

どちらの方式でも、取得した文字列は同じ「認証トークン」として扱う。
7.0 では `Authorization: Bearer <token>` ヘッダに載せる（6.4 未満は JSON 本文の `auth`）。

| | API トークン | ID / パスワード |
|---|---|---|
| 事前準備 | UI でトークン発行が必要 | 不要（既存の Admin アカウントで可） |
| 有効期限 | 発行時に指定（無期限も可） | Zabbix の「セッション有効期間」に従う |
| 失効操作 | UI でトークンを無効化 | 実行終了時に自動 `user.logout` |
| パスワードの露出 | なし | 実行環境に平文で存在する |
| 推奨用途 | 定常運用・cron・CI | 単発作業・トークン発行前の検証 |

セキュリティ上の扱い（FR-09-2 / NFR-05）:

- パスワードは**コマンドライン引数で受け取らない**（`ps` とシェル履歴に残るため）。
  環境変数か `getpass` の対話入力のみ
- 非対話（パイプ・cron）でパスワードが無ければ exit 3 で即停止し、プロンプトで固まらせない
- `password` / `token` / `auth` / `sessionid` / `Authorization` の各キーは
  ログ・レポート出力時に `***` へ置換する。`ZabbixAPI.__repr__` も同様

API バージョンは `apiinfo.version`（無認証で呼べる）で取得し、`user.login` の
パラメータ名（6.0 以降は `username`、5.x 以前は `user`）もこれで切り替える。

---

## 5. 名前解決設計（Resolver）

```
入力全体を走査
   ├─ group_names   = 全ホストの groups の集合
   ├─ tmpl_names    = 全ホストの templates の集合
   ├─ proxy_names   = 全ホストの proxy の集合
   └─ pgroup_names  = 全ホストの proxy_group の集合

1 回だけ呼ぶ:
   hostgroup.get   {output:[groupid,name],    filter:{name: [...]}}
   template.get    {output:[templateid,host], filter:{host: [...]}}
   proxy.get       {output:[proxyid,name],    filter:{name: [...]}}   ← 7.0
   proxygroup.get  {output:[proxy_groupid,name], filter:{name:[...]}} ← 7.0

不足グループ:
   --create-groups あり → hostgroup.create（配列で一括）してキャッシュに追加
   --create-groups なし → 検証エラーとして列挙
不足テンプレート/プロキシ: 常に検証エラー（勝手に作れないため）
```

**ホストグループ → ホストの順序**を Resolver が保証する（記事 A ポイント 2）。

---

## 6. 差分計算設計（Planner）

### 6.1 既存ホスト取得

```
host.get {
  output: [hostid, host, name, status, description, inventory_mode,
           monitored_by, proxyid, proxy_groupid],
  filter: {host: [<入力の全ホスト名>]},     ← 完全一致・1 リクエスト
  selectHostGroups: [groupid, name],        ← 7.0（6.x は selectGroups）
  selectParentTemplates: [templateid, host],
  selectInterfaces: [interfaceid, type, main, useip, ip, dns, port, details],
  selectTags: [tag, value],
  selectMacros: [hostmacroid, macro, value, type, description]
}
```

ホスト数が多い場合は `filter.host` も 500 件単位でチャンク分割する。

### 6.2 判定

| 条件 | アクション |
|---|---|
| 既存なし | `CREATE` |
| 既存あり・差分なし | `NOOP` |
| 既存あり・差分あり | `UPDATE`（差分項目のみを `host.update` のパラメータに載せる） |

### 6.3 項目別の比較・マージ規則

| 項目 | 比較 | 既定（加算マージ） | `--prune` 指定時 |
|---|---|---|---|
| `name` / `status` / `description` / `inventory_mode` | 値一致 | 指定があれば上書き | 同じ |
| `groups` | groupid 集合 | 既存 ∪ 指定 | 指定のみ |
| `templates` | templateid 集合 | 既存 ∪ 指定 | 指定のみ（外す分は `templates_clear` に入れてアイテムごと削除） |
| `tags` | (tag, value) 集合 | 既存 ∪ 指定 | 指定のみ |
| `macros` | macro→value/type/description | 既存を `hostmacroid` 付きで維持し、指定分を上書き・追加 | 指定のみ |
| `interfaces` | (type, main, useip, ip, dns, port, details) | 種別 + main が一致する既存の `interfaceid` を引き継ぎ更新。指定に無い既存インターフェースは残す | 指定のみ（余剰は削除） |
| `monitored_by` / `proxyid` | 値一致 | 指定があれば上書き | 同じ |

- **`--prune` を既定にしない**理由: 運用中の Zabbix には UI で足された正当なグループ・マクロが存在しうるため、既定で消さない（NFR-03）
- `templates_clear` は**アイテム・履歴の削除を伴う**ため、`--prune` 時のみ・かつ標準出力に明示警告を出す

### 6.4 マクロの `type`

| 入力値 | API 値 | 備考 |
|---|---|---|
| `text`（既定） | 0 | |
| `secret` | 1 | 値は API から取得できないため**差分比較不能**。既定では「指定があれば常に送る」= 常に UPDATE 扱いを避けるため、`--force-secret` 指定時のみ送信する |
| `vault` | 2 | パスを比較 |

---

## 7. 実行設計（Executor）

### 7.1 CREATE

```
plan.creates を chunk_size（既定 50）で分割
for chunk in chunks:
    try:
        host.create([obj, obj, ...])         # 1 リクエストで N 件（記事 E）
        → 返却 hostids を入力順に対応付け
    except ZabbixAPIError:
        # バルクは all-or-nothing。どれが悪いか分からないので切り分ける
        for obj in chunk:
            try: host.create(obj)  → OK
            except ZabbixAPIError as e: FAIL(obj, e.message)
```

`host.create` の返り値 `hostids` は**入力配列と同順**である前提で対応付ける。順序が保証されない場合に備え、成功後に `host.get` で hostid を引き直す検証モード（`--verify`）を用意する。

### 7.2 UPDATE

`host.update` はバルク配列に対応しないため 1 件ずつ実行する。件数が多い場合の所要時間はここが支配的になるので、NOOP 判定で無駄な更新を落とすことが性能上重要（NFR-01）。

### 7.3 リトライ（NFR-04）

| 事象 | 対応 |
|---|---|
| 接続エラー / タイムアウト / HTTP 5xx | 指数バックオフ（1s, 2s, 4s）で最大 3 回再試行 |
| 書き込み系のリトライ前 | `host.get` で当該ホストの存在を再確認し、**既に作成済みなら CREATE をスキップして UPDATE 判定に回す**（二重作成防止） |
| HTTP 4xx / Zabbix API エラー（-32602 など） | 再試行しない。即 FAIL として記録 |

### 7.4 レート制御

Zabbix API 側にレート制限はないが、フロントエンド（PHP-FPM）の同時処理数を圧迫しないよう**逐次実行（並列度 1）**を既定とする。`--sleep` でリクエスト間隔を挿入できる。

---

## 8. 出力設計（Reporter）

### 8.1 標準出力

```
=== Validation ===
OK: 120 hosts loaded from hosts.csv (0 errors)

=== Resolve ===
host groups : 5 resolved, 1 created (Prod/Web)
templates   : 3 resolved
proxies     : 1 resolved

=== Plan ===
CREATE  112
UPDATE    6
NOOP      2

=== Apply ===
[CREATE] web01.example.jp            hostid=10432
[UPDATE] web07.example.jp            hostid=10287  name, tags(+1), macros(~1)
[NOOP  ] web08.example.jp            hostid=10288
[FAIL  ] web09.example.jp            Host "web09.example.jp" already exists.

=== Summary ===
created=112 updated=6 noop=2 failed=1  elapsed=48.2s
exit=1
```

### 8.2 JSON レポート（`--report`）

```json
{
  "started_at": "2026-09-04T10:00:00+09:00",
  "finished_at": "2026-09-04T10:00:48+09:00",
  "zabbix": {"url": "https://zabbix.example.jp", "api_version": "7.0.9"},
  "options": {"dry_run": false, "prune": false, "chunk_size": 50},
  "summary": {"created": 112, "updated": 6, "noop": 2, "failed": 1},
  "results": [
    {"host": "web07.example.jp", "action": "UPDATE", "hostid": "10287",
     "changes": {"name": {"from": "web07", "to": "Web 07"},
                 "tags": {"added": [{"tag": "role", "value": "web"}]}},
     "source": "hosts.csv:8"},
    {"host": "web09.example.jp", "action": "FAIL", "hostid": null,
     "error": "Host \"web09.example.jp\" already exists.", "source": "hosts.csv:10"}
  ]
}
```

secret 型マクロの値は `"***"` に置換して出力する（FR-09-2）。

### 8.3 終了コード

| コード | 意味 |
|---|---|
| 0 | 全件成功（NOOP を含む） |
| 1 | 1 件以上の適用失敗 |
| 2 | 事前検証エラーで未実行 |
| 3 | 認証・接続エラーで開始不能 |

---

## 9. CLI 設計

```
zbx-bulk-host apply  [オプション] <input ...>
zbx-bulk-host plan   [オプション] <input ...>     # apply --dry-run の別名

必須
  <input ...>              入力ファイル（.csv / .yaml / .yml、複数指定可）
接続
  --url URL                Zabbix フロントエンド URL（環境変数 ZABBIX_URL）
  --token TOKEN            API トークン（環境変数 ZABBIX_TOKEN 推奨）
  --user USER              user.login 方式を使う場合のユーザー名（PW は ZABBIX_PASSWORD）
  --timeout SEC            HTTP タイムアウト（既定 30）
  --insecure               TLS 証明書検証を無効化（検証環境のみ）
挙動
  --dry-run                書き込みを行わず判定結果のみ出力
  --create-groups          未存在のホストグループを作成する
  --prune                  ファイルの内容に完全一致させる（既存の余剰設定を削除）
  --force-secret           secret 型マクロを毎回送信する
  --chunk-size N           host.create のチャンク件数（既定 50）
  --sleep SEC              API 呼び出し間隔（既定 0）
  --verify                 作成後に host.get で hostid を検証する
出力
  --report PATH            JSON レポート出力先
  --verbose / -v           詳細ログ
  --quiet / -q             サマリのみ
```

---

## 10. エラーハンドリング方針

| 層 | 事象 | 挙動 |
|---|---|---|
| 認証 | トークン不正 | 即終了（exit 3）。トークン値は出力しない |
| 接続 | 名前解決失敗・接続拒否 | 3 回再試行後 exit 3 |
| 検証 | 必須欠落・書式不正・名前解決不能 | **全件検査してから**エラー一覧を出力し exit 2（部分適用しない） |
| 適用 | 個別ホストの API エラー | 当該ホストのみ FAIL 記録、処理継続。最後に exit 1 |
| 適用 | 5xx / タイムアウト | バックオフ再試行。書き込み系は再確認付き |
| 中断 | Ctrl-C | 実行済み分のレポートを書き出して exit 130 |

---

## 11. テスト設計

| ID | 種別 | 内容 |
|---|---|---|
| UT-01 | 単体 | CSV パース（BOM、コメント行、`;`/`=` 分解、既定値補完） |
| UT-02 | 単体 | YAML パース（defaults 展開、リストマージ、ホスト側上書き） |
| UT-03 | 単体 | バリデーション（必須欠落、ホスト名重複、useip/ip 不整合、マクロ書式、main 重複） |
| UT-04 | 単体 | Resolver（名前→ID の一括解決が 1 リクエストで済むこと、未解決の検出） |
| UT-05 | 単体 | Planner（CREATE / UPDATE / NOOP 判定、加算マージ、`--prune`、interfaceid 引き継ぎ、hostmacroid 引き継ぎ） |
| UT-06 | 単体 | Executor（チャンク分割、バルク失敗時の単体切り分け） |
| UT-07 | 単体 | Reporter（secret マクロのマスク、終了コード） |
| IT-01 | 結合 | モック API に対して 10 件 apply → 再実行で全件 NOOP（AC-02 相当） |
| IT-02 | 結合 | 1 件だけ差分を入れて再実行 → その 1 件のみ UPDATE（AC-03 相当） |
| ST-01 | 実機 | 検証 Zabbix に対し dry-run → apply → UI 目視（AC-01, AC-04〜07） |

モック API は `ZabbixAPI` と同じインターフェースを持つ `FakeZabbixAPI` を用意し、`host.get` / `host.create` / `host.update` / `hostgroup.*` / `template.get` をインメモリで再現する。

---

## 12. 運用手順（想定）

```bash
# 0) 準備（初回のみ）
pip install requests PyYAML
export ZABBIX_URL="https://zabbix.example.jp"
export ZABBIX_TOKEN="<UI で発行した API トークン>"

# 1) 入力を編集して Git にコミット（レビュー対象）
vi hosts.csv && git add hosts.csv && git commit -m "add 120 web hosts"

# 2) 必ず先に dry-run（構成差分レビュー）
./zbx_bulk_host.py plan hosts.csv --create-groups --report plan.json

# 3) 差分に問題がなければ適用
./zbx_bulk_host.py apply hosts.csv --create-groups --report apply.json

# 4) 冪等性の確認（2 回目は全件 NOOP になること）
./zbx_bulk_host.py plan hosts.csv
```

### 運用ルール

- 本番適用の前に必ず `plan`（dry-run）を実行し、`CREATE`/`UPDATE`/`NOOP` の件数を承認者が確認する
- `--prune` は棚卸し作業時のみ使用し、`plan` の差分内容を確認してから実行する
- 入力ファイルは Git 管理し、Zabbix の構成の正本とする
- API トークンは実行ユーザーの環境変数または CI のシークレットに置き、ファイルに書かない

---

## 13. 参考資料

- [Zabbix API でラクにミスなく大量のホストを登録しよう！ — アークシステム](https://devlog.arksystems.co.jp/2019/08/06/8884/)（設計の 3 ポイントの出典）
- [host.create — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/create)
- [host.update — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/update)
- [Host object — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/object)（`monitored_by` / `proxyid`）
- [Use Zabbix API — Zabbix Documentation](https://www.zabbix.com/documentation/7.4/en/devel/python/api)
- [Introducing zabbix_utils — Zabbix Blog](https://blog.zabbix.com/python-zabbix-utils/27056/)
- [Supporting bulk operations in REST APIs — Michael Scharhag](https://www.mscharhag.com/api-design/bulk-and-batch-operations)（バルク失敗の切り分け設計）
- [community.zabbix.zabbix_host — Ansible](https://docs.ansible.com/projects/ansible/latest/collections/community/zabbix/zabbix_host_module.html)（入力スキーマの参考）
