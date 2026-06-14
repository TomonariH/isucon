# isucon

ISUCON 競技向けスクリプト・スキル集。  
`~/private-isu` を試験環境として動作確認している。

## ディレクトリ構成

```
scripts/
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

### Phase 1 — 競技開始直後（最初の 5 分）

```bash
# このリポジトリをサーバーに clone
git clone <this-repo> ~/isucon-tools
cd ~/isucon-tools
```

まず環境を調査してからセットアップ方針を決める:

```
/isucon-survey
```

調査結果に基づいてセットアップを実行する:

```bash
# 1台構成の場合（調査結果から推奨コマンドが提示される）
sudo bash scripts/setup.sh
```

`setup.sh` は `setup-tools.sh` → `setup-nginx.sh` → `setup-mysql.sh` → `setup-app.sh` を順に呼ぶラッパー。各スクリプトが行うこと:

| スクリプト | 処理 |
|------------|------|
| `setup-tools.sh` | alp をインストール（amd64 / arm64 自動判定）、`pt-query-digest` をインストール（apt / dnf / yum 自動選択） |
| `setup-nginx.sh` | `templates/nginx-ltsv.conf` を `/etc/nginx/conf.d/` にコピーしてリロード（nginx がなければスキップ） |
| `setup-mysql.sh` | `SET GLOBAL` でスロークエリログを動的有効化（失敗時のみ `systemctl restart`）（MySQL/MariaDB がなければスキップ） |
| `setup-app.sh` | `reports/` ディレクトリ作成、`$ISUCON_WEBAPP_DIR` で `git init` + 初回コミット |

webapp ディレクトリが標準パスと異なる場合:

```bash
ISUCON_WEBAPP_DIR=/home/isucon/private_isu/webapp sudo bash scripts/setup.sh
```

**nginx / MySQL / アプリが別サーバーに分かれている場合**は個別スクリプトを使う:

```bash
# nginx サーバーで
sudo bash scripts/setup-nginx.sh

# DB サーバー（ローカル MySQL）で
sudo bash scripts/setup-mysql.sh

# アプリサーバーで
sudo bash scripts/setup-tools.sh
sudo bash scripts/setup-app.sh
```

---

### Phase 2 — 初回ベンチマーク → 分析

```bash
# ベンチマーク実行（環境に合わせたコマンドで）
./benchmarker -t http://localhost:8080 -u ./userdata

# 計測・レポート生成（ベンチ後に毎回実行）
bash scripts/analyze.sh
```

`analyze.sh` が行うこと:

- `alp` でアクセスログを URI 別・合計レスポンスタイム順に集計
- `pt-query-digest` でスロークエリを合計実行時間順に集計
- `reports/20240101-120000.md` のようなタイムスタンプ付きファイルに出力
- ログを次のベンチに備えて 0 バイトにリセット（`ROTATE_LOGS=0` で無効化）

レポートが生成されたら Claude Code で分析:

```
/isucon-analyze
```

出力例:

```
## ボトルネック分析

### TOP5 改善提案
1. [高インパクト/低難易度] GET /posts — sum 42.3s。N+1 クエリが疑われる
2. [高インパクト/低難易度] posts.user_id — インデックスなし、全スキャン
3. [中インパクト/中難易度] GET /image/:id — 画像を DB から返している
...

### 推奨アクション
posts.user_id にインデックスを追加する（実装 1 分、インパクト大）
```

---

### Phase 3 — コードレビュー → 実装

コードを読んでいない状態でも AI がボトルネックを列挙してくれる:

```
/isucon-review-app
```

特定の問題を修正させる場合:

```
/isucon-fix N+1クエリ: GET /posts のユーザー情報取得
/isucon-fix posts テーブルの user_id にインデックスを追加
/isucon-fix 画像をファイルシステムに移動して nginx で直接配信
```

画像を nginx から直接配信する場合は `templates/nginx-staticfile.conf` をベースにする:

```bash
sudo cp templates/nginx-staticfile.conf /etc/nginx/sites-available/isucon.conf
# パスをアプリに合わせて編集
sudo nginx -t && sudo systemctl reload nginx
```

---

### Phase 4 — 再ベンチ → スコア記録 → ループ

```bash
# ベンチ実行
./benchmarker -t http://localhost:8080 -u ./userdata
# {"pass":true,"score":3200,"success":2800,"fail":0,"messages":[]}

# スコアを記録
bash scripts/score-log.sh 3200 "posts.user_id にインデックス追加"

# 次の計測
bash scripts/analyze.sh

# Claude に次の手を聞く
/isucon-analyze
```

`reports/scores.md` にスコア履歴が蓄積される:

| Time | Score | Commit | Note |
|------|-------|--------|------|
| 2024-01-01 12:00:00 | **1710** | abc1234 | baseline |
| 2024-01-01 12:30:00 | **3200** | def5678 | posts.user_id にインデックス追加 |
| 2024-01-01 13:00:00 | **5800** | ghi9012 | 画像をファイルシステムに移動 |

Phase 2 〜 4 を制限時間まで繰り返す。

---

## スクリプトリファレンス

### `scripts/setup.sh`

1台構成用ラッパー。`setup-tools.sh` → `setup-nginx.sh` → `setup-mysql.sh` → `setup-app.sh` をまとめて実行する。

```bash
sudo bash scripts/setup.sh

# webapp ディレクトリを指定する場合
ISUCON_WEBAPP_DIR=/path/to/webapp sudo bash scripts/setup.sh
```

冪等。各コンポーネントスクリプトは既に適用済みの設定をスキップする。コンポーネントが別サーバーに分かれている場合は個別スクリプトを直接実行する。

### `scripts/analyze.sh`

```bash
bash scripts/analyze.sh

# ログパスが標準と異なる場合
NGINX_ACCESS_LOG=/var/log/nginx/app.log \
MYSQL_SLOW_LOG=/var/log/mysql/slow-query.log \
bash scripts/analyze.sh

# ログローテートを無効化（デバッグ用）
ROTATE_LOGS=0 bash scripts/analyze.sh
```

出力: `reports/YYYYMMDD-HHMMSS.md`

### `scripts/score-log.sh`

```bash
bash scripts/score-log.sh <score> [メモ]

# 例
bash scripts/score-log.sh 3200 "N+1解消"
bash scripts/score-log.sh 5800 "画像をファイルシステムに移動"
```

出力: `reports/scores.md`（なければ自動作成）

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
sudo bash scripts/setup-tools.sh
sudo bash scripts/setup-nginx.sh
sudo bash scripts/setup-mysql.sh
sudo bash scripts/setup-app.sh
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

## テスト環境（~/private-isu）

```bash
cd ~/private-isu/webapp
docker compose up -d

cd ~/private-isu/benchmarker
make  # 初回のみ
./bin/benchmarker -t http://localhost:8080 -u ./userdata
```

スコア例: `{"pass":true,"score":1710,"success":1434,"fail":0,"messages":[]}`

setup-docker.sh でログを自動的にホストに expose できる（下記 Docker Compose パターンを参照）。

---

## パターン別対応ガイド

ISUCON の競技環境は毎年異なる。以下は頻出パターンへの対処法。

### アプリが Docker Compose で動いている場合

nginx / app / MySQL がすべてコンテナで動いている構成（private-isu など）。

```bash
# このリポジトリをホストに clone してから
sudo bash scripts/setup-tools.sh
sudo bash scripts/setup-app.sh
DOCKER_COMPOSE_DIR=~/private-isu/webapp sudo bash scripts/setup-docker.sh
```

`setup-docker.sh` が行うこと:
- `docker-compose.override.yml` を生成してコンテナのログをホストの `<compose-dir>/logs/` にマウント
- nginx LTSV ログ設定をホスト側 conf.d に配置してリロード
- `docker compose exec mysql mysql -e "SET GLOBAL slow_query_log = 1; ..."` でスロークエリログを有効化
- `scripts/env-docker.sh` を生成（`analyze.sh` が自動 source）

ベンチ後の分析:

```bash
# env-docker.sh は analyze.sh が自動で読む
bash scripts/analyze.sh
```

nginx conf.d がデフォルトパス（`<compose-dir>/etc/nginx/conf.d`）と異なる場合:

```bash
NGINX_CONF_HOST_DIR=/path/to/nginx/conf.d DOCKER_COMPOSE_DIR=... sudo bash scripts/setup-docker.sh
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
sudo bash scripts/setup-rds.sh

# AWS CLI でパラメータグループを直接変更する場合
export RDS_INSTANCE=isucon-db
export RDS_PARAM_GROUP=isucon-params
sudo bash scripts/setup-rds.sh --aws-cli
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
- ベンチ後に `mysql.slow_log` を TRUNCATE してリセット
- `/etc/h2o/h2o.conf` が存在すれば H2O のアクセスログを自動検出（`analyze.sh` と同じ挙動）

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
# IP アドレスを編集してから適用
vim templates/nginx-upstream.conf
sudo cp templates/nginx-upstream.conf /etc/nginx/sites-available/isucon.conf
sudo ln -sf /etc/nginx/sites-available/isucon.conf /etc/nginx/sites-enabled/
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

---

### H2O が Web サーバーの場合

H2O の設定ファイルに LTSV ログを追加する:

```bash
# /etc/h2o/h2o.conf に LTSV ログ設定を追加
# templates/h2o-ltsv.conf の access-log セクションをコピーして適用
sudo nano /etc/h2o/h2o.conf
sudo systemctl reload h2o
```

`analyze.sh` と `analyze-rds.sh` はどちらも `/etc/h2o/h2o.conf` が存在すれば自動的に H2O のログを使う:

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
sudo bash scripts/setup.sh
```
