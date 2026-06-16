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

## Output

- `scripts/env.sh` の確認・補完
- `reports/survey.md` の AWS 構成サマリー更新
- 未確定項目がある場合は `reports/survey.md` に TODO として記録

## Questions To Resolve

- benchmark は backend ALB を直接叩くか、frontend ALB 経由か
- benchmark SQS message body の正確な形式
- pprof を ECS Exec、task IP、temporary security group のどれで取るか
- app は stateless か。画像/upload/session が local 依存でないか
