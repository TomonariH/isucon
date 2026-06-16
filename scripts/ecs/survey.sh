#!/bin/bash
# ECS service/task/log 情報を AWS CLI から収集する。env.sh は自動生成せず、候補値を report に出す。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

REPORT_FILE="${REPORT_FILE:-$TOOL_REPO/reports/ecs-survey.md}"

usage() {
  cat <<'EOF'
Usage:
  ECS_CLUSTER=<cluster> ECS_SERVICE=<service> scripts/ecs/survey.sh

Environment:
  AWS_REGION      optional AWS region
  ECS_CLUSTER     ECS cluster name
  ECS_SERVICE     ECS service name
  BENCH_QUEUE_NAME optional benchmark SQS queue name
EOF
}

case "${1:-}" in
  -h|--help)
    usage; exit 0
    ;;
esac

ecs_require_cmd aws
ecs_require_env ECS_CLUSTER ECS_SERVICE
mkdir -p "$(dirname "$REPORT_FILE")"

task_def="$(ecs_service_task_definition)"
task_arn="$(ecs_latest_task_arn || true)"
target_group_arns="$(ecs_aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" --query 'services[0].loadBalancers[].targetGroupArn' --output text 2>/dev/null || true)"
rds_cluster="${RDS_CLUSTER:-${DB_CLUSTER:-}}"
rds_instance="${RDS_INSTANCE:-}"

{
  echo "# ECS/RDS Survey"
  echo ""
  echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## Service"
  echo ""
  echo '```json'
  ecs_aws ecs describe-services --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
    --query 'services[0].{clusterArn:clusterArn,serviceName:serviceName,status:status,desiredCount:desiredCount,runningCount:runningCount,launchType:launchType,capacityProviderStrategy:capacityProviderStrategy,taskDefinition:taskDefinition,loadBalancers:loadBalancers,networkConfiguration:networkConfiguration}' \
    --output json
  echo '```'
  echo ""
  echo "## Task Definition"
  echo ""
  echo '```json'
  ecs_aws ecs describe-task-definition --task-definition "$task_def" \
    --query 'taskDefinition.{family:family,revision:revision,networkMode:networkMode,cpu:cpu,memory:memory,requiresCompatibilities:requiresCompatibilities,containerDefinitions:containerDefinitions[*].{name:name,image:image,cpu:cpu,memory:memory,portMappings:portMappings,environment:environment,logConfiguration:logConfiguration}}' \
    --output json
  echo '```'
  echo ""
  if [ -n "${task_arn:-}" ] && [ "$task_arn" != "None" ]; then
    echo "## Running Task"
    echo ""
    echo '```json'
    ecs_aws ecs describe-tasks --cluster "$ECS_CLUSTER" --tasks "$task_arn" \
      --query 'tasks[0].{taskArn:taskArn,lastStatus:lastStatus,launchType:launchType,capacityProviderName:capacityProviderName,containers:containers[*].{name:name,lastStatus:lastStatus,networkInterfaces:networkInterfaces},attachments:attachments}' \
      --output json
    echo '```'
    echo ""
  fi
  if [ -n "${target_group_arns:-}" ] && [ "$target_group_arns" != "None" ]; then
    echo "## Target Groups / Load Balancers"
    echo ""
    echo '```json'
    ecs_aws elbv2 describe-target-groups --target-group-arns $target_group_arns \
      --query 'TargetGroups[*].{targetGroupArn:TargetGroupArn,targetGroupName:TargetGroupName,protocol:Protocol,port:Port,targetType:TargetType,loadBalancerArns:LoadBalancerArns,healthCheckPath:HealthCheckPath}' \
      --output json || true
    echo '```'
    lb_arns="$(ecs_aws elbv2 describe-target-groups --target-group-arns $target_group_arns --query 'TargetGroups[].LoadBalancerArns[]' --output text 2>/dev/null || true)"
    if [ -n "${lb_arns:-}" ] && [ "$lb_arns" != "None" ]; then
      echo ""
      echo '```json'
      ecs_aws elbv2 describe-load-balancers --load-balancer-arns $lb_arns \
        --query 'LoadBalancers[*].{loadBalancerArn:LoadBalancerArn,loadBalancerName:LoadBalancerName,DNSName:DNSName,Scheme:Scheme,Type:Type,VpcId:VpcId}' \
        --output json || true
      echo '```'
    fi
    echo ""
  fi
  if [ -n "${BENCH_QUEUE_NAME:-}" ]; then
    echo "## Benchmark Queue"
    echo ""
    echo '```json'
    ecs_aws sqs get-queue-url --queue-name "$BENCH_QUEUE_NAME" --output json || true
    echo '```'
    echo ""
  fi
  echo "## RDS / Aurora"
  echo ""
  echo '```json'
  if [ -n "$rds_cluster" ]; then
    ecs_aws rds describe-db-clusters --db-cluster-identifier "$rds_cluster" \
      --query 'DBClusters[*].{dbClusterIdentifier:DBClusterIdentifier,engine:Engine,endpoint:Endpoint,readerEndpoint:ReaderEndpoint,dbClusterParameterGroup:DBClusterParameterGroup,dbClusterMembers:DBClusterMembers[*].DBInstanceIdentifier}' \
      --output json || true
  else
    ecs_aws rds describe-db-clusters \
      --query 'DBClusters[*].{dbClusterIdentifier:DBClusterIdentifier,engine:Engine,endpoint:Endpoint,readerEndpoint:ReaderEndpoint,dbClusterParameterGroup:DBClusterParameterGroup,dbClusterMembers:DBClusterMembers[*].DBInstanceIdentifier}' \
      --output json || true
  fi
  echo '```'
  echo ""
  echo '```json'
  if [ -n "$rds_instance" ]; then
    ecs_aws rds describe-db-instances --db-instance-identifier "$rds_instance" \
      --query 'DBInstances[*].{dbInstanceIdentifier:DBInstanceIdentifier,dbClusterIdentifier:DBClusterIdentifier,engine:Engine,endpoint:Endpoint.Address,dbParameterGroup:DBParameterGroups[0].DBParameterGroupName}' \
      --output json || true
  else
    ecs_aws rds describe-db-instances \
      --query 'DBInstances[*].{dbInstanceIdentifier:DBInstanceIdentifier,dbClusterIdentifier:DBClusterIdentifier,engine:Engine,endpoint:Endpoint.Address,dbParameterGroup:DBParameterGroups[0].DBParameterGroupName}' \
      --output json || true
  fi
  echo '```'
  echo ""
  echo "## env.sh candidate"
  echo ""
  echo '```bash'
  echo "export ISUCON_RUNTIME='ecs'"
  echo "export AWS_REGION='${AWS_REGION:-}'"
  echo "export ECS_CLUSTER='$ECS_CLUSTER'"
  echo "export ECS_SERVICE='$ECS_SERVICE'"
  echo "export ECS_TASK_DEFINITION='$task_def'"
  echo "export DB_TYPE='aurora'"
  echo "export RDS_CLUSTER='<aurora-cluster-id>'"
  echo "export RDS_CLUSTER_PARAM_GROUP='<aurora-cluster-parameter-group>'"
  echo "export RDS_INSTANCE='<db-instance-id>'"
  echo "export RDS_PARAM_GROUP='<db-instance-parameter-group>'"
  echo "export REBUILD_CMD='bash scripts/ecs/deploy.sh'"
  echo "export ECR_REPOSITORY='<repository-name>'"
  echo "export BACKEND_ALB_NAME='<backend-alb-name>'"
  echo "export BACKEND_ALB_PROTOCOL='http'"
  echo "export BACKEND_ALB_PATH='/'"
  echo "export BENCH_QUEUE_NAME='${BENCH_QUEUE_NAME:-<benchmark-queue-name>}'"
  echo "export BENCH_CMD='bash scripts/ecs/bench-sqs.sh'"
  echo "export BENCH_MESSAGE_BODY='{\"target_url\":\"{{BENCH_TARGET_URL}}\"}'"
  echo '```'
} > "$REPORT_FILE"

ecs_log "wrote: $REPORT_FILE"
