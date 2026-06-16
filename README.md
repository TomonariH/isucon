# isucon

ISUCON 競技向けスクリプト・スキル集。  
`~/private-isu` を試験環境として動作確認している。

## ディレクトリ構成

```
scripts/
  alp.yml           # alp URI 正規化設定（/isucon-survey または手動で更新）
  env.sh            # /isucon-survey が生成する環境変数（git 管理外）
  install-claude.sh # Claude Code CLI をインストールする
  setup-tools.sh    # alp / pt-query-digest インストール（分析実行サーバー）
  setup-nginx.sh    # nginx LTSV アクセスログ設定（nginx サーバー）
  setup-mysql.sh    # MySQL スロークエリログ設定（DB サーバー、ローカル MySQL 用）
  setup-app.sh      # git init / reports ディレクトリ作成（アプリサーバー）
  setup-docker.sh   # Docker Compose 環境向けセットアップ（ログ expose・nginx LTSV・MySQL slow log）
  setup-rds.sh      # RDS 環境向けセットアップ（MySQL が AWS RDS / Aurora の場合）
  setup.sh          # 1台構成向け初動セットアップ wrapper
  unsetup.sh        # setup.sh / setup-* の一部変更を元に戻す補助
  lib.sh            # 共通環境検出ライブラリ（OS / arch / MySQL サービス名など）
  lib-docker.sh     # Docker Compose 環境向け helper（compose file / service 検出）
  analyze.sh        # ベンチ後に毎回実行する計測・レポート生成（H2O 自動検出）
  analyze-rds.sh    # RDS 環境向け分析（mysql.slow_log テーブル対応）
  bench-locked.sh   # rebuild / benchmark の排他実行とログ window 管理
  improvement-log.sh # 改善候補・評価・cleanup 判断を reports に記録
  score-log.sh      # スコアを reports/scores.md に記録
  ecs/
    survey.sh       # ECS service/task definition/log 調査 report を生成
    deploy.sh       # Docker build -> ECR push -> ECS force deployment
    wait-stable.sh  # ECS service stable と healthcheck を待つ
    bench-locked.sh # ECS deploy / benchmark の排他実行
    bench-sqs.sh    # SQS queue に benchmark request を送信
    resolve-alb-url.sh # ALB name/ARN/DNS から target URL を解決
    logs.sh         # CloudWatch Logs から nginx/app stdout を取得
    analyze.sh      # ECS nginx stdout + RDS slow log の分析 report を生成
    pprof.sh        # ECS pprof 取得補助
templates/
  nginx-00-ltsv.conf        # nginx LTSV アクセスログ設定
  mysql-slow.cnf            # MySQL スロークエリログ設定
  nginx-staticfile.conf     # 静的ファイル直接配信設定（画像 DB 脱却後に使用）
  nginx-upstream.conf       # 複数台構成のロードバランシング設定
  nginx-upstream-keepalive.conf # nginx -> app 接続再利用設定
  nginx-final-no-access-log.conf # 最終ベンチ向け access_log off 設定
  mysql-remote.cnf          # MySQL 外部接続許可設定（DB サーバー分離時）
  mysql-buffer-pool.cnf     # innodb_buffer_pool_size 段階評価用
  mysql-durability-relaxed.cnf # fsync 緩和設定（競技向け）
  mysql-connection-cache.cnf # 接続・一時テーブル系設定
  memcached-competition.command # memcached 競技向け command 例
  redis-cache.conf          # Redis キャッシュ用途向け設定
  rds-parameter-group.md    # RDS パラメータグループ手動設定手順
  go-pprof.snippet          # Go pprof エンドポイント追加コード
  h2o-ltsv.conf             # H2O web server LTSV ログ設定
references/
  goal-common.md            # /goal 共通ルール（env, bench lock, fail診断, git安全）
  agent-rules.md            # エージェント別ルール（Claude Code / Codex / 共通）
  orchestration-rules.md    # 複数エージェント・worktree・merge採否ルール
  phase-boundaries.md       # Phase の責務境界
  goals/                    # Phase 別 /goal 手順
  ecs/                      # ECS + RDS 専用 Phase 手順
.codex/skills/
  isucon-*                  # Codex 用 skill wrapper（.claude/commands を正本として参照）
.claude/commands/
  isucon-survey.md          # /isucon-survey スキル（競技開幕の環境調査）
  isucon-analyze.md         # /isucon-analyze スキル
  isucon-fix.md             # /isucon-fix スキル（具体的な改善候補の実装）
  isucon-multiserver.md     # /isucon-multiserver スキル（複数台構成）
  isucon-pprof.md           # /isucon-pprof スキル（Go pprof）
  isucon-review-app.md      # /isucon-review-app スキル（アプリ性能レビュー）
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

このフェーズでは、複数エージェントで改善候補を並列実装し、改善したものだけを統合する。詳細手順は reference に分割しているため、Claude Code には次の短い prompt を投げる。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 2 の改善ループを実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/orchestration-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase2-improvement-loop.md
```

---

### Phase 3 — pprof サイクル

改善ループのスコアが伸び悩んだとき、alp・スロークエリでは見えないアプリ内部のCPUホットスポットを特定して修正する。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 3 の pprof サイクルを実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/orchestration-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase3-pprof-cycle.md
```

---

### Phase 4 — ミドルウェア秘伝のタレ評価

アプリ改善と pprof 分析が一巡したら、MySQL / nginx / memcached / Redis の定番設定を単体差分で評価する。テンプレートは `templates/` に分割してあるので、効いたものだけ残す。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 4 のミドルウェア秘伝のタレ評価を実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase4-infra-tuning.md
```

---

### Phase 5 — サーバー分割

1台構成でアプリ改善・pprof・ミドルウェア調整が一巡し、CPU / メモリ / DB のどれかが明確に上限に近い場合だけ、複数台構成を検討する。サーバー分割は長期ループではなく、まず `/isucon-multiserver` スキルで「最新レポートに基づく分割案・手順・実施可能なローカル修正」を出す。

```text
/isucon-multiserver
```

このスキルが行うこと:
- `scripts/env.sh`、最新 `reports/*.md`、`reports/scores.md`、`reports/survey.md` を読み、最新ボトルネックから最適な分割案を出す
- 現在のISUCONレギュレーション、利用可能サーバー、入口URL、Docker Compose / systemd / RDS などの実行環境を確認する
- 手順提示に必要なIP、SSH可否、sudo権限、DB移行、画像/セッション共有などが不明なら、調査またはユーザーへの確認を行う
- nginx upstream、MySQL外部接続、app/cache/静的ファイル共有、分散環境でのログ収集、ロールバック手順を提示する
- スキルが実行されているサーバー内で安全に実施できる変更があれば、新規ブランチを作成して適用・検証・commit する

実際に複数案をベンチで反復評価する場合だけ、`/isucon-multiserver` の出力を正本として別途 `/goal` を使う。

---

### Phase 6 — 最終提出用のサーバー整備

提出直前は、分析用の重いログ・pprof・一時ファイル・未採用設定を外し、再起動後も同じ構成で起動することを確認する。ここでは新しい最適化を増やさず、採用済み変更の固定と事故防止に集中する。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Phase 6 の最終提出用サーバー整備を実行してください。

- $TOOL_REPO/references/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/goals/phase6-final-prep.md
```

---

## Fargate/ALB/Aurora 環境の戦い方

Fargate + ALB + Aurora MySQL 環境では、既存の `systemd` / Docker Compose 向け Phase 手順に条件分岐を足さず、`references/ecs/` を正本にする。作業場所は ECS task 内ではなく、AWS CLI と Docker が使えるローカル端末または作業用 EC2 を基本にする。

ECS task は入れ替わる前提なので、running container 内で直接設定を書き換えない。変更は app repo、Docker image、ECR tag、ECS service/task definition、RDS parameter group に反映する。

frontend ALB と backend ALB は分けて扱う。frontend task から backend ALB へアクセスし、benchmark は NAT Gateway 経由で backend ALB を叩く想定なら、`BENCH_CMD='bash scripts/ecs/bench-sqs.sh'` とし、SQS queue に backend ALB URL を送る。

作業端末には AWS CLI、Docker、python3、alp、RDS 解析に必要な mysql client / pt-query-digest を用意する。alp や pt-query-digest は通常 `scripts/setup-tools.sh` で入れる。

### 対応モデル

| 構成 | 方針 | 主な script |
|---|---|---|
| ECS Fargate / ECS on EC2 | task 内を直接変更せず、image build / ECR push / ECS service update で反映する | `scripts/ecs/deploy.sh`, `scripts/ecs/bench-locked.sh` |
| ECS + backend ALB + SQS benchmark | backend ALB URL を解決し、SQS に benchmark request を送る | `scripts/ecs/resolve-alb-url.sh`, `scripts/ecs/bench-sqs.sh` |
| ECS nginx container | CloudWatch Logs の stdout を alp 入力にする。LTSV でなければ image 側 nginx config を直す | `scripts/ecs/logs.sh`, `scripts/ecs/analyze.sh` |
| EC2 + nginx process | ローカル access log を読む従来手順を使う | `scripts/setup-nginx.sh`, `scripts/analyze.sh` |
| Docker Compose nginx container | host に expose した access log を読む従来手順を使う | `scripts/setup-docker.sh`, `scripts/analyze.sh` |
| Aurora MySQL | cluster parameter group と instance parameter group を両方確認し、`mysql.slow_log` を読む | `scripts/analyze-rds.sh`, `templates/rds-parameter-group.md` |
| RDS MySQL | DB parameter group を確認し、`mysql.slow_log` を読む | `scripts/setup-rds.sh`, `scripts/analyze-rds.sh` |
| self-managed MySQL on EC2 | MySQL conf を直接変更し、slow log file を読む | `scripts/setup-mysql.sh`, `scripts/analyze.sh` |

### 初動

```bash
source scripts/env.sh 2>/dev/null || true
ECS_CLUSTER=<cluster> ECS_SERVICE=<service> bash scripts/ecs/survey.sh
```

`reports/ecs-survey.md` を読み、`scripts/env.sh` に `ISUCON_RUNTIME=ecs`、ECS service、CloudWatch Logs、ECR、RDS、benchmark の値を埋める。

SQS 経由で benchmark を起動する環境では、最低限次を埋める。

```bash
export DB_TYPE='aurora'
export ECR_REPOSITORY='<repository-name>'
export RDS_CLUSTER='<aurora-cluster-id>'
export RDS_CLUSTER_PARAM_GROUP='<aurora-cluster-parameter-group>'
export RDS_INSTANCE='<db-instance-id>'
export RDS_PARAM_GROUP='<db-instance-parameter-group>'
export BACKEND_ALB_NAME='<backend-alb-name>'
export BACKEND_ALB_PROTOCOL='http'
export BENCH_QUEUE_NAME='<benchmark-queue-name>'
export BENCH_CMD='bash scripts/ecs/bench-sqs.sh'
export BENCH_MESSAGE_BODY='{"target_url":"{{BENCH_TARGET_URL}}"}'
```

SQS message body は大会ごとに違うため、配布資料に合わせて `BENCH_MESSAGE_BODY` または `BENCH_MESSAGE_FILE` を差し替える。URL を JSON 文字列として埋め込む場合は `{{BENCH_TARGET_URL_JSON}}` のような `_JSON` suffix の placeholder を使う。

### `/goal` の Phase 指定

初動後に改善ループへ入る場合は Phase 2 を指定する。次の `/goal` 例は `references/ecs/phase2-improvement-loop.md` を読むため、Phase 2 用。

```text
/goal
まずツールリポジトリで `source scripts/env.sh` してから、以下を順に読み、Fargate/ALB/Aurora 向け Phase を実行してください。

- $TOOL_REPO/references/ecs/goal-common.md
- $TOOL_REPO/references/agent-rules.md
- $TOOL_REPO/references/orchestration-rules.md
- $TOOL_REPO/references/phase-boundaries.md
- $TOOL_REPO/references/ecs/phase2-improvement-loop.md
```

目的が違う場合は最後の Phase 手順だけ差し替える。

```text
# 初動調査
- $TOOL_REPO/references/ecs/phase1-survey.md

# pprof
- $TOOL_REPO/references/ecs/phase3-pprof-cycle.md

# infra tuning
- $TOOL_REPO/references/ecs/phase4-infra-tuning.md

# scale
- $TOOL_REPO/references/ecs/phase5-scale.md

# final prep
- $TOOL_REPO/references/ecs/phase6-final-prep.md
```

### Phase 対応

- Phase 1: `references/ecs/phase1-survey.md`
- Phase 2: `references/ecs/phase2-improvement-loop.md`
- Phase 3: `references/ecs/phase3-pprof-cycle.md`
- Phase 4: `references/ecs/phase4-infra-tuning.md`
- Phase 5: `references/ecs/phase5-scale.md`
- Phase 6: `references/ecs/phase6-final-prep.md`

### 基本ループ

```bash
# deploy なし baseline
bash scripts/ecs/bench-locked.sh --analyze

# app 修正後: build/push/deploy/wait/bench/analyze
bash scripts/ecs/bench-locked.sh --rebuild --analyze

# SQS benchmark request だけ送る
bash scripts/ecs/bench-sqs.sh

# benchmark 後に手動分析だけ行う
BENCH_START_EPOCH=<epoch> bash scripts/ecs/analyze.sh
```

ECS では access log はローカルファイルではなく CloudWatch Logs から取得する。RDS slow query は `mysql.slow_log` または RDS log file から読む。pprof は ECS Exec、task IP、または一時 security group のどれで取るかを Phase 3 で決める。

---

## スクリプトリファレンス

### 使い方の前提

多くの script は `/isucon-survey` が生成する `scripts/env.sh` を読む。競技環境ではまず次を実行してから使う。

```bash
source scripts/env.sh
```

`scripts/lib.sh` と `scripts/lib-docker.sh` は他の script から `source` される helper で、直接実行しない。`scripts/alp.yml` は alp の設定ファイルで、shell script ではない。

### `scripts/install-claude.sh`

Claude Code CLI をインストールする。競技前の端末準備で使う。すでに `claude` が入っている場合は何もしない。

```bash
bash scripts/install-claude.sh
```

### `scripts/setup-tools.sh`

分析実行サーバーに `alp`、`pt-query-digest`、`dstat` を入れる。nginx / DB / app が別サーバーの場合でも、ログを解析するサーバーでは実行する。

```bash
bash scripts/setup-tools.sh
```

### `scripts/setup-nginx.sh`

systemd / ローカル nginx 環境で、nginx access log を LTSV 形式にする。nginx サーバーで実行する。Docker Compose 環境では通常 `setup-docker.sh` を使う。

```bash
bash scripts/setup-nginx.sh
```

### `scripts/setup-mysql.sh`

systemd / ローカル MySQL または MariaDB 環境で slow query log を有効化する。DB サーバーで実行する。RDS / Aurora では使わず、`setup-rds.sh` を使う。

```bash
bash scripts/setup-mysql.sh
```

### `scripts/setup-app.sh`

アプリサーバー初期化用。`reports/` を作り、webapp が git 管理されていなければ初期 commit を作る。systemd + Go では `APP_SERVICES` に対して GC trace 用 drop-in も設定する。

```bash
bash scripts/setup-app.sh
```

### `scripts/setup-docker.sh`

Docker Compose 環境向け初期セットアップ。nginx / MySQL のログをホストへ出す override を作り、nginx LTSV と MySQL slow query log を有効化する。`DOCKER_COMPOSE_DIR`、`DOCKER_COMPOSE_FILE_ARGS`、`DOCKER_NGINX_SERVICE`、`DOCKER_MYSQL_SERVICE` は `scripts/env.sh` に記録しておく。

```bash
bash scripts/setup-docker.sh
```

### `scripts/setup-rds.sh`

DB が AWS RDS / Aurora の場合に使う。共通ツールと nginx/app setup を呼び、RDS slow query log の設定状態を確認する。AWS CLI でパラメータグループも変更する場合は `--aws-cli` を付ける。

```bash
bash scripts/setup-rds.sh
bash scripts/setup-rds.sh --aws-cli
```

### `scripts/setup.sh`

1台構成向けの wrapper。`setup-tools.sh`、`setup-nginx.sh`、`setup-mysql.sh`、`setup-app.sh` を順に実行する。Docker Compose、RDS、複数台構成では個別 script を使う。

```bash
bash scripts/setup.sh
```

### `scripts/unsetup.sh`

このリポジトリの setup script が入れた分析用設定の一部を戻す。alp / percona-toolkit / nginx LTSV / MySQL slow log / systemd GC trace drop-in を、生成物 marker を見ながら削除する。競技中に戻す場合は影響範囲を確認してから使う。

```bash
bash scripts/unsetup.sh
```

### `scripts/bench-locked.sh`

rebuild / restart / benchmark を同じ排他ロックに入れて実行する。ログを benchmark window ごとに切り、dstat / docker stats / Go GC trace も取得する。競技中の評価は原則これ経由で行う。

```bash
bash scripts/bench-locked.sh
bash scripts/bench-locked.sh --rebuild
bash scripts/bench-locked.sh --no-reset-logs

HEALTHCHECK_CMD='curl -fsS http://localhost/ >/dev/null' \
bash scripts/bench-locked.sh --rebuild
```

### `scripts/analyze.sh`

ベンチ結果を解析して、access log、slow query log、dstat、docker stats、Go GC trace を含むレポートを `reports/<timestamp>.md` に生成する。ローカル MySQL / Docker MySQL / systemd 環境向け。

```bash
bash scripts/analyze.sh
```

### `scripts/analyze-rds.sh`

RDS / Aurora 向け分析。`mysql.slow_log` テーブルを読み、`pt-query-digest` に流してレポートを生成する。`log_output=TABLE` が未設定の場合は AWS CLI によるログファイル取得を試す。

```bash
bash scripts/analyze-rds.sh
SLOW_LOG_MINUTES=10 bash scripts/analyze-rds.sh
ROTATE_RDS_SLOW_LOG=1 bash scripts/analyze-rds.sh
```

### `scripts/score-log.sh`

ベンチ結果のスコアを履歴として追記する shell。対象 commit とメモも残すので、どの修正で改善したかを追える。

```bash
bash scripts/score-log.sh <score> [メモ]

# 例
bash scripts/score-log.sh 3200 "N+1解消"
bash scripts/score-log.sh 5800 "画像をファイルシステムに移動"
```

### `scripts/improvement-log.sh`

改善候補、ベンチ評価、worktree cleanup 判断を `reports/improvement-loop.md` に記録する。複数エージェントや複数 branch で改善候補を比較するときに使う。

```bash
bash scripts/improvement-log.sh candidate C1 high low feature/cache-user "cache user lookup"
bash scripts/improvement-log.sh eval C1 feature/cache-user 12345 true merged "improved baseline"
bash scripts/improvement-log.sh cleanup feature/cache-user /tmp/wt kept "left for audit"
```

### `scripts/ecs/survey.sh`

ECS service、task definition、running task、container log 設定を AWS CLI から調査し、`reports/ecs-survey.md` を生成する。`scripts/env.sh` の ECS 用候補値も report に出す。

```bash
ECS_CLUSTER=<cluster> ECS_SERVICE=<service> bash scripts/ecs/survey.sh
```

### `scripts/ecs/deploy.sh`

Docker image を build して ECR に push し、ECS service を `--force-new-deployment` で更新して stable まで待つ。既存 task definition が同じ image tag を参照している前提で、task definition revision は新規作成しない。`ECR_IMAGE` が空なら `aws sts get-caller-identity` と `ECR_REPOSITORY` から image URI を組み立てる。`REBUILD_CMD='bash scripts/ecs/deploy.sh'` として使う。

```bash
bash scripts/ecs/deploy.sh
SKIP_DOCKER_BUILD=1 bash scripts/ecs/deploy.sh
```

### `scripts/ecs/wait-stable.sh`

ECS service の `services-stable` を待ち、`HEALTHCHECK_CMD` または `BENCH_TARGET_URL` があれば endpoint の疎通も確認する。

```bash
bash scripts/ecs/wait-stable.sh
```

### `scripts/ecs/bench-locked.sh`

ECS deploy / benchmark を排他実行する。`--rebuild` で `REBUILD_CMD` を実行し、`--analyze` で benchmark window の CloudWatch Logs と RDS slow log を解析する。

```bash
bash scripts/ecs/bench-locked.sh --analyze
bash scripts/ecs/bench-locked.sh --rebuild --analyze
```

### `scripts/ecs/bench-sqs.sh`

SQS queue に benchmark request を送る。`BENCH_QUEUE_URL` がなければ `BENCH_QUEUE_NAME` から queue URL を取得し、`BENCH_TARGET_URL` がなければ backend ALB 設定から URL を解決する。message body は `BENCH_MESSAGE_BODY` または `BENCH_MESSAGE_FILE` で大会形式に合わせる。

```bash
BENCH_QUEUE_NAME=<queue> BACKEND_ALB_NAME=<backend-alb> bash scripts/ecs/bench-sqs.sh
BENCH_QUEUE_NAME=<queue> BACKEND_ALB_NAME=<backend-alb> bash scripts/ecs/bench-sqs.sh --dry-run
BENCH_MESSAGE_BODY='{"target_url":"{{BENCH_TARGET_URL}}"}' bash scripts/ecs/bench-sqs.sh
BENCH_MESSAGE_BODY='{"backend":{{BACKEND_ALB_URL_JSON}},"frontend":{{FRONTEND_ALB_URL_JSON}}}' bash scripts/ecs/bench-sqs.sh --dry-run
```

置換できる placeholder は `{{BENCH_TARGET_URL}}`、`{{BACKEND_ALB_URL}}`、`{{FRONTEND_ALB_URL}}`、`{{BENCH_QUEUE_URL}}`。JSON 文字列として埋める場合は `{{BENCH_TARGET_URL_JSON}}`、`{{BACKEND_ALB_URL_JSON}}`、`{{FRONTEND_ALB_URL_JSON}}`、`{{BENCH_QUEUE_URL_JSON}}` を使う。

### `scripts/ecs/resolve-alb-url.sh`

backend / frontend ALB の name、ARN、DNS name から target URL を出力する。SQS benchmark の送信前確認や `BENCH_TARGET_URL` の手動設定に使う。

```bash
BACKEND_ALB_NAME=<backend-alb> bash scripts/ecs/resolve-alb-url.sh --kind backend
FRONTEND_ALB_NAME=<frontend-alb> bash scripts/ecs/resolve-alb-url.sh --kind frontend
```

### `scripts/ecs/logs.sh`

CloudWatch Logs から nginx または app container の stdout を取得する。nginx access log が stdout に出ている ECS 環境で alp 解析の入力を作る。

```bash
bash scripts/ecs/logs.sh --kind nginx --since-epoch <epoch> --out reports/.runtime/ecs-nginx.log
bash scripts/ecs/logs.sh --kind app --since-epoch <epoch> --out reports/.runtime/ecs-app.log
```

### `scripts/ecs/analyze.sh`

ECS nginx stdout を CloudWatch Logs から取得し、alp で解析する。DB が RDS / Aurora の場合は `analyze-rds.sh` を使って slow query も report に含める。

```bash
bash scripts/ecs/analyze.sh
BENCH_START_EPOCH=<epoch> bash scripts/ecs/analyze.sh
```

### `scripts/ecs/pprof.sh`

ECS 環境で pprof を取る補助。`PPROF_URL` がある場合は profile を取得して `go tool pprof` の top 出力を保存する。URL がない場合は ECS Exec で container 内から取得する手順を表示する。

```bash
PPROF_URL='http://<reachable-host>:6060/debug/pprof/profile' bash scripts/ecs/pprof.sh
bash scripts/ecs/pprof.sh
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

---

## テンプレートリファレンス

### `templates/nginx-00-ltsv.conf`

nginx の access log を LTSV 形式で出力する設定。systemd nginx では `setup-nginx.sh` が使う。server / location に個別 `access_log` がある場合は、そちらも LTSV に合わせる。

```bash
sudo cp templates/nginx-00-ltsv.conf /etc/nginx/conf.d/ltsv.conf
sudo nginx -t && sudo systemctl reload nginx
```

### `templates/mysql-slow.cnf`

MySQL の slow query log を有効化する設定。`setup-mysql.sh` と `setup-docker.sh` が使う。ローカル MySQL / Docker MySQL 用で、RDS / Aurora は `rds-parameter-group.md` を使う。

```bash
# Ubuntu / Debian
sudo cp templates/mysql-slow.cnf /etc/mysql/conf.d/slow-query.cnf
sudo systemctl restart mysql

# Amazon Linux 2 / 2023
sudo cp templates/mysql-slow.cnf /etc/my.cnf.d/slow-query.cnf
sudo systemctl restart mysqld
```

### `templates/nginx-staticfile.conf`

静的ファイルを nginx から直接配信する設定例。画像や CSS/JS をアプリや DB から切り離した後に使う。完全な server block 例なので、既存設定を丸ごと置き換えず、必要な `location` だけ差分適用する。

### `templates/nginx-upstream.conf`

アプリサーバーを複数台に分けるときの nginx upstream 例。`least_conn`、複数 app server、keepalive を含む。IP アドレス、port、既存 location は競技環境に合わせて差分適用する。

### `templates/nginx-upstream-keepalive.conf`

nginx から app への upstream 接続を keepalive する設定例。1台構成でも nginx -> app の接続 churn が重いときに評価する。既存 server block へ upstream と proxy header だけ差分適用する。

### `templates/nginx-final-no-access-log.conf`

最終ベンチ直前に nginx access log を止めるための設定。alp 解析ができなくなるので、分析が終わって採用構成が固まった Phase 6 でだけ使う。

### `templates/h2o-ltsv.conf`

H2O web server の access log を LTSV 形式にする設定例。nginx ではなく H2O が入口の環境で使う。既存 `/etc/h2o/h2o.conf` の top-level `access-log` だけを追加または置換する。

### `templates/mysql-buffer-pool.cnf`

`innodb_buffer_pool_size` を段階評価するための MySQL 設定。`<BUFFER_POOL_SIZE>` を `256M`、`512M` など実測する値に置換して、別ファイルとして配置する。

### `templates/mysql-connection-cache.cnf`

MySQL の接続 churn、table open cache、一時テーブル周りを保守的に調整する設定。小さい Docker container でも破綻しにくい値にしてあるが、必ず単体差分で評価する。

### `templates/mysql-durability-relaxed.cnf`

`innodb_flush_log_at_trx_commit=2` と `sync_binlog=0` で fsync 圧を下げる競技向け設定。クラッシュ耐久性を緩めるため、initialize で復元できるか、競技ルール上問題ないかを確認してから評価する。

### `templates/mysql-remote.cnf`

DB サーバーを app サーバーから接続できるように `bind-address=0.0.0.0` と接続数を設定する例。複数台構成で DB を分離するときに、DB サーバー側へ差分適用する。

### `templates/rds-parameter-group.md`

RDS / Aurora で slow query log を取るためのパラメータグループ手順。`slow_query_log=1`、`long_query_time=0`、`log_output=TABLE` を設定し、`analyze-rds.sh` で読む。Aurora は DB cluster parameter group と DB instance parameter group の両方を確認する。

### `templates/go-pprof.snippet`

Go アプリに `net/http/pprof` endpoint を追加するコード片。`/isucon-pprof` または Phase 3 の pprof サイクルで使う。Docker Compose 環境では別途 port expose が必要。

### `templates/memcached-competition.command`

memcached を cache / session store として使っている場合の command 例。`-m 256 -c 4096 -t 2` を systemd `ExecStart` や Docker Compose `command:` に差分適用して評価する。正データを保持している場合は使わない。

### `templates/redis-cache.conf`

Redis を cache または再構築可能な session store として使う場合の競技向け設定。永続化を止め、`allkeys-lru` を使う。Redis が正データの場合は使わない。
