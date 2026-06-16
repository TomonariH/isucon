#!/bin/bash
# SQS queue に benchmark request を送信する。BENCH_CMD から呼ぶ。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

QUEUE_URL="${BENCH_QUEUE_URL:-${SQS_QUEUE_URL:-}}"
TARGET_URL="${BENCH_TARGET_URL:-}"
FRONTEND_URL="${FRONTEND_ALB_URL:-}"
MESSAGE_BODY="${BENCH_MESSAGE_BODY:-}"
MESSAGE_FILE="${BENCH_MESSAGE_FILE:-}"
OUT="${BENCH_SQS_OUT:-$TOOL_REPO/reports/.runtime/ecs-bench-sqs-response.json}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/bench-sqs.sh [--dry-run]

Environment:
  BENCH_QUEUE_URL       SQS queue URL. If empty, BENCH_QUEUE_NAME is resolved with aws sqs get-queue-url.
  BENCH_QUEUE_NAME      SQS queue name.
  BENCH_TARGET_URL      benchmark target URL. If empty, backend ALB settings are resolved.
  BACKEND_ALB_* / FRONTEND_ALB_* see scripts/ecs/resolve-alb-url.sh.
  BENCH_MESSAGE_BODY    message body template.
  BENCH_MESSAGE_FILE    file containing message body template.
  BENCH_SQS_OUT         response output path, default: reports/.runtime/ecs-bench-sqs-response.json
  SQS_MESSAGE_GROUP_ID  optional for FIFO queues.
  SQS_MESSAGE_DEDUPLICATION_ID optional for FIFO queues.

Placeholders:
  {{BENCH_TARGET_URL}}, {{BACKEND_ALB_URL}}, {{FRONTEND_ALB_URL}}, {{BENCH_QUEUE_URL}}
  JSON escaped variants: {{BENCH_TARGET_URL_JSON}}, {{BACKEND_ALB_URL_JSON}}, {{FRONTEND_ALB_URL_JSON}}, {{BENCH_QUEUE_URL_JSON}}
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
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

mkdir -p "$(dirname "$OUT")"

if [ -z "$QUEUE_URL" ]; then
  QUEUE_URL="$(ecs_sqs_queue_url)"
fi
if [ -z "$TARGET_URL" ]; then
  TARGET_URL="$(ecs_alb_url_for backend)"
fi
if [ -z "$FRONTEND_URL" ] && {
  [ -n "${FRONTEND_ALB_DNS_NAME:-}" ] || [ -n "${FRONTEND_ALB_ARN:-}" ] || [ -n "${FRONTEND_ALB_NAME:-}" ]
}; then
  FRONTEND_URL="$(ecs_alb_url_for frontend)"
fi

if [ -n "$MESSAGE_FILE" ]; then
  [ -f "$MESSAGE_FILE" ] || {
    echo "[ecs] ERROR: BENCH_MESSAGE_FILE not found: $MESSAGE_FILE" >&2
    exit 1
  }
  MESSAGE_BODY="$(sed -n '1,$p' "$MESSAGE_FILE")"
fi
if [ -z "$MESSAGE_BODY" ]; then
  MESSAGE_BODY='{"target_url":"{{BENCH_TARGET_URL}}"}'
fi

target_json="$(printf '%s' "$TARGET_URL" | ecs_json_escape)"
frontend_json="$(printf '%s' "$FRONTEND_URL" | ecs_json_escape)"
queue_json="$(printf '%s' "$QUEUE_URL" | ecs_json_escape)"

MESSAGE_BODY="${MESSAGE_BODY//\{\{BENCH_TARGET_URL_JSON\}\}/$target_json}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{BACKEND_ALB_URL_JSON\}\}/$target_json}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{FRONTEND_ALB_URL_JSON\}\}/$frontend_json}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{BENCH_QUEUE_URL_JSON\}\}/$queue_json}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{BENCH_TARGET_URL\}\}/$TARGET_URL}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{BACKEND_ALB_URL\}\}/$TARGET_URL}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{FRONTEND_ALB_URL\}\}/$FRONTEND_URL}"
MESSAGE_BODY="${MESSAGE_BODY//\{\{BENCH_QUEUE_URL\}\}/$QUEUE_URL}"

if [ "$DRY_RUN" = "1" ]; then
  echo "[ecs] dry-run benchmark request"
  echo "queue_url=$QUEUE_URL"
  echo "target_url=$TARGET_URL"
  echo "frontend_url=$FRONTEND_URL"
  echo "message_body=$MESSAGE_BODY"
  exit 0
fi

ecs_require_cmd aws
args=(sqs send-message --queue-url "$QUEUE_URL" --message-body "$MESSAGE_BODY")
if [ -n "${SQS_MESSAGE_GROUP_ID:-}" ]; then
  args+=(--message-group-id "$SQS_MESSAGE_GROUP_ID")
fi
if [ -n "${SQS_MESSAGE_DEDUPLICATION_ID:-}" ]; then
  args+=(--message-deduplication-id "$SQS_MESSAGE_DEDUPLICATION_ID")
fi

ecs_log "send benchmark request: queue=$QUEUE_URL target=$TARGET_URL"
ecs_aws "${args[@]}" --output json > "$OUT"
ecs_log "wrote: $OUT"
cat "$OUT"
