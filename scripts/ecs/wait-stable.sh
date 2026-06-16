#!/bin/bash
# ECS service が安定し、任意の healthcheck が通るまで待つ。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

WAIT_SERVICES_TIMEOUT="${WAIT_SERVICES_TIMEOUT:-300}"
HEALTHCHECK_TIMEOUT="${HEALTHCHECK_TIMEOUT:-60}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/wait-stable.sh

Environment:
  ECS_CLUSTER          ECS cluster name
  ECS_SERVICE          ECS service name
  AWS_REGION           optional AWS region
  HEALTHCHECK_CMD      optional command to verify the benchmark endpoint
  BENCH_TARGET_URL     used as default healthcheck URL when HEALTHCHECK_CMD is empty
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

ecs_require_cmd aws
ecs_require_env ECS_CLUSTER ECS_SERVICE

ecs_log "waiting for ECS service stable: $ECS_CLUSTER/$ECS_SERVICE"
timeout "$WAIT_SERVICES_TIMEOUT" bash -c '
  set -euo pipefail
  source "'"$SCRIPT_DIR"'/lib.sh"
  ecs_load_env
  ecs_aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE"
'

if [ -z "${HEALTHCHECK_CMD:-}" ] && [ -n "${BENCH_TARGET_URL:-}" ]; then
  ecs_require_cmd curl
  HEALTHCHECK_CMD="curl -fsS '$BENCH_TARGET_URL' >/dev/null"
fi

if [ -n "${HEALTHCHECK_CMD:-}" ]; then
  ecs_log "waiting for healthcheck"
  deadline=$((SECONDS + HEALTHCHECK_TIMEOUT))
  until eval "$HEALTHCHECK_CMD"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "[ecs] ERROR: healthcheck did not pass within ${HEALTHCHECK_TIMEOUT}s" >&2
      exit 1
    fi
    sleep 2
  done
fi

ecs_log "service is stable"
