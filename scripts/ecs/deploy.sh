#!/bin/bash
# Docker image を build/push し、ECS service を新規 deployment へ更新する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

APP_BUILD_DIR="${APP_BUILD_DIR:-${ISUCON_WEBAPP_DIR:-}}"
IMAGE_TAG="${IMAGE_TAG:-isucon-latest}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
PLATFORM_ARG="${DOCKER_PLATFORM:+--platform $DOCKER_PLATFORM}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/deploy.sh

Environment:
  APP_BUILD_DIR        Docker build context, defaults to ISUCON_WEBAPP_DIR
  DOCKERFILE          Dockerfile path relative to APP_BUILD_DIR, default: Dockerfile
  ECR_IMAGE           ECR image URI without tag
  IMAGE_TAG           image tag, default: isucon-latest
  AWS_REGION          AWS region
  ECS_CLUSTER         ECS cluster name
  ECS_SERVICE         ECS service name
  SKIP_DOCKER_BUILD   1 to skip docker build/tag/push and only force ECS deployment
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

ecs_require_cmd aws docker
ecs_require_env ECR_IMAGE ECS_CLUSTER ECS_SERVICE
if [ "${SKIP_DOCKER_BUILD:-0}" != "1" ]; then
  [ -n "$APP_BUILD_DIR" ] || {
    echo "[ecs] ERROR: APP_BUILD_DIR or ISUCON_WEBAPP_DIR is required" >&2
    exit 1
  }
  [ -d "$APP_BUILD_DIR" ] || {
    echo "[ecs] ERROR: APP_BUILD_DIR not found: $APP_BUILD_DIR" >&2
    exit 1
  }

  ECR_REGISTRY="${ECR_IMAGE%%/*}"
  ecs_log "docker build: $ECR_IMAGE:$IMAGE_TAG"
  # shellcheck disable=SC2086
  docker build $PLATFORM_ARG -f "$APP_BUILD_DIR/$DOCKERFILE" -t "$ECR_IMAGE:$IMAGE_TAG" "$APP_BUILD_DIR"
  ecs_aws ecr get-login-password | docker login --username AWS --password-stdin "$ECR_REGISTRY"
  docker push "$ECR_IMAGE:$IMAGE_TAG"
fi

ecs_log "force new ECS deployment: $ECS_CLUSTER/$ECS_SERVICE"
ecs_aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$ECS_SERVICE" \
  --force-new-deployment >/dev/null

bash "$TOOL_REPO/scripts/ecs/wait-stable.sh"
