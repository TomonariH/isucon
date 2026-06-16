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
  echo "## env.sh candidate"
  echo ""
  echo '```bash'
  echo "export ISUCON_RUNTIME='ecs'"
  echo "export AWS_REGION='${AWS_REGION:-}'"
  echo "export ECS_CLUSTER='$ECS_CLUSTER'"
  echo "export ECS_SERVICE='$ECS_SERVICE'"
  echo "export ECS_TASK_DEFINITION='$task_def'"
  echo "export DB_TYPE='rds'"
  echo "export REBUILD_CMD='bash scripts/ecs/deploy.sh'"
  echo "export BENCH_TARGET_URL='<task-ip-or-host-url>'"
  echo "export BENCH_CMD='<benchmark command>'"
  echo '```'
} > "$REPORT_FILE"

ecs_log "wrote: $REPORT_FILE"
