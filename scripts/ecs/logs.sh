#!/bin/bash
# CloudWatch Logs から ECS container stdout を取得する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

KIND="nginx"
SINCE_EPOCH="${SINCE_EPOCH:-}"
OUT=""

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/logs.sh [--kind nginx|app] [--since-epoch <epoch>] [--out <path>]

Environment:
  ECS_LOG_GROUP / ECS_NGINX_LOG_GROUP / ECS_APP_LOG_GROUP
  ECS_LOG_STREAM_PREFIX / ECS_NGINX_LOG_STREAM_PREFIX / ECS_APP_LOG_STREAM_PREFIX

Defaults:
  --kind nginx
  --since-epoch now-10min
  --out reports/.runtime/ecs-<kind>.log
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kind)
      [ "$#" -ge 2 ] || {
        echo "[ecs] ERROR: --kind requires a value" >&2
        exit 2
      }
      KIND="$2"; shift
      ;;
    --since-epoch)
      [ "$#" -ge 2 ] || {
        echo "[ecs] ERROR: --since-epoch requires a value" >&2
        exit 2
      }
      SINCE_EPOCH="$2"; shift
      ;;
    --out)
      [ "$#" -ge 2 ] || {
        echo "[ecs] ERROR: --out requires a value" >&2
        exit 2
      }
      OUT="$2"; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "[ecs] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

ecs_require_cmd aws
case "$KIND" in
  nginx|app) ;;
  *)
    echo "[ecs] ERROR: --kind must be nginx or app: $KIND" >&2
    exit 2
    ;;
esac

if [ -z "$SINCE_EPOCH" ]; then
  SINCE_EPOCH="$(date -d '10 minutes ago' +%s)"
fi
if [ -z "$OUT" ]; then
  OUT="$TOOL_REPO/reports/.runtime/ecs-${KIND}.log"
fi

ecs_log "fetch logs: kind=$KIND since=$SINCE_EPOCH out=$OUT"
ecs_fetch_logs "$KIND" "$SINCE_EPOCH" "$OUT"
ecs_log "wrote: $OUT"
