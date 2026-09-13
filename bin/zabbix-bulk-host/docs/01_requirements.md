# 要件定義書 — Zabbix ホスト一括登録自動化ツール

- ドキュメント種別: 要件定義書
- 対象システム: Zabbix 7.0 LTS 以降
- 作成日: 2026-09-04
- 版数: 1.0

---

## 1. 背景と目的

### 1.1 背景

Zabbix の Web UI からホストを 1 台ずつ登録する運用は、台数が増えるほど工数と設定ミスのリスクが増大する。アークシステム社の技術ブログ「[Zabbix API でラクにミスなく大量のホストを登録しよう！](https://devlog.arksystems.co.jp/2019/08/06/8884/)」では 300 台の登録を題材に、手作業では「単純な繰り返しのためうっかり設定ミスしそう」という課題を挙げている。

### 1.2 目的

- Zabbix API を用いてホストを一括登録・一括更新できる CLI ツールを整備する
- 構成情報を CSV / YAML というレビュー可能なテキストで管理し、Git 管理・差分レビューを可能にする
- 何度実行しても同じ結果になる（冪等）ことで、「追加」だけでなく「継続的な構成の当て込み」に使えるようにする

### 1.3 スコープ

| 区分 | 内容 |
|---|---|
| 対象内 | ホストグループ作成、ホスト作成、ホスト更新、インターフェース、テンプレートリンク、ユーザーマクロ、ホストタグ、プロキシ割当 |
| 対象外 | アイテム／トリガー／グラフの個別作成（テンプレート経由で付与する方針）、ダッシュボード、アクション、ユーザー管理、ホスト削除（安全上、初版では非対応） |

---

## 2. 調査結果（参考記事・公式ドキュメント）

設計・実装は以下の調査結果を根拠とする。

### 2.1 主要参考記事

| # | 記事／ドキュメント | 本ツールへの反映点 |
|---|---|---|
| A | [Zabbix API でラクにミスなく大量のホストを登録しよう！（アークシステム）](https://devlog.arksystems.co.jp/2019/08/06/8884/) | ①認証トークンを取得処理として切り出す ②**ホストグループ → ホストの順**で作成する（グループ未作成だと `host.create` がエラー）③**ホストグループは名前ではなく ID 指定が必須**のため名前→ID 変換層を設ける |
| B | [Introducing zabbix_utils - the official Python library for Zabbix（Zabbix 公式ブログ）](https://blog.zabbix.com/python-zabbix-utils/27056/) | 公式ライブラリの存在。ただし追加依存を避けたい現場もあるため、本ツールは `requests` のみの薄い自前クライアントを標準とし、`zabbix_utils` 相当の API 呼び出し形式に合わせる |
| C | [Python library for Zabbix / Use Zabbix API（Zabbix 7.4 公式ドキュメント）](https://www.zabbix.com/documentation/7.4/en/devel/python/api) | 7.0 以降は **API トークン（Bearer）認証**を標準とする |
| D | [4 API tokens（Zabbix 公式ドキュメント）](https://www.zabbix.com/documentation/7.4/en/manual/web_interface/frontend_sections/users/api_tokens) | UI で発行した API トークンを使用。パスワードをスクリプトに埋め込まない |
| E | [host.create（Zabbix 公式 API リファレンス）](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/create) | `host.create` は**オブジェクトの配列を受け付ける**＝1 リクエストで複数ホストを作成可能。必須項目は `host` と `groups` |
| F | [Host object（Zabbix 公式 API リファレンス）](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/object) | 7.0 以降は `proxy_hostid` が廃止され **`monitored_by`（0=サーバー / 1=プロキシ / 2=プロキシグループ）+ `proxyid` / `proxy_groupid`** になった |
| G | [CSV ファイルを読み込んで Zabbix にホスト登録（Zenn / Qiita）](https://zenn.dev/charatech_bps/articles/9fc68db3d4a66c) | CSV を入力とする実装パターン。ただしテンプレート ID／グループ ID をスクリプトに固定している点は本ツールでは名前解決に置き換える |
| H | [API を活用した Zabbix のホスト管理（サイバートラスト）](https://www.cybertrust.co.jp/blog/linux-oss/system-monitoring/tech-lounge/zabbix-api.html) | `host.get` でホスト名から hostid を引き、`host.update` で更新するパターン。冪等化の土台 |
| I | [Supporting bulk operations in REST APIs（Michael Scharhag）](https://www.mscharhag.com/api-design/bulk-and-batch-operations) | バルク API は通信回数を減らせるが、**一括失敗時にどの要素が失敗したかを特定できる設計**が必要 |
| J | [community.zabbix.zabbix_host module（Ansible）](https://docs.ansible.com/projects/ansible/latest/collections/community/zabbix/zabbix_host_module.html) | 冪等モジュールのパラメータ体系（`host_groups` / `link_templates` / `interfaces` / `tags` / `macros`）を入力スキーマ設計の参考にする |

### 2.2 調査から得た設計上の教訓

1. **記事 A の 3 ポイントは必須要件**である。特に「名前→ID 変換」は、記事 A の実装がホスト 1 台ごとに `hostgroup.get` を呼ぶ N+1 構造になっており、300 台では 300 回の余計な API 呼び出しが発生する。→ **本ツールでは事前に一括解決してキャッシュする**（改善点）。
2. 参考記事の多くは `host.create` のみで、**既存ホストが存在すると `already exists` エラーで止まる**。→ **本ツールは `host.get` による事前突合で create / update / no-op を判定する**（改善点）。
3. 記事 E より `host.create` は配列を受け付けるため、記事 I の指摘（失敗要素の特定）と合わせて **チャンク投入＋失敗時の単体リトライ**という二段構えにする（改善点）。
4. 記事 F より、7.0 のプロキシ指定は 6.x とは非互換。→ **API バージョンを実行時に検出して分岐する**。

---

## 3. 前提条件

| 項目 | 内容 |
|---|---|
| Zabbix バージョン | 7.0 LTS 以降（6.0 / 6.4 も互換モードで動作） |
| API エンドポイント | `https://<zabbix>/api_jsonrpc.php` |
| 認証 | 次のいずれか（Super admin または Admin ロール）。①UI で発行した API トークンを環境変数 `ZABBIX_TOKEN` で受け渡す（推奨） ②`--user` + パスワード（環境変数 `ZABBIX_PASSWORD` または対話入力）による `user.login` |
| 実行環境 | Python 3.9 以降 / 外部依存は `requests`（YAML 利用時のみ `PyYAML`） |
| ネットワーク | 実行ホストから Zabbix フロントエンドへ HTTPS 到達可能 |
| 実行者 | Zabbix 運用担当（Python の読み書きは必須でない。CSV 編集とコマンド実行ができれば足りる） |

---

## 4. 機能要件

### FR-01 入力の受付
- **FR-01-1** CSV ファイルを入力として受け付ける（UTF-8 / UTF-8 BOM 付きの双方に対応。Excel からの書き出しを想定）
- **FR-01-2** YAML ファイルを入力として受け付ける（`defaults` による共通値の定義と、ホスト単位の上書きに対応）
- **FR-01-3** 複数ファイルの同時指定に対応する
- **FR-01-4** CSV の 1 セル内に複数値を書くための区切り文字は `;` とする（記事 A と同様に、IP やホスト名にカンマ・空白が混入しても壊れないようにするため）

### FR-02 名前解決
- **FR-02-1** ホストグループ・テンプレート・プロキシ・プロキシグループは、入力では**名前で指定**する（ID 指定を運用者に強制しない）
- **FR-02-2** 名前→ID の解決は、入力全体から名前の集合を作り**1 リクエストで一括取得**する（N+1 回避）
- **FR-02-3** 解決できない名前は事前検証でエラーとして列挙する

### FR-03 ホストグループの自動作成
- **FR-03-1** 入力に存在し Zabbix 側に存在しないホストグループは、`--create-groups` 指定時に `hostgroup.create` で作成する
- **FR-03-2** 作成は**必ずホスト作成より前**に行う（記事 A ポイント 2）

### FR-04 ホストの作成・更新（冪等）
- **FR-04-1** `host` （技術名）をキーに既存ホストを突合する
- **FR-04-2** 未存在なら CREATE、存在して差分ありなら UPDATE、差分なしなら NOOP と判定する
- **FR-04-3** 設定可能な項目は次の通り
  - 基本: `host` / `name`（表示名）/ `status`（有効・無効）/ `description` / `inventory_mode`
  - インターフェース: Agent / SNMP / IPMI / JMX、`useip`・`ip`・`dns`・`port`・`main`、SNMP は `version`・`community`・`bulk`
  - ホストグループ（複数）
  - テンプレートリンク（複数）
  - ユーザーマクロ `{$XXX}`（値・種別 text/secret/vault・説明）
  - ホストタグ（`tag` / `value`）
  - 監視元（Zabbix サーバー / プロキシ / プロキシグループ）
- **FR-04-4** 更新時の既定動作は**加算マージ**とする（Zabbix 側にあってファイルに無いグループ・テンプレート・タグ・マクロは残す）。`--prune` 指定時のみファイルの内容に完全一致させる
- **FR-04-5** インターフェースは、種別と `main` が一致する既存インターフェースの `interfaceid` を引き継いで更新する（アイテムのインターフェース参照を壊さないため）

### FR-05 バルク投入
- **FR-05-1** `host.create` はチャンク単位（既定 50 件）でオブジェクト配列を投入する
- **FR-05-2** チャンクが失敗した場合、そのチャンク内を 1 件ずつ再投入して**失敗したホストのみを特定**する（記事 I）
- **FR-05-3** チャンクサイズは CLI で変更できる

### FR-06 事前検証（バリデーション）
書き込みを 1 件も行う前に、以下を全件検査してエラーを列挙する。
- **FR-06-1** 必須項目（`host`、ホストグループ 1 つ以上）の有無
- **FR-06-2** ホスト名の重複（入力ファイル内）
- **FR-06-3** IP アドレス／ポート／`useip` の整合性（`useip=1` なら `ip` 必須、`useip=0` なら `dns` 必須）
- **FR-06-4** マクロ名の書式（`{$NAME}` 形式）
- **FR-06-5** インターフェース種別ごとの `main` の重複
- **FR-06-6** 名前解決の失敗（FR-02-3）

### FR-07 dry-run
- **FR-07-1** `--dry-run` 指定時は一切の書き込み API を呼ばず、CREATE / UPDATE / NOOP の判定結果と差分内容を出力する
- **FR-07-2** dry-run は既定動作とはせず、明示指定とする（ただし本番適用前の実施を手順書で必須化する）

### FR-08 レポート
- **FR-08-1** 標準出力に 1 行 1 ホストのサマリ（`CREATE` / `UPDATE` / `NOOP` / `FAIL` + 理由）を出力する
- **FR-08-2** `--report <path>` で JSON 形式の実行結果を出力する（差分内容・エラーメッセージ・hostid を含む）
- **FR-08-3** 終了コードは `0`=全件成功、`1`=1 件以上失敗、`2`=事前検証エラーで未実行 とする

### FR-09 ログ
- **FR-09-1** `--verbose` で API リクエスト／レスポンスの要約を出力する
- **FR-09-2** ログ・レポートに認証情報（パスワード・API トークン・セッション ID）および secret 型マクロの値を出力しない（`***` にマスクする）

### FR-10 認証
- **FR-10-1** API トークン方式（`--token` / `$ZABBIX_TOKEN`）に対応する
- **FR-10-2** ID/パスワード方式（`--user` + `$ZABBIX_PASSWORD` または対話入力）に対応し、トークン未発行でも利用できるようにする
- **FR-10-3** パスワードはコマンドライン引数で受け取らない（`ps` およびシェル履歴への残留を防ぐため）
- **FR-10-4** 非対話環境でパスワードが得られない場合は、プロンプトで待たずに exit 3 で終了する
- **FR-10-5** `user.login` で取得したセッションは、正常終了・異常終了を問わず `user.logout` で無効化する（API トークンは無効化しない）
- **FR-10-6** `user.login` のパラメータ名はバージョンで切り替える（6.0 以降は `username`、5.x 以前は `user`）

---

## 5. 非機能要件

| ID | 分類 | 要件 |
|---|---|---|
| NFR-01 | 性能 | 1,000 ホストの新規登録を 10 分以内に完了する。名前解決の API 呼び出し回数はホスト数に依存しない（O(1)） |
| NFR-02 | 冪等性 | 同一入力で 2 回連続実行した場合、2 回目は全件 NOOP となる |
| NFR-03 | 安全性 | ホストの削除は行わない。既定では既存設定を減らさない（加算マージ） |
| NFR-04 | 耐障害性 | 接続エラー・HTTP 5xx・タイムアウトに対し指数バックオフで最大 3 回再試行する。書き込み系の再試行前には `host.get` で実際の反映状況を再確認し、二重作成を防ぐ |
| NFR-05 | 機密性 | 認証情報は環境変数または 0600 権限の設定ファイルから読む。コード・入力 CSV に平文で持たない |
| NFR-06 | 保守性 | 外部依存は `requests`（+ YAML 利用時 `PyYAML`）のみ。単一ファイルで配布可能とする |
| NFR-07 | 互換性 | `apiinfo.version` で API バージョンを検出し、7.0 以降と 6.x のプロキシ指定・認証方式の差異を吸収する |
| NFR-08 | 可監査性 | JSON レポートにより「いつ・どのホストに・何を変更したか」を追跡できる |

---

## 6. 制約事項

- Zabbix API はトランザクションを提供しないため、実行途中で中断した場合は「一部反映済み」の状態になる。冪等性（NFR-02）により再実行で復旧する方針とする。
- `host.create` のバルク投入は 1 リクエスト単位で成否が決まる。部分成功は API 仕様上あり得ないため、FR-05-2 の単体再投入で切り分ける。
- ホストの技術名（`host`）を後から変更する運用は本ツールの突合キーを壊すため、非対応とする（別名変更は表示名 `name` で行う）。

---

## 7. 受け入れ基準

| # | 基準 | 検証方法 |
|---|---|---|
| AC-01 | サンプル CSV 10 件が新規登録できる | dry-run → 実行 → Web UI 目視 |
| AC-02 | 同じファイルで再実行すると全件 NOOP になる | 2 回目実行の標準出力 |
| AC-03 | 表示名・タグ・マクロを 1 箇所変更して再実行すると、その 1 件のみ UPDATE になる | 差分出力の確認 |
| AC-04 | 未存在のホストグループ名を書いた行が、事前検証でエラーとして報告され、書き込みが 1 件も走らない | `--dry-run` なしで実行し終了コード 2 を確認 |
| AC-05 | 不正な行（IP 欠落など）が 1 行あると、書き込み前に全件停止する | 事前検証の出力 |
| AC-06 | チャンク内 1 件が API エラーになった場合、他の 49 件は成功し、失敗 1 件が特定できる | 重複ホスト名などを故意に混ぜて実行 |
| AC-07 | レポート JSON にトークン・secret マクロ値が含まれない | レポートの grep |
| AC-08 | 単体テストが全件パスする | `python3 tests/test_zbx_bulk_host.py` |
| AC-09 | API トークンを持たない状態で、Admin の ID/パスワードだけで登録・更新ができる | `--user Admin` で apply → 再実行で全件 NOOP |
| AC-10 | `--user` 実行の終了時に `user.logout` が呼ばれ、セッションが無効化される | モック API の呼び出し履歴 |
| AC-11 | `-v` 実行時のログにパスワード・トークンの平文が出ない | ログ全体を平文文字列で grep |

---

## 8. 未決事項 / 今後の拡張候補

- ホストの棚卸し（ファイルに無い既存ホストの検出・無効化）— 別サブコマンド `audit` として追加を検討
- IP レンジからのホスト定義自動生成 — 今回のヒアリングでは入力元に選ばれなかったため保留（`generate` サブコマンドとして拡張可能）
- Excel(xlsx) 直読み — 現状は「Excel で編集 → CSV 保存」の運用で代替
- CI での dry-run 自動実行（入力ファイルを Git 管理する前提での構成レビュー）

---

## 参考リンク一覧

- [Zabbix API でラクにミスなく大量のホストを登録しよう！ — アークシステム](https://devlog.arksystems.co.jp/2019/08/06/8884/)
- [【5.0対応済】Python3でZabbix API – ホストの登録と削除 — アークシステム](https://devlog.arksystems.co.jp/2020/10/20/13611/)
- [Introducing zabbix_utils - the official Python library for Zabbix — Zabbix Blog](https://blog.zabbix.com/python-zabbix-utils/27056/)
- [Python library for Zabbix — Zabbix Documentation](https://www.zabbix.com/documentation/7.4/en/devel/python)
- [Use Zabbix API — Zabbix Documentation](https://www.zabbix.com/documentation/7.4/en/devel/python/api)
- [API tokens — Zabbix Documentation](https://www.zabbix.com/documentation/7.4/en/manual/web_interface/frontend_sections/users/api_tokens)
- [host.create — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/create)
- [host.update — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/update)
- [Host object — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/host/object)
- [hostgroup.create — Zabbix API Reference](https://www.zabbix.com/documentation/current/en/manual/api/reference/hostgroup/create)
- [CSVファイルを読み込んでZabbixにホスト登録 — Zenn](https://zenn.dev/charatech_bps/articles/9fc68db3d4a66c)
- [API を活用した Zabbix のホスト管理 — サイバートラスト](https://www.cybertrust.co.jp/blog/linux-oss/system-monitoring/tech-lounge/zabbix-api.html)
- [community.zabbix.zabbix_host module — Ansible Documentation](https://docs.ansible.com/projects/ansible/latest/collections/community/zabbix/zabbix_host_module.html)
- [Supporting bulk operations in REST APIs — Michael Scharhag](https://www.mscharhag.com/api-design/bulk-and-batch-operations)
