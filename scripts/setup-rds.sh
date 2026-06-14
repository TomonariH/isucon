#!/bin/bash
# ISUCON RDS 専用セットアップスクリプト
# MySQL が AWS RDS / Aurora の場合に使う。
# ツールインストール・nginx・git init は共通スクリプトに委譲する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# /isucon-survey が生成した env.sh を読む（存在すれば）
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"

log() { echo "[setup-rds] $*"; }

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-isucon}"
DB_PASS="${DB_PASS:-isucon}"
DB_NAME="${DB_NAME:-isucon}"
MYSQL_OPTS=(-h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "-p$DB_PASS")

check_rds() {
  local version_comment
  version_comment="$(mysql "${MYSQL_OPTS[@]}" -N -e "SELECT @@version_comment;" 2>/dev/null || echo '')"
  echo "$version_comment" | grep -qi "amazon\|rds\|aurora"
}

# ---- RDS スロークエリ設定 ----
# RDS では SET GLOBAL slow_query_log が使えない。
# log_output=TABLE + slow_query_log=ON はパラメータグループで設定する必要がある。
# ここでは long_query_time だけ動的に設定する（RDS でも許可されている）。
setup_rds_slowlog() {
  log "Setting up RDS slow query log..."

  local err
  if err="$(mysql "${MYSQL_OPTS[@]}" -e "SET GLOBAL long_query_time = 0;" 2>&1)"; then
    log "SET GLOBAL long_query_time = 0 OK"
  else
    log "WARNING: Could not set long_query_time: $err"
  fi

  local sq_log
  sq_log="$(mysql "${MYSQL_OPTS[@]}" -N -e "SELECT @@slow_query_log;" 2>/dev/null || echo '0')"
  if [ "$sq_log" != "1" ]; then
    log ""
    log "=========================================="
    log "  slow_query_log is OFF on this RDS."
    log "  パラメータグループで以下を設定してください:"
    log ""
    log "  slow_query_log    = 1"
    log "  long_query_time   = 0"
    log "  log_output        = TABLE  (mysql.slow_log に書き込む)"
    log ""
    log "  詳細: templates/rds-parameter-group.md"
    log "  AWS CLI で設定: bash scripts/setup-rds.sh --aws-cli"
    log "=========================================="
    return
  fi

  log "slow_query_log is ON"
  local log_output
  log_output="$(mysql "${MYSQL_OPTS[@]}" -N -e "SELECT @@log_output;" 2>/dev/null || echo '')"
  log "log_output = $log_output"
  if echo "$log_output" | grep -qi "TABLE"; then
    log "Slow queries → mysql.slow_log table → use analyze-rds.sh"
  else
    log "Slow queries → file → use analyze.sh with correct log path"
  fi
}

# ---- AWS CLI でパラメータグループを設定する（--aws-cli オプション時） ----
setup_rds_via_aws_cli() {
  command -v aws &>/dev/null || { log "ERROR: aws CLI not found. Install with: pip install awscli"; exit 1; }

  if [ -z "${RDS_INSTANCE:-}" ]; then
    log "ERROR: RDS_INSTANCE env var required"
    exit 1
  fi
  if [ -z "${RDS_PARAM_GROUP:-}" ]; then
    log "ERROR: RDS_PARAM_GROUP env var required"
    exit 1
  fi
  log "RDS_INSTANCE=$RDS_INSTANCE"
  log "RDS_PARAM_GROUP=$RDS_PARAM_GROUP"

  log "Modifying RDS parameter group: $RDS_PARAM_GROUP"
  aws rds modify-db-parameter-group \
    --db-parameter-group-name "$RDS_PARAM_GROUP" \
    --parameters \
      "ParameterName=slow_query_log,ParameterValue=1,ApplyMethod=immediate" \
      "ParameterName=long_query_time,ParameterValue=0,ApplyMethod=immediate" \
      "ParameterName=log_output,ParameterValue=TABLE,ApplyMethod=immediate"

  log "Parameter group updated. Changes may take a few minutes to apply."
  log "If not applied yet, reboot: aws rds reboot-db-instance --db-instance-identifier $RDS_INSTANCE"
}

main() {
  log "=== ISUCON RDS setup start ==="
  log "DB: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"

  if check_rds; then
    log "Detected: AWS RDS / Aurora"
  else
    log "WARNING: This does not look like RDS. For local MySQL, use setup-mysql.sh instead."
  fi

  bash "$SCRIPT_DIR/setup-tools.sh"
  bash "$SCRIPT_DIR/setup-nginx.sh"

  if [ "${1:-}" = "--aws-cli" ]; then
    setup_rds_via_aws_cli
  else
    setup_rds_slowlog
  fi

  bash "$SCRIPT_DIR/setup-app.sh"

  log "=== ISUCON RDS setup done ==="
  log ""
  log "Next steps:"
  log "  1. Run benchmark"
  log "  2. bash scripts/analyze-rds.sh"
  log "  3. /isucon-analyze"
}

main "$@"
