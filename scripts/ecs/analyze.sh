#!/bin/bash
# ECS + RDS 環境向けレポート生成。nginx stdout は CloudWatch Logs から取得する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$TOOL_REPO/reports/$TIMESTAMP.md"
RUNTIME_DIR="${ISUCON_RUNTIME_DIR:-$TOOL_REPO/reports/.runtime}"
ALP_CONFIG="${ALP_CONFIG:-$TOOL_REPO/scripts/alp.yml}"
ECS_NGINX_LOG="$RUNTIME_DIR/ecs-nginx.log"
BENCH_START_EPOCH="${BENCH_START_EPOCH:-}"
SLOW_REPORT="$RUNTIME_DIR/rds-analysis-$TIMESTAMP.md"

log() { echo "[ecs-analyze] $*"; }

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/analyze.sh

Environment:
  BENCH_START_EPOCH  fetch CloudWatch logs since this epoch, default: now-10min
  ECS_*_LOG_GROUP    CloudWatch Logs group settings used by scripts/ecs/logs.sh
  DB_TYPE            rds|aurora to include RDS slow query analysis
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ -z "$BENCH_START_EPOCH" ]; then
  BENCH_START_EPOCH="$(date -d '10 minutes ago' +%s)"
fi

run_alp() {
  echo "## Access Log (alp from ECS nginx stdout)"
  echo ""
  if [ ! -s "$ECS_NGINX_LOG" ]; then
    echo "> ECS nginx log not found or empty: $ECS_NGINX_LOG"
    echo ""
    return
  fi
  if ! command -v alp >/dev/null 2>&1; then
    echo "> alp not installed. Run scripts/setup-tools.sh on the workstation."
    echo ""
    return
  fi
  echo '```'
  if [ -f "$ALP_CONFIG" ]; then
    alp ltsv --config "$ALP_CONFIG" < "$ECS_NGINX_LOG" 2>&1 || true
  else
    alp ltsv --sort sum --reverse --output "count,method,uri,min,avg,max,sum,p99" --limit 30 < "$ECS_NGINX_LOG" 2>&1 || true
  fi
  echo '```'
  echo ""
}

run_rds() {
  local rds_slow_log_minutes
  echo "## Slow Query Log (RDS)"
  echo ""
  if [ "${DB_TYPE:-}" != "rds" ] && [ "${DB_TYPE:-}" != "aurora" ]; then
    echo "> DB_TYPE is not rds/aurora; skipping analyze-rds.sh."
    echo ""
    return
  fi
  rds_slow_log_minutes="${SLOW_LOG_MINUTES:-}"
  if [ -z "$rds_slow_log_minutes" ] && [[ "$BENCH_START_EPOCH" =~ ^[0-9]+$ ]]; then
    rds_slow_log_minutes=$(( ( $(date +%s) - BENCH_START_EPOCH + 59 ) / 60 ))
    [ "$rds_slow_log_minutes" -gt 0 ] || rds_slow_log_minutes=1
  fi
  if REPORT_FILE="$SLOW_REPORT" ROTATE_LOGS=0 SLOW_LOG_MINUTES="${rds_slow_log_minutes:-60}" bash "$TOOL_REPO/scripts/analyze-rds.sh" > "$SLOW_REPORT.stdout" 2>&1; then
    sed -n '/## Slow Query Log/,$p' "$SLOW_REPORT" || true
  else
    cat "$SLOW_REPORT.stdout"
  fi
  echo ""
}

main() {
  mkdir -p "$TOOL_REPO/reports" "$RUNTIME_DIR"
  log "fetching nginx stdout from CloudWatch Logs"
  bash "$SCRIPT_DIR/logs.sh" --kind nginx --since-epoch "$BENCH_START_EPOCH" --out "$ECS_NGINX_LOG" || true

  log "generating report: $REPORT_FILE"
  {
    echo "# ISUCON ECS Analysis Report"
    echo ""
    echo "- **Date**: $TIMESTAMP"
    echo "- **Host**: $(hostname)"
    echo "- **ECS**: ${ECS_CLUSTER:-}/${ECS_SERVICE:-}"
    echo "- **DB**: ${DB_TYPE:-unknown} ${DB_HOST:-}"
    echo "- **Git commit**: $(git -C "$TOOL_REPO" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
    echo ""
    run_alp
    run_rds
    echo "---"
    echo ""
    echo "_Ask Claude: \`/isucon-analyze\` to get optimization suggestions based on this report._"
  } > "$REPORT_FILE"
  log "done: $REPORT_FILE"
}

main "$@"
