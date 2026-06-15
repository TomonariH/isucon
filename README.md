# isucon

ISUCON 競技向けスクリプト・スキル集。  
`~/private-isu` を試験環境として動作確認している。

## ディレクトリ構成

```
scripts/
  install-claude.sh # Claude Code CLI をインストールする
  setup.sh          # 1台構成用ラッパー（下記4スクリプトをまとめて実行）
  setup-tools.sh    # alp / pt-query-digest インストール（分析実行サーバー）
  setup-nginx.sh    # nginx LTSV アクセスログ設定（nginx サーバー）
  setup-mysql.sh    # MySQL スロークエリログ設定（DB サーバー、ローカル MySQL 用）
  setup-app.sh      # git init / reports ディレクトリ作成（アプリサーバー）
  setup-docker.sh   # Docker Compose 環境向けセットアップ（ログ expose・nginx LTSV・MySQL slow log）
  setup-rds.sh      # RDS 環境向けセットアップ（MySQL が AWS RDS / Aurora の場合）
  lib.sh            # 共通環境検出ライブラリ（OS / arch / MySQL サービス名など）
  analyze.sh        # ベンチ後に毎回実行する計測・レポート生成（H2O 自動検出）
  analyze-rds.sh    # RDS 環境向け分析（mysql.slow_log テーブル対応）
  score-log.sh      # スコアを reports/scores.md に記録
  unsetup.sh        # setup.sh の変更を元に戻す
  alp.yml           # alp の設定（URI 正規化パターンなど）
templates/
  nginx-ltsv.conf           # nginx LTSV アクセスログ設定
  mysql-slow.cnf            # MySQL スロークエリログ設定
  nginx-staticfile.conf     # 静的ファイル直接配信設定（画像 DB 脱却後に使用）
  nginx-upstream.conf       # 複数台構成のロードバランシング設定
  mysql-remote.cnf          # MySQL 外部接続許可設定（DB サーバー分離時）
  rds-parameter-group.md    # RDS パラメータグループ手動設定手順
  go-pprof.snippet          # Go pprof エンドポイント追加コード
  h2o-ltsv.conf             # H2O web server LTSV ログ設定
.claude/commands/
  isucon-survey.md          # /isucon-survey スキル（競技開幕の環境調査）
  isucon-analyze.md         # /isucon-analyze スキル
  isucon-review-app.md      # /isucon-review-app スキル
  isucon-fix.md             # /isucon-fix スキル
  isucon-multiserver.md     # /isucon-multiserver スキル（複数台構成）
  isucon-pprof.md           # /isucon-pprof スキル（Go pprof）
reports/                    # analyze.sh が生成するレポートの出力先
```

---

## 競技当日の使い方

### Phase 0 — 事前準備

```bash
git clone <this-repo> ~/isucon-tools
cd ~/isucon-tools
bash scripts/install-claude.sh
```

Claude Code がまだ入っていない端末では、リポジトリを clone した直後にこれを実行しておく。

### Phase 1 — 競技開始直後（最初の 5 分）

```
/isucon-survey
```

出力例:

```
## ISUCON 環境サマリー

### サーバー
- OS: Ubuntu 22.04 (x86_64)
- 実行環境: systemd
- Web サーバー: nginx 1.24
- アプリ: Go (サービス名: isu-go, ポート: 8080)
- webapp パス: /home/isucon/webapp

### DB
- 種別: ローカル MySQL
- ホスト: localhost
- ユーザー: isucon

### セットアップ手順

source scripts/env.sh
bash scripts/setup-tools.sh
bash scripts/setup-nginx.sh
bash scripts/setup-mysql.sh
bash scripts/setup-app.sh
```

出力されたセットアップ手順をそのまま実行する。

---

### Phase 2 — 改善ループ

このフェーズでは、複数エージェントで改善候補を並列実装し、改善したものだけを統合する。Claude Code には次の手順をそのまま投げる。

```text
/goal
競技中の改善ループを以下の手順で実行せよ。

前提:
- 統合先ブランチは `$APP_REPO` の `feature/isucon-work` とする。
- rebuild/restart と benchmark は必ず `$TOOL_REPO/scripts/bench-locked.sh` で実行し、他エージェントの rebuild/restart/benchmark と同時に実行しない。

ループ:
1. `APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"` を設定し、`$APP_REPO` の `feature/isucon-work` に移動する。
2. `$TOOL_REPO/scripts/bench-locked.sh` を1回実行し、現在の基準スコアを確認する。
3. `$TOOL_REPO/scripts/analyze.sh` を実行し、その結果を `/isucon-analyze` スキルで分析する。
4. `/isucon-analyze` の結果から、高インパクト・中インパクトの提案だけを抽出する。
   - 抽出した候補は、候補ごとに `$TOOL_REPO/scripts/improvement-log.sh candidate ...` で記録する。
   - 候補ID、インパクト、難易度、予定ブランチ、改善方法を必ず残す。
5. 抽出した提案が存在しない、つまり小インパクトのみになったら終了する。
6. 高・中インパクトの提案を、提案項目1つにつき1つの独立 worktree/branch に分けて並列修正する。
   - ファイルやインパクトでまとめず、必ず提案単位で分ける。
   - 各作業ブランチは `feature/<短い内容>` のように命名する。
   - メインエージェントは候補抽出、worktree/branch作成、評価、merge採否だけを担当する。
   - 実装は候補ごとに別サブエージェントへ委譲する。同時実装数は最大5件までに制限する。
   - 各サブエージェントは割り当てられた1候補・1worktreeのみを編集する。
   - 各サブエージェントはコード修正、ローカルテスト、commit作成まで行い、結果をメインエージェントへ報告する。
   - 各サブエージェントは rebuild/restart、benchmark、merge を実行しない。
   - rebuild/restart、benchmark、merge はメインエージェントだけが直列に実行する。
7. 各修正ブランチごとに、`$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
   - pass し、基準スコアより明確に改善した修正だけを merge 対象にする。
   - 採否は `$TOOL_REPO/scripts/improvement-log.sh eval ...` で記録する。
8. merge は `$APP_REPO` の `feature/isucon-work` に対して行い、commit を必ず残す。squash しない。
   - コンフリクトが出た場合は自動解決を試みる。
   - 解決後は、`$TOOL_REPO/scripts/bench-locked.sh --rebuild` を実行する。
   - pass し、スコア改善が維持される場合のみ merge を確定する。
   - 自動解決が不確実、またはスコア改善が消えた場合は、その修正は merge しない。
9. merge 後、改善スコアを `$TOOL_REPO/scripts/score-log.sh` で記録する。
10. 手順4で抽出した全ての高・中インパクト提案を評価し終えたら、手順2に戻る。
   - 未mergeのworktree/branchは勝手に削除しない。
   - 残す、後で消す、再評価する、の判断を `$TOOL_REPO/scripts/improvement-log.sh cleanup ...` で記録する。
11. `/isucon-analyze` の結果が小インパクトのみになるまで、このループを継続する。

禁止:
- `git reset --hard` などの破壊的操作
- unrelated changes の巻き戻し
- 複数提案を1つの worktree にまとめること
```

---

## スクリプトリファレンス

### `scripts/setup.sh`

1台構成用ラッパー。`setup-tools.sh` → `setup-nginx.sh` → `setup-mysql.sh` → `setup-app.sh` をまとめて実行する。

```bash
bash scripts/setup.sh

# webapp ディレクトリを指定する場合
ISUCON_WEBAPP_DIR=/path/to/webapp bash scripts/setup.sh
```

冪等。各コンポーネントスクリプトは既に適用済みの設定をスキップする。コンポーネントが別サーバーに分かれている場合は個別スクリプトを直接実行する。

### `scripts/analyze.sh`

```bash
bash scripts/analyze.sh

# ログパスが標準と異なる場合
NGINX_ACCESS_LOG=/var/log/nginx/app.log \
MYSQL_SLOW_LOG=/var/log/mysql/slow.log \
bash scripts/analyze.sh

# ログローテートを無効化（デバッグ用）
ROTATE_LOGS=0 bash scripts/analyze.sh
```

出力: `reports/YYYYMMDD-HHMMSS.md`

### `scripts/bench-locked.sh`

```bash
# ベンチだけ実行。実行前にログをtruncateし、1回分のログ窓を作る
bash scripts/bench-locked.sh

# rebuild/restart と benchmark を同じ排他ロック内で連続実行
# 再起動後、その環境で必要なプロセス/接続性を確認してからベンチする
bash scripts/bench-locked.sh --rebuild

# デバッグ時だけ、既存ログを残して実行
bash scripts/bench-locked.sh --no-reset-logs

# 追加の起動確認を入れる
HEALTHCHECK_CMD='curl -fsS http://localhost/initialize >/dev/null' \
bash scripts/bench-locked.sh --rebuild
```

出力: benchmarker のJSON。直後に `bash scripts/analyze.sh` を実行すると、そのベンチ1回分だけを解析できる。

### `scripts/score-log.sh`

```bash
bash scripts/score-log.sh <score> [メモ]

# 例
bash scripts/score-log.sh 3200 "N+1解消"
bash scripts/score-log.sh 5800 "画像をファイルシステムに移動"
```

出力: `reports/scores.md`（なければ自動作成）。`scripts/env.sh` から `ISUCON_WEBAPP_DIR` を読み、`APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"` の HEAD commit を記録する。

### `scripts/improvement-log.sh`

```bash
bash scripts/improvement-log.sh candidate C1 high low feature/cache-user "cache user lookup"
bash scripts/improvement-log.sh eval C1 feature/cache-user 12345 true merged "improved baseline"
bash scripts/improvement-log.sh cleanup feature/cache-user /tmp/wt kept "left for audit"
```

出力: `reports/improvement-loop.md`（候補、評価、worktree後片付け方針を追記）

### `scripts/alp.yml`

URI 正規化パターンを競技アプリに合わせて編集する。

```yaml
uri_matching_groups:
  - ^/posts/[0-9]+$       # /posts/123 → /posts/:id
  - ^/image/[0-9]+\.(jpg|jpeg|png|gif)$
  - ^/@[a-zA-Z0-9_]+$    # /@username
  - ^/api/.*$
```

---

## Claude Code スキルリファレンス

### `/isucon-survey`

競技開始直後にサーバーを調査し、環境サマリーと推奨セットアップコマンドを提示する。  
OS / アーキテクチャ・動作サービス・アプリのサービスファイル・DB 接続情報（`EnvironmentFile=` 参照先も読む）・DB 種別（ローカル / RDS / Aurora）・静的ファイルパスを一括調査する。

```
/isucon-survey
```

出力例:
```
## ISUCON 環境サマリー

### サーバー
- OS: Ubuntu 22.04 (x86_64)
- Web サーバー: nginx 1.24
- アプリ: Go (サービス名: isu-go, ポート: 8080)
- webapp パス: /home/isucon/webapp

### DB
- 種別: ローカル MySQL
- ホスト: localhost
- ユーザー: isucon

### 推奨セットアップコマンド
bash scripts/setup-tools.sh
bash scripts/setup-nginx.sh
bash scripts/setup-mysql.sh
bash scripts/setup-app.sh
```

### `/isucon-analyze`

`reports/` の最新レポートを読んで改善優先順位 TOP5 を提示する。  
`analyze.sh` 実行後に使う。

### `/isucon-review-app`

アプリコードを全ファイル読んでパフォーマンス問題を列挙する。  
競技開始直後、初回ベンチの前後どちらでも使える。  
N+1 クエリ・インデックス不足・キャッシュ化の余地・BLOB 画像などを検出する。

### `/isucon-fix <対象>`

指定した問題を実装する。修正後に `git diff` の確認と `score-log.sh` でのスコア記録を促す。

```
/isucon-fix GET /posts の N+1 クエリを JOIN に書き直す
/isucon-fix comments テーブルの post_id にインデックスを追加
/isucon-fix 画像を DB から取り出してファイルシステムに保存するスクリプトを作る
```

---

## テンプレートリファレンス

### `templates/nginx-ltsv.conf`

`setup.sh` が自動適用する。手動で適用する場合:

```bash
sudo cp templates/nginx-ltsv.conf /etc/nginx/conf.d/ltsv.conf
sudo nginx -t && sudo systemctl reload nginx
```

### `templates/mysql-slow.cnf`

`setup.sh` が自動適用する。手動で適用する場合:

```bash
# Ubuntu / Debian
sudo cp templates/mysql-slow.cnf /etc/mysql/conf.d/slow-query.cnf
sudo systemctl restart mysql

# Amazon Linux 2 / 2023
sudo cp templates/mysql-slow.cnf /etc/my.cnf.d/slow-query.cnf
sudo systemctl restart mysqld
```

### `templates/nginx-staticfile.conf`

画像を DB から取り出してファイルシステムに移した後で使う静的配信設定。  
`/isucon-fix 画像をファイルシステムに移動` と併用する。

---

## パターン別対応ガイド

ISUCON の競技環境は毎年異なる。以下は頻出パターンへの対処法。

### アプリが Docker Compose で動いている場合

nginx / app / MySQL がすべてコンテナで動いている構成（private-isu など）。

まず Claude Code で `/isucon-survey` を実行し、`scripts/env.sh` を生成する。

```bash
# このリポジトリをホストに clone してから
source scripts/env.sh
bash scripts/setup-tools.sh
bash scripts/setup-app.sh
bash scripts/setup-docker.sh
```

`setup-docker.sh` が行うこと:
- `docker-compose.isucon-logs.yml` を生成してコンテナのログをホストの `<compose-dir>/logs/` にマウント
- 既存の `docker-compose.override.yml` があれば保持したまま、ISUCON用 override を追加で重ねて起動する
- nginx LTSV ログ設定をホスト側 conf.d に配置してリロード
- `docker compose exec -T <mysql-service> mysql -e "SET GLOBAL slow_query_log = 1; ..."` でスロークエリログを有効化
- `/isucon-survey` が生成した `scripts/env.sh` の `DOCKER_COMPOSE_DIR` / `DOCKER_NGINX_SERVICE` / `DOCKER_MYSQL_SERVICE` / `NGINX_CONF_HOST_DIR` を読む

`docker-compose.isucon-logs.yml` は Docker Compose のデフォルトファイル名ではない。以後手動で `docker compose up` / `restart` する場合は、`setup-docker.sh` を再実行するか、スクリプトが最後に表示する `-f ...` 一式を付けて実行する。

ベンチ後の分析:

```bash
# scripts/env.sh は analyze.sh が自動で読む
bash scripts/analyze.sh
```

nginx conf.d がデフォルトパス（`<compose-dir>/etc/nginx/conf.d`）と異なる場合:

```bash
NGINX_CONF_HOST_DIR=/path/to/nginx/conf.d \
DOCKER_COMPOSE_DIR=... \
DOCKER_NGINX_SERVICE=... \
DOCKER_MYSQL_SERVICE=... \
bash scripts/setup-docker.sh
```

---

### MySQL が AWS RDS の場合

RDS では `SET GLOBAL slow_query_log = 1` が使えない。専用スクリプトを使う。

```bash
# RDS への接続情報を設定
export DB_HOST=<rds-endpoint>
export DB_USER=isucon
export DB_PASS=isucon

# セットアップ（ツール・nginx・git init を共通スクリプトに委譲 + long_query_time を動的設定 + パラメータグループ案内）
bash scripts/setup-rds.sh

# AWS CLI でパラメータグループを直接変更する場合
export RDS_INSTANCE=isucon-db
export RDS_PARAM_GROUP=isucon-params
bash scripts/setup-rds.sh --aws-cli
```

パラメータグループの手動設定手順: `templates/rds-parameter-group.md`

ベンチ後の分析:

```bash
# mysql.slow_log テーブルから取得して pt-query-digest で分析
DB_HOST=<rds-endpoint> bash scripts/analyze-rds.sh
```

`analyze-rds.sh` が行うこと:
- `mysql.slow_log` テーブル（TABLE モード）からスロークエリを取得して pt-query-digest で分析
- TABLE モード未設定の場合のみ AWS CLI でログファイルを取得する（フォールバック）
- デフォルトでは `mysql.slow_log` をローテートしない。リセットする場合のみ `ROTATE_RDS_SLOW_LOG=1` を指定する
- H2O サービスが稼働していて `/etc/h2o/h2o.conf` が存在すれば H2O のアクセスログを自動検出（`analyze.sh` と同じ挙動）

---

### 複数台構成（2〜3台）の場合

```bash
# Claude Code で役割分担の設計を依頼する
/isucon-multiserver
```

スキルが案内してくれること:
- サーバースペックに基づいた役割分担案（nginx 専用 / app / DB）
- `templates/nginx-upstream.conf` ベースの upstream 設定生成
- DB サーバーの外部接続許可手順

**nginx upstream 設定（`templates/nginx-upstream.conf`）**:

```bash
# templates/nginx-upstream.conf を参考に、既存の server block へ
# upstream と proxy_pass の差分だけを反映する
sudo nginx -T | grep -E 'server_name|proxy_pass|include .*(conf.d|sites-enabled)'
sudoedit <既存の nginx server 設定ファイル>
sudo nginx -t && sudo systemctl reload nginx
```

**MySQL を別サーバーに分離する場合（`templates/mysql-remote.cnf`）**:

```bash
# DB サーバーで実行（サービス名・conf dir は環境で異なる）
systemctl list-units --type=service | grep -E 'mysql|mariadb'  # サービス名確認
ls /etc/mysql/conf.d 2>/dev/null || ls /etc/my.cnf.d 2>/dev/null  # conf dir 確認

sudo cp templates/mysql-remote.cnf <conf-dir>/remote.cnf
sudo systemctl restart <mysql|mysqld|mariadb>

# app サーバーの接続先を変更
export DB_HOST=<db-server-ip>
```

---

### Go アプリの pprof プロファイリング

```bash
# pprof エンドポイント追加の案内（コード変更）
/isucon-pprof
```

スキルが案内してくれること:
- `templates/go-pprof.snippet` のコードを main.go に追加
- echo / gin / chi 各フレームワーク向けの登録方法
- ベンチマーク中のプロファイル取得コマンド
- 取得した `top10` 出力をペーストすると改善提案

手動で取得する場合:

```bash
# CPU プロファイル（ベンチマーク実行中に 30秒計測）
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/profile?seconds=30

# ヒープ（メモリ）プロファイル
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/heap
```

Docker Compose 環境では、まずコンテナ内から `127.0.0.1:6060` に届くか確認する。ホストから取得する場合は、SSH port-forward または localhost 限定のポート公開を使う。

---

### H2O が Web サーバーの場合

H2O の設定ファイルに LTSV ログを追加する:

```bash
# /etc/h2o/h2o.conf に LTSV ログ設定を追加
# templates/h2o-ltsv.conf の access-log セクションをコピーして適用
sudo nano /etc/h2o/h2o.conf
sudo systemctl reload h2o
```

`analyze.sh` と `analyze-rds.sh` はどちらも H2O サービスが稼働していて `/etc/h2o/h2o.conf` が存在すれば自動的に H2O のログを使う:

```bash
# H2O が検出されると /var/log/h2o/access.log を自動で読む
bash scripts/analyze.sh
# RDS 環境でも同様
DB_HOST=<rds-endpoint> bash scripts/analyze-rds.sh

# ログパスが異なる場合は明示指定（両スクリプト共通）
NGINX_ACCESS_LOG=/var/log/h2o/access.log bash scripts/analyze.sh
NGINX_ACCESS_LOG=/var/log/h2o/access.log bash scripts/analyze-rds.sh
```

---

### Amazon Linux 2 / 2023・ARM64 (aarch64) の場合

`setup.sh` はそのまま動く。`lib.sh` が OS とアーキテクチャを自動検出する。

| 項目 | 自動対応内容 |
|------|-------------|
| アーキテクチャ | `uname -m` で判定し `alp_linux_arm64.tar.gz` を使用 |
| パッケージマネージャー | `dnf`（AL2023）/ `yum`（AL2）を自動選択 |
| Percona リポジトリ | RHEL 系では自動追加（`percona-release-latest.noarch.rpm`） |
| MySQL サービス名 | `mysql` / `mysqld` / `mariadb` を順に探索 |
| MySQL 設定 dir | `/etc/mysql/conf.d`（Debian 系）/ `/etc/my.cnf.d`（RHEL 系）を自動選択 |

```bash
# Amazon Linux 2 / 2023 でも同じコマンドで動く
bash scripts/setup.sh
```
