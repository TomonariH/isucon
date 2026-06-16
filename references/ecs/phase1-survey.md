# ECS/RDS Phase 1 Survey Verification

`/isucon-survey` が生成した AWS / ECS / ALB / Aurora 調査結果を確認し、`scripts/env.sh` の不足値を補完する。
この reference は初動調査を最初からやり直す手順ではない。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`
- `reports/survey.md`
- `reports/aws-survey.md`
- `reports/ecs-survey.md`
- `scripts/env.sh`

## Preconditions

1. `/isucon-survey` を実行済みであること。
2. AWS managed 構成の場合、`/isucon-survey` が内部で次を実行済みであること。

   ```bash
   AWS_REGION=<region> bash scripts/ecs/discover.sh
   ECS_CLUSTER=<cluster> ECS_SERVICE=<backend-service> BENCH_QUEUE_NAME=<queue> bash scripts/ecs/survey.sh
   ```

3. 上記 report がない、または backend service / ALB / SQS / Aurora が未確定の場合だけ、該当 script を再実行する。

## Verify `scripts/env.sh`

最低限、次が実値で埋まっていることを確認する。未確定の値は推測せず、`reports/aws-survey.md`、`reports/ecs-survey.md`、配布資料から補完する。

```bash
export ISUCON_RUNTIME='ecs'
export AWS_REGION='<region>'
export ECS_CLUSTER='<cluster>'
export ECS_SERVICE='<backend service>'
export ECS_APP_CONTAINER='<app container>'
export ECS_NGINX_CONTAINER='<nginx container>'
export ECS_LOG_GROUP='<cloudwatch log group>'
export ECS_LOG_STREAM_PREFIX='<stream prefix>'
export ECR_REPOSITORY='<repository-name>'
export IMAGE_TAG='isucon-latest'
export APP_BUILD_DIR='<app build context>'
export DB_TYPE='aurora'
export DB_HOST='<aurora writer endpoint>'
export DB_PORT='3306'
export DB_USER='<user>'
export DB_PASS='<password>'
export DB_NAME='<dbname>'
export RDS_CLUSTER='<aurora cluster id>'
export RDS_CLUSTER_PARAM_GROUP='<aurora cluster parameter group>'
export RDS_INSTANCE='<db instance id>'
export RDS_PARAM_GROUP='<db instance parameter group>'
export FRONTEND_ALB_NAME='<frontend alb name>'
export BACKEND_ALB_NAME='<backend alb name>'
export BACKEND_ALB_PROTOCOL='http'
export BACKEND_ALB_PATH='/'
export BENCH_QUEUE_NAME='<benchmark queue name>'
export BENCH_CMD='bash scripts/ecs/bench-sqs.sh'
export REBUILD_CMD='bash scripts/ecs/deploy.sh'
export BENCH_DURATION_SEC='60'
export BENCH_RESULT_MARGIN_SEC='15'
```

`BENCH_MESSAGE_BODY` / `BENCH_MESSAGE_FILE` は大会固有。`/isucon-survey` で自動確定できなかった場合は、配布資料、マニュアル URL、スクリーンショットを確認して設定する。未確認なら空のまま `reports/survey.md` に TODO を残す。

## Verify AWS Targets

1. backend service が benchmark 対象であることを確認する。

   ```bash
   aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
   ```

2. frontend ALB / backend ALB が取り違えられていないことを確認する。

   ```bash
   bash scripts/ecs/resolve-alb-url.sh --kind backend
   [ -n "${FRONTEND_ALB_NAME:-}${FRONTEND_ALB_DNS_NAME:-}${FRONTEND_ALB_URL:-}" ] && \
     bash scripts/ecs/resolve-alb-url.sh --kind frontend
   ```

3. backend target group に healthy target があることを確認する。

   ```bash
   aws elbv2 describe-target-health --target-group-arn <backend-target-group-arn>
   ```

4. benchmark SQS queue が確定していることを確認する。

   ```bash
   aws sqs get-queue-url --queue-name "$BENCH_QUEUE_NAME"
   ```

## Verify IAM Reach

`scripts/ecs/analyze.sh` は多数の AWS API に依存し、競技 IAM role が一部を拒否しても各セクションが黙って `n/a` に落ちる（scripts が `|| echo '{}'` でエラーを握りつぶす）。「拒否」と「データなし」を区別するため、計測チェーンに入る前に到達性を確認する。

```bash
bash scripts/ecs/iam-check.sh
```

- DENIED の action と、選んだ `SKIP_*`（例: `SKIP_CW_METRICS=1` / `SKIP_PI=1`）を `reports/survey.md` に記録する。
- DENIED の metrics / PI / logs は analyze の該当セクションが `n/a` になる理由＝「データなし」ではない。混同しない。

## Verify Benchmark Request

SQS benchmark request は必ず dry-run で message body を確認してから実送信する。

```bash
bash scripts/ecs/bench-sqs.sh --dry-run
```

確認すること:

- target URL が backend ALB を向いている
- message body が配布資料の形式に合っている
- JSON 文字列埋め込みが必要な箇所に `_JSON` placeholder を使っている
- queue URL が benchmark queue を向いている

## Verify Benchmark Completion & Result

SQS benchmark は worker 側で非同期に実行され、`send-message` は MessageId を返すだけで完了や score を返さない。`bench-sqs.sh` は送信後 `BENCH_DURATION_SEC`(+margin) だけブロックしてから返り、`bench-locked.sh` の analyze 窓が空にならないようにしている。配布資料から次を確定し、`reports/survey.md` に記録する。

1. benchmark の実行時間を確認し、`BENCH_DURATION_SEC`（既定 60）に設定する。CloudWatch Logs / メトリクスの取り込み遅延に備えた余裕は `BENCH_RESULT_MARGIN_SEC`（既定 15）。総待ち時間 = duration + margin。

   ```bash
   export BENCH_DURATION_SEC='60'
   export BENCH_RESULT_MARGIN_SEC='15'
   ```

2. score / pass-fail の返却経路を確認する。候補:
   - 結果用 SQS キュー(`*-result` / `*-response` 等)
   - ベンチ worker の CloudWatch Logs
   - ポータル / HTTP エンドポイント

   `scripts/ecs/discover.sh` の `## SQS Queues` と `## CloudWatch Log Groups` 出力から候補を探す。

3. 返却経路が確定したら `bench-sqs.sh` の `BENCH_RESULT_MODE` に対応する mode を設定し、その mode の fetch logic を実装する。現状は 3 mode の **stub 枠**があり、設定すると必要な env を表示して duration-wait にフォールバックする（＝ここが Phase 1 後の接続点で、「作り直し」ではなく「fetch を埋める」作業になる）。
   - `BENCH_RESULT_MODE=sqs`: 結果用 SQS キューをポーリング。`BENCH_RESULT_QUEUE_URL` または `BENCH_RESULT_QUEUE_NAME`、score 抽出に `BENCH_SCORE_JQ`、送信 MessageId / correlation id で突合。
   - `BENCH_RESULT_MODE=log`: ベンチ worker の CloudWatch Logs を読む。`BENCH_RESULT_LOG_GROUP`、`BENCH_PASS_REGEX` / `BENCH_SCORE_REGEX` で pass-fail と score を抽出。
   - `BENCH_RESULT_MODE=http`: ポータル / 結果 API をポーリング。`BENCH_RESULT_URL`、`BENCH_SCORE_JQ` で score を抽出。
   - 実装したら score を `scripts/score-log.sh` に自動連携する。未確定の間は duration-wait で P0-A（空 analyze 窓）を回避し、score は `scripts/score-log.sh <score> "<note>"` で手動記録する。

## Verify Aurora Slow Query

Aurora は DB cluster parameter group と DB instance parameter group の両方を確認する。

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name "$RDS_CLUSTER_PARAM_GROUP" \
  --query 'Parameters[?ParameterName==`slow_query_log` || ParameterName==`long_query_time` || ParameterName==`log_output`].[ParameterName,ParameterValue,ApplyType,ApplyMethod]' \
  --output table

aws rds describe-db-parameters \
  --db-parameter-group-name "$RDS_PARAM_GROUP" \
  --query 'Parameters[?ParameterName==`slow_query_log` || ParameterName==`long_query_time` || ParameterName==`log_output`].[ParameterName,ParameterValue,ApplyType,ApplyMethod]' \
  --output table
```

変更が必要な場合は `templates/rds-parameter-group.md` を読み、競技ルールと再起動影響を確認してから parameter group を変更する。

## Verify Measurement Chain (Phase2 入場ゲート)

`scripts/ecs/analyze.sh` は `alp ltsv`（nginx の LTSV 出力前提）と slow query / Performance Insights を読む。これらが揃う前に最初の analyze を回すと、空・無意味な report になる。Phase2 の baseline analyze に入る**前に**、次の計測チェーン疎通を Phase1 で済ませる。

1. nginx container stdout が LTSV であること。

   ```bash
   bash scripts/ecs/logs.sh --kind nginx
   ```

   出力が combined など LTSV 以外なら、**image 側 nginx config を LTSV 化（`templates/nginx-00-ltsv.conf` 参照）して deploy** する。running container 内を直接編集しない。これは Phase4 の作業ではなく Phase1 で済ませる。

2. Aurora の slow query が読めること。cluster / instance parameter group で `slow_query_log=1` + `log_output=TABLE`（上記 "Verify Aurora Slow Query" 参照）。**または** Performance Insights が有効であること。PI が有効なら mysql 直結不要で、クエリを DB Load 順に順位付けできる（VPC 外の workstation から Aurora に到達できない場合の代替になる）。

   PI が無効なら次で有効化できる（Aurora MySQL は再起動不要・無料枠7日保持、observability 設定でありスペック/構成変更ではない）。

   ```bash
   aws rds modify-db-instance --db-instance-identifier <id> --enable-performance-insights --apply-immediately
   aws rds describe-db-instances --query 'DBInstances[0].PerformanceInsightsEnabled'
   ```

3. baseline ベンチ→`scripts/ecs/analyze.sh` の出力が **NON-EMPTY** であることを確認してから Phase2 に入る。

   - alp セクションに行が出ている
   - slow query セクション **または** Performance Insights セクションに行が出ている

   どちらかが空なら、Phase2 に進まずまず計測を直す（LTSV 化・slow query 有効化 / PI 有効化・到達性）。

## Output

- `scripts/env.sh` の確認・補完
- `reports/survey.md` の AWS 構成サマリー更新
- 未確定項目がある場合は `reports/survey.md` に TODO として記録

## Questions To Resolve

- benchmark は backend ALB を直接叩くか、frontend ALB 経由か
- benchmark SQS message body の正確な形式
- benchmark の実行時間（`BENCH_DURATION_SEC`）と、score / pass-fail の返却経路（結果 SQS / worker logs / ポータル）
- pprof を ECS Exec、task IP、temporary security group のどれで取るか
- app は stateless か。画像/upload/session が local 依存でないか
