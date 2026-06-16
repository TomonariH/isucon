# /isucon-survey

ISUCON 競技開始直後の環境調査を行い、セットアップに必要な情報を `scripts/env.sh` と `reports/survey.md` に保存する。
保存後は「`source scripts/env.sh` してから各 setup スクリプトを実行する」だけでよい。

## Steps

0. **課題リポジトリを確認・clone する**

   まずユーザーに確認する:
   - 競技課題リポジトリの URL はわかっているか？
   - サーバー上に既に課題ディレクトリがあるか？

   ユーザーの回答をもとに clone するか既存パスを確定する:
   ```bash
   git clone <課題リポジトリ URL> ~/webapp
   # または既にある場合はパスを確認
   ls ~/webapp /home/isucon/webapp /opt/isucon 2>/dev/null
   ```

1. **サーバー基本情報を取得する**

   ```bash
   uname -m
   grep -E '^(ID|ID_LIKE|VERSION_ID)=' /etc/os-release
   ```

1a. **AWS managed 構成の場合はサービス構造を探索する**

   ユーザーが AWS / ECS / Fargate / ALB / RDS / Aurora / SQS に言及している、または配布 credential がある場合は、通常の systemd / Docker Compose 調査に入る前に AWS 全体構造を概観する。
   ローカル端末または作業用 EC2 で AWS CLI credential と region を確認する:

   ```bash
   aws sts get-caller-identity
   aws configure get region
   ```

   region が未設定なら、配布情報から `AWS_REGION` を設定してから discovery を実行する:

   ```bash
   AWS_REGION=<region> bash scripts/ecs/discover.sh
   ```

   `reports/aws-survey.md` から以下を特定する:
   - backend ECS cluster / service
   - frontend ALB / backend ALB
   - backend target group
   - benchmark SQS queue
   - Aurora cluster / DB instance / cluster parameter group / instance parameter group
   - ECR repository
   - nginx/app container の CloudWatch Logs group / stream prefix

   backend service が確定したら詳細調査を実行する:

   ```bash
   ECS_CLUSTER=<cluster> ECS_SERVICE=<backend-service> BENCH_QUEUE_NAME=<queue> bash scripts/ecs/survey.sh
   ```

   Fargate/ALB/Aurora 環境では、この結果を `scripts/env.sh` に反映する。最低限:

   ```bash
   export ISUCON_RUNTIME='ecs'
   export AWS_REGION='<region>'
   export ECS_CLUSTER='<cluster>'
   export ECS_SERVICE='<backend-service>'
   export DB_TYPE='aurora'
   export RDS_CLUSTER='<aurora-cluster-id>'
   export RDS_CLUSTER_PARAM_GROUP='<aurora-cluster-parameter-group>'
   export RDS_INSTANCE='<db-instance-id>'
   export RDS_PARAM_GROUP='<db-instance-parameter-group>'
   export ECR_REPOSITORY='<repository-name>'
   export BACKEND_ALB_NAME='<backend-alb-name>'
   export FRONTEND_ALB_NAME='<frontend-alb-name>'
   export BENCH_QUEUE_NAME='<benchmark-queue-name>'
   export BENCH_CMD='bash scripts/ecs/bench-sqs.sh'
   export REBUILD_CMD='bash scripts/ecs/deploy.sh'
   ```

   この場合、`reports/survey.md` には `reports/aws-survey.md` と `reports/ecs-survey.md` を参照した AWS 構成サマリーを含める。

2. **Docker Compose か systemd かを判定し、サービス一覧を取得する**

   まず Docker Compose の有無を確認する:
   ```bash
   ls <webapp-path>/compose.yml <webapp-path>/docker-compose.yml 2>/dev/null
   ```

   **Docker Compose がある場合**:
   ```bash
   docker compose -f <compose-file> ps
   cat <compose-file>
   ```
   compose.yml から読み取る:
   - サービス名と image/build コンテキスト → 言語を確認
   - nginx/mysql/memcached/redis 以外のサービス名 → `APP_SERVICES`（複数台構成なら全て列挙）
   - `environment:` → DB 接続情報（HOST / PORT / USER / PASSWORD / NAME）
   - MySQL の管理ユーザー情報（`MYSQL_ROOT_PASSWORD` など。slow query log 有効化に使う）
   - `volumes:` → webapp パスとホスト側マウントパス（nginx conf.d のホストパスを特定する）
   - nginx / MySQL の実サービス名（`setup-docker.sh` に渡す）
   - アプリのポート番号

   **systemd の場合**:
   ```bash
   systemctl list-units --type=service --state=active --no-pager
   ```
   出力から以下を探す:
   - **Web サーバー**: nginx / h2o / apache2 / httpd
   - **アプリ**: isu* / app* / go* / ruby* / python* / node* / php* / perl* を含むもの → unit 名を `APP_SERVICES` に記録（複数台構成なら全て列挙）
   - **DB（ローカル）**: mysql / mysqld / mariadb / postgresql / redis

3. **アプリの設定から webapp パスと環境変数を取得する**

   **Docker Compose の場合** — Step 2 で取得済み。スキップ。

   **systemd の場合**:
   ```bash
   sudo systemctl cat <app-service-name>
   ```
   読み取る:
   - `WorkingDirectory=` → webapp パス
   - `Environment=` → DB 接続情報
   - `EnvironmentFile=` → 参照先ファイルを **必ず `cat`** して接続情報を取得する
   - `ExecStart=` → 言語の確認

4. **アプリのソースコードから DB 接続情報を補完する**

   Step 2〜3 で取得できなかった場合のみ実行:
   ```bash
   grep -rE '(db_host|DB_HOST|database_host|dsn|DataSourceName|mysql\.open|connectDB)' \
     <webapp-path> --include="*.go" --include="*.rb" --include="*.py" \
     --include="*.js" --include="*.ts" --include="*.php" --include="*.pl" \
     -l 2>/dev/null | head -5
   ```
   見つかったファイルを Read して接続情報を抽出する。

   `.env` ファイルも確認する:
   ```bash
   find <webapp-path> -maxdepth 3 \( -name ".env" -o -name "*.env" \) 2>/dev/null
   ```

5. **DB の種別を判定する**

   取得した DB ホスト名を基準に判定する:
   - `*.cluster-*.rds.amazonaws.com` → **aurora**
   - `*.rds.amazonaws.com` → **rds**
   - compose.yml のサービス名（`mysql` / `db` など）→ **docker**
   - `localhost` / `127.0.0.1` / 未設定 かつ systemd に DB サービスあり → **local**
   - 他のプライベート IP → **remote**

6. **静的ファイルのパスを特定する**

   ```bash
   grep -rE '(static|public|assets|StaticFS|ServeFiles|send_file|sendfile)' \
     <webapp-path> --include="*.go" --include="*.rb" --include="*.py" \
     --include="*.js" --include="*.ts" --include="*.php" --include="*.pl" \
     --include="*.psgi" -l 2>/dev/null | head -5
   ```

6b. **ルーティングから alp の URI パターンを抽出する**

   アプリのルート定義ファイルを読んで、パスパラメータを含む URL を列挙する:

   ```bash
   # Go (echo/gin/chi/net/http)
   grep -rE '(GET|POST|PUT|DELETE|PATCH|e\.|r\.|router\.|http\.Handle)\s*\(\s*"/' \
     <webapp-path> --include="*.go" 2>/dev/null | head -30

   # Ruby (Sinatra / Rack)
   grep -rE "^\s*(get|post|put|delete|patch)\s+['\"]/" \
     <webapp-path> --include="*.rb" 2>/dev/null | head -30

   # Python (Flask / Bottle)
   grep -rE "@(app|bottle)\.(route|get|post|put|delete)\s*\(" \
     <webapp-path> --include="*.py" 2>/dev/null | head -30

   # Node.js (Express)
   grep -rE "\.(get|post|put|delete|patch)\s*\(\s*['\"]/" \
     <webapp-path> --include="*.js" --include="*.ts" 2>/dev/null | head -30

   # PHP
   grep -rE "(get|post|put|delete)\s*\(\s*['\"]/" \
     <webapp-path> --include="*.php" 2>/dev/null | head -30
   ```

   抽出したルートから `:id`・`*id`・`<id>` などのパスパラメータを正規表現に変換する:

   | ルート例 | alp パターン |
   |---------|------------|
   | `/posts/:id` | `^/posts/[0-9]+$` |
   | `/image/:id.jpg` | `^/image/[0-9]+\.(jpg\|jpeg\|png\|gif)$` |
   | `/@:username` | `^/@[a-zA-Z0-9_]+$` |
   | `/api/*` | `^/api/.*$` |

   パスパラメータがない静的ルート（`/login`・`/register` など）はパターン不要。

6c. **ベンチマーク実行手順をユーザーから取得する**

   自動検出が難しいため、ユーザーに確認する:
   > ベンチマーカーの実行手順が載っているページ URL かスクリーンショットを共有してもらえますか？

   - URL が提供された場合: `WebFetch` で取得してコマンドを抽出する
   - スクリーンショットが提供された場合: 画像を Read して手順を読み取る
   - 「わからない / 後で」の場合: `BENCH_CMD=''` として空のまま進む

   抽出するもの:
   - ベンチマーカーのパス（例: `~/benchmarker/bin/benchmarker`）
   - 実行オプション（`-t`・`-u` など）
   - ベンチ前後の初期化 URL（`/initialize` など）

6d. **再ビルドコマンドを導出する**

   runtime と言語から以下のルールで決定する（実際の値に置き換えること）:

   **Docker Compose**:
   ```bash
   docker compose -f <compose-file> [-f <compose-dir>/docker-compose.override.yml] -f <compose-dir>/docker-compose.isucon-logs.yml build <app-service> && docker compose -f <compose-file> [-f <compose-dir>/docker-compose.override.yml] -f <compose-dir>/docker-compose.isucon-logs.yml up -d
   ```

   Docker Compose では `setup-docker.sh` が作成する `<compose-dir>/docker-compose.isucon-logs.yml` を標準の compose ファイル列に含める。これにより nginx access log volume と MySQL slow log volume/config が、再起動・recreate 後も維持される。
   既存の `<compose-dir>/docker-compose.override.yml` がある場合は、それも `DOCKER_COMPOSE_FILE_ARGS` に含める。

   `scripts/env.sh` には compose 実行で使う引数を `DOCKER_COMPOSE_FILE_ARGS` として保存し、`REBUILD_CMD` でも同じ値を使う:

   ```bash
   export DOCKER_COMPOSE_FILE='<compose-file>'
   # docker-compose.override.yml がある場合は -f <compose-dir>/docker-compose.override.yml を <compose-file> の後に追加する
   export DOCKER_COMPOSE_FILE_ARGS='-f <compose-file> -f <compose-dir>/docker-compose.isucon-logs.yml'
   export REBUILD_CMD='docker compose $DOCKER_COMPOSE_FILE_ARGS build <app-service> && docker compose $DOCKER_COMPOSE_FILE_ARGS up -d'
   ```

   Docker Compose では候補評価でもフル再起動を標準にする。nginx / MySQL / memcached 等の設定が再起動後も維持されることを毎回検証するため、`up -d --no-deps <app-service>` はデバッグ時の例外扱いにする。

   注意: `docker-compose.isucon-logs.yml` は `bash scripts/setup-docker.sh` が作成する。`setup-docker.sh` 実行前に `REBUILD_CMD` を実行すると override ファイル未作成で失敗するため、Docker 環境では初回ベンチ前に必ず setup 手順を完了する。

   **systemd**:

   | 言語 | コマンド |
   |------|---------|
   | go | `cd <WorkingDirectory> && go build -o <binary> . && sudo systemctl restart <app-service>` |
   | ruby | `sudo systemctl restart <app-service>` |
   | python | `sudo systemctl restart <app-service>` |
   | node | `cd <WorkingDirectory> && npm install && sudo systemctl restart <app-service>` |
   | php | `sudo systemctl restart <app-service>` |
   | perl | `sudo systemctl restart <app-service>` |

7. **`scripts/env.sh`・`scripts/alp.yml`・`reports/survey.md` を書き出す**

   収集した情報を整理し、以下の 2 ファイルを Write ツールで保存する。
   **プレースホルダーはすべて実際の値に置き換えること。**
   `scripts/env.sh` の値は必ず shell-safe にクォートする。非該当の項目はプレースホルダーを残さず `''` にする。
   値にシングルクォートが含まれる場合は `'\''` でエスケープする。

   ### scripts/env.sh（機械可読 — setup スクリプトが source する）

   ```bash
   # Generated by /isucon-survey <YYYY-MM-DD HH:MM>
   # source してから setup スクリプトを実行する

   export ISUCON_RUNTIME='<docker|systemd>'
   export TOOL_REPO='<ISUCON 運用ツールリポジトリの絶対パス>'
   export ISUCON_WEBAPP_DIR='<webapp の絶対パス>'
   export ISUCON_APP_LANG='<go|ruby|python|node|php|perl>'

   # Docker Compose 環境のみ
   export DOCKER_COMPOSE_DIR='<compose.yml があるディレクトリの絶対パス>'
   export DOCKER_COMPOSE_FILE='<compose.yml または docker-compose.yml の絶対パス。非 Docker では空文字>'
   export DOCKER_NGINX_SERVICE='<nginx service name>'
   export DOCKER_MYSQL_SERVICE='<mysql service name>'
   export NGINX_CONF_HOST_DIR='<ホスト側 nginx conf.d パス>'
   export DOCKER_COMPOSE_FILE_ARGS='<Docker Compose 環境では: -f <compose-file> -f <compose-dir>/docker-compose.isucon-logs.yml。docker-compose.override.yml がある場合は compose-file の直後にそれも含める。非 Docker では空文字>'
   export APP_SERVICES='<アプリのサービス名をスペース区切りで列挙。Docker Compose: nginx/mysql/memcached/redis を除いたサービス名（例: app1 app2）。systemd: アプリの unit 名（例: isu-go）。bench-locked.sh の GC トレース取得・docker stats に使う。不明な場合は空文字>'

   # DB 接続情報
   export DB_TYPE='<docker|local|rds|aurora|remote>'
   export DB_HOST='<host>'
   export DB_PORT='<port>'
   export DB_USER='<user>'
   export DB_PASS='<password>'
   export DB_NAME='<dbname>'

   # Docker MySQL 管理用（slow query log 有効化に使う。アプリ用ユーザーとは分ける）
   export DB_ADMIN_USER='<admin user>'
   export DB_ADMIN_PASS='<admin password>'

   # RDS / Aurora のみ
   export RDS_CLUSTER='<aurora-cluster-id。非 Aurora では空文字>'
   export RDS_CLUSTER_PARAM_GROUP='<aurora-cluster-parameter-group。非 Aurora では空文字>'
   export RDS_INSTANCE='<db-instance-id>'
   export RDS_PARAM_GROUP='<parameter-group-name>'

   # ECS / Fargate / ALB / SQS 環境のみ
   export AWS_REGION='<aws-region。非 AWS では空文字>'
   export ECS_CLUSTER='<ecs-cluster。非 ECS では空文字>'
   export ECS_SERVICE='<ecs-service。非 ECS では空文字>'
   export ECS_TASK_DEFINITION='<task-definition-arn。非 ECS では空文字>'
   export ECR_REPOSITORY='<ecr-repository-name。非 ECS では空文字>'
   export FRONTEND_ALB_NAME='<frontend-alb-name。非 ALB では空文字>'
   export BACKEND_ALB_NAME='<backend-alb-name。非 ALB では空文字>'
   export BENCH_QUEUE_NAME='<benchmark-sqs-queue-name。非 SQS では空文字>'

   # ログパス（analyze.sh が使う）
   # Docker: setup-docker.sh 実行後に <DOCKER_COMPOSE_DIR>/logs/ に作られる
   # systemd: デフォルトパス
   export NGINX_ACCESS_LOG='<path>'
   export MYSQL_SLOW_LOG='<path>'   # RDS の場合は空文字: export MYSQL_SLOW_LOG=''

   # クイックリファレンス（手動実行用）
   export BENCH_CMD='<ベンチマーク実行コマンド全体。不明な場合は空文字>'
   export REBUILD_CMD='<アプリ再ビルド＋再起動コマンド。step 6d で導出>'
   ```

   Docker 環境のログパス規則:
   - `NGINX_ACCESS_LOG="$DOCKER_COMPOSE_DIR/logs/nginx/access.log"`
   - `MYSQL_SLOW_LOG="$DOCKER_COMPOSE_DIR/logs/mysql/slow.log"`

   systemd 環境のデフォルト:
   - `NGINX_ACCESS_LOG="/var/log/nginx/access.log"`
   - `MYSQL_SLOW_LOG="/var/log/mysql/slow.log"`

   ### scripts/alp.yml（alp URI 正規化設定）

   step 6b で抽出したパターンを実際の値に置き換えて書き出す。
   パターンが不明な場合は `matching_groups` を空にしておき、初回ベンチ後に追記する。

   **重要**: alp の YAML キーは `matching_groups`（`uri_matching_groups` ではない）。
   書き出し後に必ず以下で動作確認すること:
   ```bash
   curl -s http://localhost/ > /dev/null
   cat "$NGINX_ACCESS_LOG" | alp ltsv --config scripts/alp.yml
   # "Too many URI's" が出たら matching_groups のキー名またはパターンを確認する
   ```

   ```yaml
   sort: sum
   reverse: true
   output: count,method,uri,min,avg,max,sum,p99
   limit: 30

   matching_groups:
     # step 6b で抽出したパスパラメータを含むルートを正規表現に変換して列挙
     - ^/posts/[0-9]+$
     - ^/image/[0-9]+\.(jpg|jpeg|png|gif)$
   ```

   ### reports/survey.md（人間可読）

   ```markdown
   # ISUCON 環境サマリー

   調査日時: <YYYY-MM-DD HH:MM>

   ## サーバー
   - OS: <distro> <version> (<arch>)
   - 実行環境: <Docker Compose | systemd>
   - Web サーバー: <nginx|h2o|apache> <version>
   - アプリ: <言語> (サービス名: <name>, ポート: <port>)
   - webapp パス: <path>
   - 静的ファイルパス: <path>

   ## DB
   - 種別: <Docker MySQL|ローカル MySQL|RDS MySQL|Aurora MySQL 等>
   - ホスト: <host>
   - ポート: <port>
   - ユーザー: <user>
   - パスワード: <password>
   - DB 名: <dbname>

   ## クイックリファレンス

   ```bash
   # ベンチマーク実行
   <BENCH_CMD の値。不明な場合は「TODO: ベンチマーク手順を確認する」>

   # アプリ再ビルド＆再起動
   <REBUILD_CMD の値>
   ```

   ## セットアップ手順

   ```bash
   source scripts/env.sh

   # Docker Compose 環境
   bash scripts/setup-tools.sh
   bash scripts/setup-app.sh
   bash scripts/setup-docker.sh
   # setup-docker.sh が docker-compose.isucon-logs.yml を作成した後は、
   # REBUILD_CMD / bench-locked.sh が override 込みの compose ファイル列を使う。

   # systemd + ローカル MySQL 環境
   bash scripts/setup-tools.sh
   bash scripts/setup-nginx.sh
   bash scripts/setup-mysql.sh
   bash scripts/setup-app.sh

   # RDS / Aurora 環境
   bash scripts/setup-rds.sh
   # パラメータグループ変更が必要な場合:
   # bash scripts/setup-rds.sh --aws-cli
   ```

   `ISUCON_APP_LANG` が `go` の場合のみ、以下を末尾に追記する:

   ```markdown
   ## Go アプリ向け追加手順

   ### ホストに Go をインストールする（pprof に必要）

   ```bash
   go version 2>/dev/null || sudo snap install go --classic
   ```

   ### pprof でボトルネック関数を特定する

   pprof はベンチ実行前にセットアップし、ベンチ実行中にプロファイルを取得します:

   ```
   /isucon-pprof
   ```
   ```
   ```
