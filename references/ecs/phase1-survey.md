# ECS/RDS Phase 1 Survey

ECS + RDS 環境の初動調査を行い、`scripts/env.sh` に必要な値を確定する。

## Read First

- `$TOOL_REPO/references/ecs/goal-common.md`

## Procedure

1. AWS CLI の権限と region を確認する。

   ```bash
   aws sts get-caller-identity
   aws configure get region
   ```

2. ECS cluster / service を特定する。

   ```bash
   aws ecs list-clusters
   aws ecs list-services --cluster <cluster>
   ```

3. backend service の調査 report を生成する。frontend / backend が分かれる場合、まず benchmark 対象の backend service を `ECS_SERVICE` にする。

   ```bash
   ECS_CLUSTER=<cluster> ECS_SERVICE=<service> bash scripts/ecs/survey.sh
   ```

4. `reports/ecs-survey.md` から task definition、container name、image、port、logConfiguration、target group、ALB を読む。

5. frontend ALB / backend ALB / benchmark queue を特定する。

   ```bash
   aws elbv2 describe-load-balancers \
     --query 'LoadBalancers[*].{name:LoadBalancerName,dns:DNSName,scheme:Scheme,type:Type}'
   aws sqs list-queues
   ```

   backend ALB を直接叩ける構成なら、benchmark target は backend ALB にする。frontend task から backend ALB へアクセスする構成では、frontend ALB と backend ALB の両方を記録する。

6. Aurora MySQL / RDS を特定する。

   ```bash
   aws rds describe-db-clusters \
     --query 'DBClusters[*].{id:DBClusterIdentifier,endpoint:Endpoint,reader:ReaderEndpoint,engine:Engine,clusterParameterGroup:DBClusterParameterGroup}'
   aws rds describe-db-instances \
     --query 'DBInstances[*].{id:DBInstanceIdentifier,cluster:DBClusterIdentifier,endpoint:Endpoint.Address,engine:Engine,parameterGroup:DBParameterGroups[0].DBParameterGroupName}'
   ```

7. `scripts/env.sh` を ECS/RDS 用に更新する。最低限:

   ```bash
   export ISUCON_RUNTIME='ecs'
   export AWS_REGION='<region>'
   export ECS_CLUSTER='<cluster>'
   export ECS_SERVICE='<service>'
   export ECS_APP_CONTAINER='<app container>'
   export ECS_NGINX_CONTAINER='<nginx container>'
   export ECS_LOG_GROUP='<cloudwatch log group>'
   export ECS_LOG_STREAM_PREFIX='<stream prefix>'
   export ECR_REPOSITORY='<repository-name>'
   export ECR_IMAGE='<account>.dkr.ecr.<region>.amazonaws.com/<repo>'
   export IMAGE_TAG='isucon-latest'
   export APP_BUILD_DIR='<app build context>'
   export DB_TYPE='aurora'
   export DB_HOST='<rds endpoint>'
   export DB_PORT='3306'
   export DB_USER='<user>'
   export DB_PASS='<password>'
   export DB_NAME='<dbname>'
   export RDS_CLUSTER='<aurora cluster id>'
   export RDS_CLUSTER_PARAM_GROUP='<aurora cluster parameter group>'
   export RDS_INSTANCE='<db instance id>'
   export RDS_PARAM_GROUP='<parameter group>'
   export FRONTEND_ALB_NAME='<frontend alb name>'
   export BACKEND_ALB_NAME='<backend alb name>'
   export BACKEND_ALB_PROTOCOL='http'
   export BACKEND_ALB_PATH='/'
   export BENCH_QUEUE_NAME='<benchmark queue name>'
   export BENCH_CMD='bash scripts/ecs/bench-sqs.sh'
   export BENCH_MESSAGE_BODY='{"target_url":"{{BENCH_TARGET_URL}}"}'
   export REBUILD_CMD='bash scripts/ecs/deploy.sh'
   ```

8. backend ALB URL と SQS benchmark request を dry run で確認する。

   ```bash
   bash scripts/ecs/resolve-alb-url.sh --kind backend
   BENCH_MESSAGE_BODY='{"target_url":"{{BENCH_TARGET_URL}}"}' bash scripts/ecs/bench-sqs.sh --dry-run
   ```

   実際の message body 形式は大会ごとに変わるため、配布資料の形式に合わせて `BENCH_MESSAGE_BODY` または `BENCH_MESSAGE_FILE` を調整する。

9. nginx stdout が alp で読める形式か確認する。LTSV でない場合、nginx config を image 側で変更する候補として記録する。

10. Aurora slow query log の状態を確認する。ECS では `scripts/setup-rds.sh` を直接使わない。あの script は systemd / Docker Compose 向けの nginx/app setup も呼ぶため、RDS/Aurora parameter 操作だけを AWS CLI で確認する。

   ```bash
   aws rds describe-db-cluster-parameters \
     --db-cluster-parameter-group-name <cluster parameter group> \
     --query 'Parameters[?ParameterName==`slow_query_log` || ParameterName==`long_query_time` || ParameterName==`log_output`].[ParameterName,ParameterValue,ApplyType,ApplyMethod]' \
     --output table
   aws rds describe-db-parameters \
     --db-parameter-group-name <parameter group> \
     --query 'Parameters[?ParameterName==`slow_query_log` || ParameterName==`long_query_time` || ParameterName==`log_output`].[ParameterName,ParameterValue,ApplyType,ApplyMethod]' \
     --output table
   ```

   変更が必要な場合は `templates/rds-parameter-group.md` を読み、競技ルールと再起動影響を確認してから parameter group を変更する。

## Output

- `scripts/env.sh`
- `reports/ecs-survey.md`
- `scripts/alp.yml`

## Questions To Resolve

- launch type は EC2 か Fargate か
- benchmark は backend ALB を叩くか、frontend ALB 経由か
- benchmark SQS message body の正確な形式
- pprof を ECS Exec、task IP、temporary security group のどれで取るか
- app は stateless か。画像/upload/session が local 依存でないか
