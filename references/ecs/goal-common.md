# ECS/RDS Goal Common Rules

ECS + RDS 環境では、既存の `references/goals/` ではなくこの `references/ecs/` を正本にする。
作業は ECS task 内ではなく、原則として AWS CLI と Docker が使えるローカル端末または作業用 EC2 から行う。

## Environment

最初に `$TOOL_REPO/scripts/env.sh` を読む。存在する場合は `source "$TOOL_REPO/scripts/env.sh"` して、少なくとも次を確認する:

- `TOOL_REPO`
- `ISUCON_RUNTIME=ecs`
- `ISUCON_WEBAPP_DIR` または `APP_BUILD_DIR`
- `AWS_REGION`
- `ECS_CLUSTER`
- `ECS_SERVICE`
- `ECS_TASK_DEFINITION`
- `ECS_APP_CONTAINER`
- `ECS_NGINX_CONTAINER`
- `ECS_LOG_GROUP` / `ECS_NGINX_LOG_GROUP` / `ECS_APP_LOG_GROUP`
- `ECS_LOG_STREAM_PREFIX` / `ECS_NGINX_LOG_STREAM_PREFIX` / `ECS_APP_LOG_STREAM_PREFIX`
- `ECR_IMAGE`
- `ECR_REPOSITORY`（`ECR_IMAGE` を自動生成する場合）
- `IMAGE_TAG`
- `FRONTEND_ALB_NAME` / `FRONTEND_ALB_ARN` / `FRONTEND_ALB_DNS_NAME`
- `BACKEND_ALB_NAME` / `BACKEND_ALB_ARN` / `BACKEND_ALB_DNS_NAME`
- `BENCH_TARGET_URL`（空なら backend ALB から解決）
- `BENCH_QUEUE_URL` または `BENCH_QUEUE_NAME`
- `BENCH_MESSAGE_BODY` または `BENCH_MESSAGE_FILE`
- `BENCH_CMD`
- `REBUILD_CMD`
- `DB_TYPE=rds|aurora`
- `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASS` / `DB_NAME`
- `RDS_CLUSTER` / `RDS_CLUSTER_PARAM_GROUP`（Aurora の場合）
- `RDS_INSTANCE`
- `RDS_PARAM_GROUP`

不明な値は推測で埋めない。`scripts/ecs/survey.sh` と AWS CLI で調査し、未確定として残す。

## Compact / Resume Safety

compact、中断、別 turn からの再開後は、作業を続ける前に必ず次を確認する。

1. 最新のユーザー指示を読む。特に「push して」「セルフレビューして」「Phase 4 で Phase 6 をしない」などの継続条件を確認する。
2. `git status --short --branch` を確認し、未コミット変更・未追跡ファイル・現在 branch を把握する。
3. `$TOOL_REPO/scripts/env.sh`、`reports/survey.md`、`reports/aws-survey.md`、`reports/ecs-survey.md`、最新 `reports/*.md` を必要に応じて読み直す。
4. 現在実行中の `references/ecs/` Phase reference と、この `references/ecs/goal-common.md` を読み直す。
5. 未完了タスク、禁止事項、AWS 操作対象、検証方法、push 要否を整理してから再開する。
6. compact 前の指示が不明、または相互に矛盾して見える場合は、推測で進めずユーザーに確認する。

この確認は Phase 固有手順より優先する。

## Execution Model

- rebuild / deploy / benchmark は必ず `$TOOL_REPO/scripts/ecs/bench-locked.sh` で直列化する。
- ECS deploy は ECR push + `aws ecs update-service --force-new-deployment` + `aws ecs wait services-stable` を基本にする。既存 task definition が同じ image tag を参照している前提で、task definition revision は自動作成しない。
- `ECR_IMAGE` が未確定なら、`ECR_REPOSITORY` と `aws sts get-caller-identity` の account ID から deploy script が組み立てる。
- SQS queue で benchmark を起動する場合は `BENCH_CMD='bash $TOOL_REPO/scripts/ecs/bench-sqs.sh'` を使う。
- task 内で設定ファイルを直接編集しない。変更は app repo、Docker image、task definition、ECS service、RDS parameter group に反映する。
- nginx/app logs は CloudWatch Logs から取得する。ローカル file path 前提の `NGINX_ACCESS_LOG` に依存しない。
- RDS slow query は `mysql.slow_log` table または AWS CLI の RDS log download から取得する。
- frontend ALB と backend ALB が分かれる場合、benchmark target は backend ALB として扱う。frontend task から backend ALB へアクセスする構成では、両方の ALB 名/ARN/DNS を report に残す。

## Benchmark Exclusivity

- benchmark は常に1つだけ実行する。
- deploy 中に benchmark しない。
- benchmark の前後で `BENCH_START_EPOCH` を記録し、その時刻以降の CloudWatch Logs を分析する。
- ベンチ後は `$TOOL_REPO/scripts/ecs/analyze.sh` を実行し、必要に応じて `$TOOL_REPO/scripts/score-log.sh` で記録する。

## Failure Diagnosis

fail が出た場合、即ロールバック・即却下しない。最低限以下を確認する:

- benchmark stdout / stderr
- `aws ecs describe-services`
- `aws ecs describe-tasks`
- ECS deployment event
- app container CloudWatch Logs
- nginx container CloudWatch Logs
- RDS slow query / connection error
- target URL healthcheck
- security group / task IP / port mapping

特に ECS では次を疑う:

- 新 task が stable になっていない
- 古い image tag が使われている
- task definition が想定 revision と違う
- CloudWatch log stream prefix の取り違え
- security group が RDS / benchmark / pprof を許可していない
- app が local filesystem / local memory session に依存している

## Git Safety

- `git reset --hard` などの破壊的操作は禁止。
- unrelated changes を巻き戻さない。
- 採用した app 変更は commit を残す。
- ECS/RDS 操作は、変更前後の ARN、revision、parameter group 名、image tag を report に記録する。

## Recording

- アプリ改善: `$TOOL_REPO/scripts/improvement-log.sh`
- スコア: `$TOOL_REPO/scripts/score-log.sh`
- ECS/RDS 調査: `$TOOL_REPO/reports/ecs-survey.md`
- ミドルウェア評価: `$TOOL_REPO/reports/ecs-infra-tuning.md`
- scale 評価: `$TOOL_REPO/reports/ecs-scale.md`
- 最終整備: `$TOOL_REPO/reports/ecs-final-prep.md`
