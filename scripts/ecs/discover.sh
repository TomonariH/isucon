#!/bin/bash
# AWS アカウント内の ECS / ALB / RDS(Aurora) / SQS / ECR / CloudWatch Logs を概観する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

REPORT_FILE="${REPORT_FILE:-$TOOL_REPO/reports/aws-survey.md}"
AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
export AWS_REGION

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/discover.sh

Environment:
  AWS_REGION   AWS region. Defaults to aws configure get region.
  REPORT_FILE  output path, default: reports/aws-survey.md

Output:
  Broad AWS structure report for /isucon-survey.
EOF
}

case "${1:-}" in
  -h|--help)
    usage; exit 0
    ;;
esac

ecs_require_cmd aws
mkdir -p "$(dirname "$REPORT_FILE")"

json_section() {
  local title="$1"
  shift
  echo "## $title"
  echo ""
  echo '```json'
  "$@" --output json || true
  echo '```'
  echo ""
}

ecs_services_section() {
  local clusters cluster service_arns service_arn
  echo "## ECS Services"
  echo ""
  clusters="$(ecs_aws ecs list-clusters --query 'clusterArns[]' --output text 2>/dev/null || true)"
  if [ -z "$clusters" ] || [ "$clusters" = "None" ]; then
    echo "> No ECS clusters found or permission denied."
    echo ""
    return
  fi

  for cluster in $clusters; do
    echo "### $cluster"
    echo ""
    echo '```json'
    ecs_aws ecs describe-clusters --clusters "$cluster" \
      --query 'clusters[*].{clusterArn:clusterArn,clusterName:clusterName,status:status,registeredContainerInstancesCount:registeredContainerInstancesCount,runningTasksCount:runningTasksCount,activeServicesCount:activeServicesCount,capacityProviders:capacityProviders}' \
      --output json || true
    echo '```'
    echo ""

    service_arns="$(ecs_aws ecs list-services --cluster "$cluster" --query 'serviceArns[]' --output text 2>/dev/null || true)"
    if [ -z "$service_arns" ] || [ "$service_arns" = "None" ]; then
      echo "> No services found."
      echo ""
      continue
    fi

    for service_arn in $service_arns; do
      echo "#### $service_arn"
      echo ""
      echo '```json'
      ecs_aws ecs describe-services --cluster "$cluster" --services "$service_arn" \
        --query 'services[0].{serviceName:serviceName,status:status,desiredCount:desiredCount,runningCount:runningCount,launchType:launchType,capacityProviderStrategy:capacityProviderStrategy,taskDefinition:taskDefinition,loadBalancers:loadBalancers,networkConfiguration:networkConfiguration}' \
        --output json || true
      echo '```'
      echo ""
    done
  done
}

env_candidate_section() {
  cat <<'EOF'
## env.sh candidate after selecting backend service

```bash
export ISUCON_RUNTIME='ecs'
export AWS_REGION='<region>'
export ECS_CLUSTER='<backend-cluster-name-or-arn>'
export ECS_SERVICE='<backend-service-name>'
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

Next:

```bash
ECS_CLUSTER="$ECS_CLUSTER" ECS_SERVICE="$ECS_SERVICE" BENCH_QUEUE_NAME="$BENCH_QUEUE_NAME" bash scripts/ecs/survey.sh
```
EOF
}

listeners_section() {
  local lb_arns lb_arn
  echo "## Listeners"
  echo ""
  lb_arns="$(ecs_aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text 2>/dev/null || true)"
  if [ -z "$lb_arns" ] || [ "$lb_arns" = "None" ]; then
    echo "> No load balancers found or permission denied."
    echo ""
    return
  fi

  for lb_arn in $lb_arns; do
    echo "### $lb_arn"
    echo ""
    echo '```json'
    ecs_aws elbv2 describe-listeners --load-balancer-arn "$lb_arn" \
      --query 'Listeners[*].{listenerArn:ListenerArn,port:Port,protocol:Protocol,defaultActions:DefaultActions}' \
      --output json || true
    echo '```'
    echo ""
  done
}

{
  echo "# AWS Service Survey"
  echo ""
  echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "## Account"
  echo ""
  echo '```json'
  ecs_aws sts get-caller-identity --output json || true
  echo '```'
  echo ""
  echo "## Region"
  echo ""
  echo '```text'
  echo "${AWS_REGION:-<aws-cli-default-region>}"
  echo '```'
  echo ""

  ecs_services_section

  json_section "Load Balancers" ecs_aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[*].{name:LoadBalancerName,dns:DNSName,scheme:Scheme,type:Type,vpcId:VpcId,arn:LoadBalancerArn}'

  json_section "Target Groups" ecs_aws elbv2 describe-target-groups \
    --query 'TargetGroups[*].{name:TargetGroupName,arn:TargetGroupArn,protocol:Protocol,port:Port,targetType:TargetType,loadBalancerArns:LoadBalancerArns,healthCheckPath:HealthCheckPath}'

  listeners_section

  json_section "RDS / Aurora Clusters" ecs_aws rds describe-db-clusters \
    --query 'DBClusters[*].{id:DBClusterIdentifier,engine:Engine,endpoint:Endpoint,readerEndpoint:ReaderEndpoint,clusterParameterGroup:DBClusterParameterGroup,members:DBClusterMembers[*].DBInstanceIdentifier}'

  json_section "RDS / Aurora Instances" ecs_aws rds describe-db-instances \
    --query 'DBInstances[*].{id:DBInstanceIdentifier,cluster:DBClusterIdentifier,engine:Engine,endpoint:Endpoint.Address,dbParameterGroup:DBParameterGroups[0].DBParameterGroupName}'

  json_section "SQS Queues" ecs_aws sqs list-queues

  json_section "ECR Repositories" ecs_aws ecr describe-repositories \
    --query 'repositories[*].{name:repositoryName,uri:repositoryUri}'

  json_section "CloudWatch Log Groups" ecs_aws logs describe-log-groups \
    --query 'logGroups[*].{name:logGroupName,storedBytes:storedBytes,retentionInDays:retentionInDays}'

  env_candidate_section
} > "$REPORT_FILE"

ecs_log "wrote: $REPORT_FILE"
