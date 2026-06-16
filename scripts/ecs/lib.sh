#!/bin/bash
# ECS/RDS 環境向け helper。scripts/ecs/*.sh から source して使う。
# このファイルは直接実行しない。

ecs_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

ecs_tool_repo() {
  local dir
  dir="$(ecs_script_dir)"
  cd "$dir/../.." && pwd
}

ecs_load_env() {
  local repo
  repo="$(ecs_tool_repo)"
  [ -f "$repo/scripts/env.sh" ] && source "$repo/scripts/env.sh"
}

ecs_log() {
  echo "[ecs] $*"
}

ecs_require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || {
      echo "[ecs] ERROR: command not found: $cmd" >&2
      return 1
    }
  done
}

ecs_require_env() {
  local name
  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      echo "[ecs] ERROR: $name is required" >&2
      return 1
    fi
  done
}

ecs_aws() {
  if [ -n "${AWS_REGION:-}" ]; then
    aws --region "$AWS_REGION" "$@"
  else
    aws "$@"
  fi
}

ecs_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

ecs_indirect() {
  local name="$1"
  printf '%s' "${!name:-}"
}

ecs_sqs_queue_url() {
  local queue_url="${BENCH_QUEUE_URL:-${SQS_QUEUE_URL:-}}"
  local queue_name="${BENCH_QUEUE_NAME:-${SQS_QUEUE_NAME:-}}"
  if [ -n "$queue_url" ]; then
    echo "$queue_url"
    return
  fi
  [ -n "$queue_name" ] || {
    echo "[ecs] ERROR: BENCH_QUEUE_URL or BENCH_QUEUE_NAME is required" >&2
    return 1
  }
  ecs_require_cmd aws || return 1
  ecs_aws sqs get-queue-url --queue-name "$queue_name" --query 'QueueUrl' --output text
}

ecs_json_escape() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
  else
    sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{printf "\""} {printf "%s%s", sep, $0; sep="\\n"} END{printf "\""}'
  fi
}

ecs_alb_url_for() {
  local kind="$1"
  local upper url dns arn name protocol port path lb_info port_part
  upper="$(ecs_upper "$kind")"

  url="$(ecs_indirect "${upper}_ALB_URL")"
  if [ -n "$url" ]; then
    echo "$url"
    return
  fi

  dns="$(ecs_indirect "${upper}_ALB_DNS_NAME")"
  arn="$(ecs_indirect "${upper}_ALB_ARN")"
  name="$(ecs_indirect "${upper}_ALB_NAME")"
  if [ -z "$dns" ] && [ -n "$arn" ]; then
    ecs_require_cmd aws || return 1
    dns="$(ecs_aws elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].DNSName' --output text)"
  elif [ -z "$dns" ] && [ -n "$name" ]; then
    ecs_require_cmd aws || return 1
    dns="$(ecs_aws elbv2 describe-load-balancers --names "$name" --query 'LoadBalancers[0].DNSName' --output text)"
  fi
  [ -n "$dns" ] && [ "$dns" != "None" ] || {
    echo "[ecs] ERROR: ${upper}_ALB_URL, ${upper}_ALB_DNS_NAME, ${upper}_ALB_ARN, or ${upper}_ALB_NAME is required" >&2
    return 1
  }

  protocol="$(ecs_indirect "${upper}_ALB_PROTOCOL")"
  protocol="${protocol:-http}"
  port="$(ecs_indirect "${upper}_ALB_PORT")"
  path="$(ecs_indirect "${upper}_ALB_PATH")"
  path="${path:-/}"
  case "$path" in
    /*) ;;
    *) path="/$path" ;;
  esac

  port_part=""
  if [ -n "$port" ]; then
    port_part=":$port"
  fi
  lb_info="${protocol}://${dns}${port_part}${path}"
  echo "$lb_info"
}

ecs_latest_task_arn() {
  ecs_require_env ECS_CLUSTER ECS_SERVICE || return 1
  ecs_aws ecs list-tasks \
    --cluster "$ECS_CLUSTER" \
    --service-name "$ECS_SERVICE" \
    --desired-status RUNNING \
    --query 'taskArns[0]' \
    --output text
}

ecs_service_task_definition() {
  ecs_require_env ECS_CLUSTER ECS_SERVICE || return 1
  ecs_aws ecs describe-services \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --query 'services[0].taskDefinition' \
    --output text
}

ecs_service_launch_type() {
  ecs_require_env ECS_CLUSTER ECS_SERVICE || return 1
  ecs_aws ecs describe-services \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --query 'services[0].{launchType:launchType,capacityProviderStrategy:capacityProviderStrategy}' \
    --output json
}

ecs_log_group_for() {
  local kind="$1"
  case "$kind" in
    nginx)
      echo "${ECS_NGINX_LOG_GROUP:-${ECS_LOG_GROUP:-}}"
      ;;
    app)
      echo "${ECS_APP_LOG_GROUP:-${ECS_LOG_GROUP:-}}"
      ;;
    *)
      echo "${ECS_LOG_GROUP:-}"
      ;;
  esac
}

ecs_log_stream_prefix_for() {
  local kind="$1"
  case "$kind" in
    nginx)
      echo "${ECS_NGINX_LOG_STREAM_PREFIX:-${ECS_LOG_STREAM_PREFIX:-}}"
      ;;
    app)
      echo "${ECS_APP_LOG_STREAM_PREFIX:-${ECS_LOG_STREAM_PREFIX:-}}"
      ;;
    *)
      echo "${ECS_LOG_STREAM_PREFIX:-}"
      ;;
  esac
}

ecs_fetch_logs() {
  local kind="$1"
  local since_epoch="$2"
  local out="$3"
  local group prefix start_ms tmp_json

  group="$(ecs_log_group_for "$kind")"
  prefix="$(ecs_log_stream_prefix_for "$kind")"
  [ -n "$group" ] || {
    echo "[ecs] ERROR: log group is required for $kind logs" >&2
    return 1
  }

  start_ms=$((since_epoch * 1000))
  mkdir -p "$(dirname "$out")"
  tmp_json="$(mktemp)"
  if [ -n "$prefix" ]; then
    ecs_aws logs filter-log-events \
      --log-group-name "$group" \
      --log-stream-name-prefix "$prefix" \
      --start-time "$start_ms" \
      --query 'events[].message' \
      --output json > "$tmp_json"
  else
    ecs_aws logs filter-log-events \
      --log-group-name "$group" \
      --start-time "$start_ms" \
      --query 'events[].message' \
      --output json > "$tmp_json"
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$tmp_json" > "$out" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    messages = json.load(f)
for message in messages:
    print(message)
PY
  else
    echo "[ecs] ERROR: python3 is required to preserve tabs in CloudWatch log messages" >&2
    rm -f "$tmp_json"
    return 1
  fi
  rm -f "$tmp_json"
}
