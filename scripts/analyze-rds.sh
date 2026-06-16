#!/bin/bash
# ISUCON RDS 専用分析スクリプト
# mysql.slow_log テーブルまたは RDS ログファイルからスロークエリを取得する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="${REPORT_FILE:-$REPO_DIR/reports/$TIMESTAMP.md}"

# /isucon-survey が生成した env.sh を読む（RDS 接続情報・ログパスを含む）
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"

# 接続情報（環境変数で上書き可）
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-isucon}"
DB_PASS="${DB_PASS:-isucon}"

# VPC 外の workstation から Aurora writer endpoint へ TCP 接続するとデフォルトでは長くハングする。
# connect-timeout を入れて速やかに fail させ、フォールバック（PI / log file download）に落とす。
MYSQL_CONNECT_TIMEOUT="${MYSQL_CONNECT_TIMEOUT:-5}"

# 配列にすることでパスワードのスペースや特殊文字に対応
MYSQL_OPTS=(-h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "-p$DB_PASS" --connect-timeout="$MYSQL_CONNECT_TIMEOUT")

ALP_CONFIG="${ALP_CONFIG:-$REPO_DIR/scripts/alp.yml}"
SLOW_LOG_MINUTES="${SLOW_LOG_MINUTES:-60}"
if ! [[ "$SLOW_LOG_MINUTES" =~ ^[0-9]+$ ]]; then
  echo "[analyze-rds] ERROR: SLOW_LOG_MINUTES must be an integer" >&2
  exit 1
fi

log() { echo "[analyze-rds] $*"; }

# H2O が存在すればそちらのログを優先、なければ nginx（analyze.sh と同じ検出ロジック）
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
    echo "> alp not installed. Run scripts/setup-rds.sh first."
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
      --sort sum --reverse \
      --output "count,method,uri,min,avg,max,sum" \
      --limit 20 2>&1 || true
  fi
  echo '```'
  echo ""
}

# ---- mysql.slow_log テーブルからスロークエリ取得 ----
# TABLE モードが設定されていれば 0 を返す。未設定なら 1 を返す（呼び出し元でフォールバック判断）。
run_slow_log_table() {
  command -v pt-query-digest &>/dev/null || return 1

  local log_output
  log_output="$(mysql "${MYSQL_OPTS[@]}" -N -e "SELECT @@log_output;" 2>/dev/null || echo '')"
  if ! echo "$log_output" | grep -qi "TABLE"; then
    return 1
  fi

  echo "## Slow Query Log (mysql.slow_log table) — Top queries by total time"
  echo ""
  echo '```'
  local tmp_log
  tmp_log="$(mktemp)"
  # ORDER BY なし: start_time の時系列順で全件取得し、pt-query-digest 側で集計する。
  # ORDER BY query_time DESC + 少数 LIMIT は高頻度・短時間クエリ（N+1 の典型）を除外するため使わない。
  if ! mysql "${MYSQL_OPTS[@]}" --skip-column-names -e "
    SELECT
      CONCAT(
        '# Time: ', DATE_FORMAT(start_time, '%y%m%d %H:%i:%S'), '\n',
        '# Query_time: ', TIME_TO_SEC(query_time), '  Lock_time: ', TIME_TO_SEC(lock_time),
        '  Rows_sent: ', rows_sent, '  Rows_examined: ', rows_examined, '\n',
        'SET timestamp=', UNIX_TIMESTAMP(start_time), ';\n',
        sql_text, ';\n'
      )
    FROM mysql.slow_log
    WHERE start_time >= DATE_SUB(NOW(), INTERVAL ${SLOW_LOG_MINUTES} MINUTE)
    LIMIT 10000;
  " > "$tmp_log" 2>/dev/null; then
    rm -f "$tmp_log"
    echo "> Failed to read mysql.slow_log table."
    echo '```'
    echo ""
    return 1
  fi
  if ! pt-query-digest --type=slowlog "$tmp_log" 2>/dev/null; then
    rm -f "$tmp_log"
    echo "> Failed to run pt-query-digest."
    echo '```'
    echo ""
    return 1
  fi
  rm -f "$tmp_log"
  echo '```'
  echo ""
}

# ---- AWS CLI でログファイルをダウンロードして分析 ----
run_slow_log_file_aws() {
  if ! command -v aws &>/dev/null; then
    echo "> aws CLI not found. Skipping file download approach."
    echo ""
    return
  fi

  local RDS_INSTANCE="${RDS_INSTANCE:-}"
  if [ -z "$RDS_INSTANCE" ]; then
    echo "> RDS_INSTANCE env var not set. Skipping AWS CLI log download."
    echo ""
    return
  fi

  echo "## Slow Query Log (RDS log file via AWS CLI)"
  echo ""
  local TMP_LOG="/tmp/rds-slowquery-$TIMESTAMP.log"
  if aws rds download-db-log-file-portion \
    --db-instance-identifier "$RDS_INSTANCE" \
    --log-file-name "slowquery/mysql-slowquery.log" \
    --output text > "$TMP_LOG" 2>/dev/null && [ -s "$TMP_LOG" ]; then
    echo '```'
    pt-query-digest "$TMP_LOG" 2>/dev/null || true
    echo '```'
    rm -f "$TMP_LOG"
  else
    echo "> Failed to download RDS slow query log."
    echo "> Ensure RDS_INSTANCE is correct and log_output includes FILE."
    echo "> Aurora に到達できない場合は Performance Insights（ECS では scripts/ecs/analyze.sh の"
    echo "> Performance Insights セクション）でクエリを順位付けする、または aws rds download-db-log-file-portion を使う。"
    rm -f "$TMP_LOG"
  fi
  echo ""
}

# ---- ログローテート ----
rotate_logs() {
  if [ "${ROTATE_LOGS:-1}" = "1" ]; then
    log "Rotating access log..."
    if [ -f "$ACCESS_LOG" ]; then
      sudo truncate -s 0 "$ACCESS_LOG"
    fi

    # RDS の mysql.slow_log は共有されやすいため、明示指定時だけローテートする。
    if [ "${ROTATE_RDS_SLOW_LOG:-0}" = "1" ]; then
      if mysql "${MYSQL_OPTS[@]}" -e "CALL mysql.rds_rotate_slow_log;" 2>/dev/null; then
        log "mysql.slow_log rotated"
      else
        log "Could not rotate mysql.slow_log"
      fi
    else
      log "mysql.slow_log not rotated. Set ROTATE_RDS_SLOW_LOG=1 to reset it."
    fi
  fi
}

# ---- レポート生成 ----
generate_report() {
  {
    echo "# ISUCON Analysis Report (RDS)"
    echo ""
    echo "- **Date**: $TIMESTAMP"
    echo "- **Host**: $(hostname)"
    echo "- **DB**: $DB_USER@$DB_HOST:$DB_PORT"
    echo "- **Git commit**: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
    echo ""

    run_alp

    # TABLE 方式を優先。未設定の場合のみ AWS CLI 方式にフォールバック。
    if ! run_slow_log_table; then
      echo "## Slow Query Log"
      echo ""
      echo "> mysql.slow_log TABLE mode not configured, or Aurora に到達できませんでした。"
      echo "> パラメータグループで log_output=TABLE を設定してください: templates/rds-parameter-group.md"
      echo "> Aurora に到達できない（VPC 外 workstation など）場合は Performance Insights"
      echo "> （ECS では \`scripts/ecs/analyze.sh\` の Performance Insights セクション）でクエリを順位付けする、"
      echo "> または \`aws rds download-db-log-file-portion\` を使う。"
      echo "> Trying AWS CLI fallback..."
      echo ""
      run_slow_log_file_aws
    fi

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
  log "Next: Run /isucon-analyze in Claude Code"
}

main "$@"
