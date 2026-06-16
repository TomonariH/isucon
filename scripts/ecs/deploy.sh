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
ECR_REPOSITORY="${ECR_REPOSITORY:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/deploy.sh

Environment:
  APP_BUILD_DIR        Docker build context, defaults to ISUCON_WEBAPP_DIR
  DOCKERFILE          Dockerfile path relative to APP_BUILD_DIR, default: Dockerfile
  ECR_IMAGE           ECR image URI without tag
  ECR_REPOSITORY      repository name used with aws sts account ID when ECR_IMAGE is empty
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

ecs_require_cmd aws
ecs_require_env ECS_CLUSTER ECS_SERVICE

if [ "${SKIP_DOCKER_BUILD:-0}" != "1" ]; then
  ecs_require_cmd docker
  if [ -z "${ECR_IMAGE:-}" ]; then
    [ -n "$ECR_REPOSITORY" ] || {
      echo "[ecs] ERROR: ECR_IMAGE or ECR_REPOSITORY is required" >&2
      exit 1
    }
    [ -n "${AWS_REGION:-}" ] || {
      echo "[ecs] ERROR: AWS_REGION is required when ECR_IMAGE is empty" >&2
      exit 1
    }
    AWS_ACCOUNT_ID="$(ecs_aws sts get-caller-identity --query Account --output text)"
    ECR_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
  fi

  [ -n "$APP_BUILD_DIR" ] || {
    echo "[ecs] ERROR: APP_BUILD_DIR or ISUCON_WEBAPP_DIR is required" >&2
    exit 1
  }
  [ -d "$APP_BUILD_DIR" ] || {
    echo "[ecs] ERROR: APP_BUILD_DIR not found: $APP_BUILD_DIR" >&2
    exit 1
  }

  # build host の arch が Fargate task の arch と一致しないと exec format error になり task が安定しない。
  # DOCKER_PLATFORM が未指定なら task definition の runtimePlatform.cpuArchitecture から推定する。
  if [ -z "${DOCKER_PLATFORM:-}" ]; then
    task_def="$(ecs_service_task_definition 2>/dev/null || true)"
    task_arch=""
    if [ -n "$task_def" ] && [ "$task_def" != "None" ]; then
      task_arch="$(ecs_aws ecs describe-task-definition \
        --task-definition "$task_def" \
        --query 'taskDefinition.runtimePlatform.cpuArchitecture' \
        --output text 2>/dev/null || true)"
    fi
    case "$task_arch" in
      ARM64)
        DOCKER_PLATFORM="linux/arm64"
        ecs_log "detected Fargate task arch ARM64 -> DOCKER_PLATFORM=$DOCKER_PLATFORM"
        ;;
      X86_64)
        DOCKER_PLATFORM="linux/amd64"
        ecs_log "detected Fargate task arch X86_64 -> DOCKER_PLATFORM=$DOCKER_PLATFORM"
        ;;
      *)
        ecs_log "WARN: could not determine Fargate task arch. build host arch must match the task arch (mismatch -> exec format error, task never stable). Proceeding without forcing --platform."
        ;;
    esac
    PLATFORM_ARG="${DOCKER_PLATFORM:+--platform $DOCKER_PLATFORM}"
  fi

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
