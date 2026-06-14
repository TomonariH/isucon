#!/bin/bash
# ISUCON 計測・レポート生成スクリプト
# ベンチマーク実行後に毎回実行する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="$REPO_DIR/reports/$TIMESTAMP.md"

# /isucon-survey が生成した env.sh を読む（Docker・RDS 等のログパス・接続情報を含む）
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"

# デフォルトパス（ISUCON環境に合わせて上書き可能）
MYSQL_SLOW_LOG="${MYSQL_SLOW_LOG:-/var/log/mysql/slow.log}"
ALP_CONFIG="${ALP_CONFIG:-$REPO_DIR/scripts/alp.yml}"

# H2O が存在すればそちらのログを優先、なければ nginx
_detect_access_log() {
  if [ -n "${NGINX_ACCESS_LOG:-}" ]; then
    echo "$NGINX_ACCESS_LOG"
  elif systemctl is-active --quiet h2o 2>/dev/null && [ -f /etc/h2o/h2o.conf ]; then
    echo "/var/log/h2o/access.log"
  else
    echo "/var/log/nginx/access.log"
  fi
}
ACCESS_LOG="$(_detect_access_log)"

log() { echo "[analyze] $*"; }

# ---- alp でアクセスログ解析 ----
run_alp() {
  if [ ! -f "$ACCESS_LOG" ]; then
    echo "## Access Log (alp)"
    echo ""
    echo "> Access log not found: $ACCESS_LOG"
    echo ""
    return
  fi
  if ! command -v alp &>/dev/null; then
    echo "## Access Log (alp)"
    echo ""
    echo "> alp not installed. Run scripts/setup.sh first."
    echo ""
    return
  fi

  echo "## Access Log (alp) — Top endpoints by total response time"
  echo ""
  echo '```'
  if [ -f "$ALP_CONFIG" ]; then
    sudo cat "$ACCESS_LOG" | alp ltsv --config "$ALP_CONFIG" 2>&1 || true
  else
    sudo cat "$ACCESS_LOG" | alp ltsv \
      --sort sum \
      --reverse \
      --output "count,method,uri,min,avg,max,sum" \
      --limit 20 \
      2>&1 || true
  fi
  echo '```'
  echo ""
}

# ---- pt-query-digest でスロークエリ解析 ----
run_pt_query_digest() {
  if [ ! -f "$MYSQL_SLOW_LOG" ]; then
    echo "## Slow Query Log (pt-query-digest)"
    echo ""
    echo "> Slow query log not found: $MYSQL_SLOW_LOG"
    echo ""
    return
  fi
  if ! command -v pt-query-digest &>/dev/null; then
    echo "## Slow Query Log (pt-query-digest)"
    echo ""
    echo "> pt-query-digest not installed. Run scripts/setup.sh first."
    echo ""
    return
  fi

  echo "## Slow Query Log (pt-query-digest) — Top queries by total time"
  echo ""
  echo '```'
  sudo pt-query-digest "$MYSQL_SLOW_LOG" 2>/dev/null || true
  echo '```'
  echo ""
}

# ---- ログをローテートしてリセット ----
rotate_logs() {
  if [ "${ROTATE_LOGS:-1}" = "1" ]; then
    log "Rotating logs for next benchmark..."
    if [ -f "$ACCESS_LOG" ]; then
      sudo truncate -s 0 "$ACCESS_LOG"
    fi
    if [ -f "$MYSQL_SLOW_LOG" ]; then
      sudo truncate -s 0 "$MYSQL_SLOW_LOG"
    fi
  fi
}

# ---- レポート生成 ----
generate_report() {
  {
    echo "# ISUCON Analysis Report"
    echo ""
    echo "- **Date**: $TIMESTAMP"
    echo "- **Host**: $(hostname)"
    echo "- **Git commit**: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
    echo ""

    run_alp
    run_pt_query_digest

    echo "---"
    echo ""
    echo "_Ask Claude: \`/isucon-analyze\` to get optimization suggestions based on this report._"
  } > "$REPORT_FILE"
}

# ---- Main ----
main() {
  mkdir -p "$REPO_DIR/reports"
  log "Generating report: $REPORT_FILE"
  generate_report
  rotate_logs
  log "Done: $REPORT_FILE"
  log ""
  log "Next: Run /isucon-analyze in Claude Code to get optimization suggestions"
}

main "$@"
