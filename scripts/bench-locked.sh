#!/bin/bash
# Run rebuild/benchmark under one exclusive lock and keep benchmark logs clean.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"

LOCK_FILE="${ISUCON_LOCK_FILE:-/tmp/isucon-bench.lock}"
RESET_LOGS_BEFORE="${RESET_LOGS_BEFORE:-1}"
RUN_REBUILD="${RUN_REBUILD:-0}"
SLEEP_AFTER_REBUILD="${SLEEP_AFTER_REBUILD:-2}"

usage() {
  cat <<'EOF'
Usage:
  scripts/bench-locked.sh [--rebuild] [--no-reset-logs]

Environment:
  BENCH_CMD            benchmark command from scripts/env.sh
  REBUILD_CMD          rebuild/restart command from scripts/env.sh
  NGINX_ACCESS_LOG     access log truncated before benchmark by default
  MYSQL_SLOW_LOG       slow log truncated before benchmark by default
  ISUCON_LOCK_FILE     lock path, default: /tmp/isucon-bench.lock
  RESET_LOGS_BEFORE    1 to truncate logs before benchmark, default: 1
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rebuild)
      RUN_REBUILD=1
      ;;
    --no-reset-logs)
      RESET_LOGS_BEFORE=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[bench-locked] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "${BENCH_CMD:-}" ]; then
  echo "[bench-locked] BENCH_CMD is empty. Run /isucon-survey first." >&2
  exit 1
fi
if [ "$RUN_REBUILD" = "1" ] && [ -z "${REBUILD_CMD:-}" ]; then
  echo "[bench-locked] REBUILD_CMD is empty." >&2
  exit 1
fi

truncate_log() {
  local path="$1"
  [ -n "$path" ] || return 0
  [ -f "$path" ] || return 0
  truncate -s 0 "$path"
}

flock "$LOCK_FILE" bash -lc '
  set -euo pipefail
  [ -f "'"$SCRIPT_DIR"'/env.sh" ] && source "'"$SCRIPT_DIR"'/env.sh"

  if [ "'"$RESET_LOGS_BEFORE"'" = "1" ]; then
    [ -n "${NGINX_ACCESS_LOG:-}" ] && [ -f "$NGINX_ACCESS_LOG" ] && truncate -s 0 "$NGINX_ACCESS_LOG"
    [ -n "${MYSQL_SLOW_LOG:-}" ] && [ -f "$MYSQL_SLOW_LOG" ] && truncate -s 0 "$MYSQL_SLOW_LOG"
  fi

  if [ "'"$RUN_REBUILD"'" = "1" ]; then
    eval "$REBUILD_CMD"
    sleep "'"$SLEEP_AFTER_REBUILD"'"
  fi

  eval "$BENCH_CMD"
'

echo "[bench-locked] benchmark finished. Run scripts/analyze.sh before the next benchmark to analyze this clean log window."
