#!/bin/bash
# ECS deploy/benchmark を排他実行し、CloudWatch Logs の取得窓を固定する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

LOCK_FILE="${ISUCON_LOCK_FILE:-/tmp/isucon-ecs-bench.lock}"
RUN_REBUILD="${RUN_REBUILD:-0}"
RUN_ANALYZE="${RUN_ANALYZE:-0}"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/bench-locked.sh [--rebuild] [--analyze] [--no-reset-logs]

Environment:
  BENCH_CMD        benchmark command
  REBUILD_CMD      defaults to bash scripts/ecs/deploy.sh when empty
  HEALTHCHECK_CMD  optional endpoint check after ECS stable
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rebuild)
      RUN_REBUILD=1
      ;;
    --analyze)
      RUN_ANALYZE=1
      ;;
    --no-reset-logs)
      # CloudWatch Logs are fetched by timestamp, so there is no local log to reset.
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

[ -n "${BENCH_CMD:-}" ] || {
  echo "[ecs] ERROR: BENCH_CMD is required" >&2
  exit 1
}
if [ -z "${REBUILD_CMD:-}" ]; then
  REBUILD_CMD="bash $TOOL_REPO/scripts/ecs/deploy.sh"
fi

exec 9>"$LOCK_FILE"
flock 9

if [ "$RUN_REBUILD" = "1" ]; then
  eval "$REBUILD_CMD"
else
  bash "$TOOL_REPO/scripts/ecs/wait-stable.sh"
fi

BENCH_START_EPOCH="$(date +%s)"
set +e
# BENCH_CMD must block until the benchmark actually finishes so that analyze
# below sees a populated CloudWatch window (BENCH_START_EPOCH..now). The SQS
# benchmark is asynchronous, so scripts/ecs/bench-sqs.sh blocks for
# BENCH_DURATION_SEC (+ ingestion margin) after sending the request. Do not add
# a second wait here.
eval "$BENCH_CMD"
BENCH_STATUS=$?
set -e

if [ "$RUN_ANALYZE" = "1" ]; then
  BENCH_START_EPOCH="$BENCH_START_EPOCH" bash "$TOOL_REPO/scripts/ecs/analyze.sh" || true
else
  echo "[ecs] benchmark finished. Run scripts/ecs/analyze.sh before the next benchmark if --analyze was not used."
fi

exit "$BENCH_STATUS"
