#!/bin/bash
# ISUCON MySQL スロークエリログ設定（ローカル MySQL 用）
# MySQL が RDS / Aurora の場合は setup-rds.sh を使う。
# MySQL/MariaDB がなければ何もしない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"

log() { echo "[setup-mysql] $*"; }

if ! mysql_installed; then
  log "MySQL/MariaDB not installed, skipping"
  exit 0
fi

# 設定 include ディレクトリに slow-query.cnf を配置（restart フォールバック用）
MYSQL_CONF_DIR="$(detect_mysql_conf_dir)"
if [ -n "$MYSQL_CONF_DIR" ]; then
  SLOW_CNF="$MYSQL_CONF_DIR/slow-query.cnf"
  if [ ! -f "$SLOW_CNF" ]; then
    log "Writing MySQL slow query config to $SLOW_CNF..."
    sudo mkdir -p "$MYSQL_CONF_DIR"
    sudo cp "$REPO_DIR/templates/mysql-slow.cnf" "$SLOW_CNF"
  fi
else
  log "WARNING: MySQL conf.d dir not found; restart fallback will not apply config file"
  SLOW_CNF=""
fi

sudo mkdir -p /var/log/mysql
sudo touch /var/log/mysql/slow.log
sudo chown mysql:mysql /var/log/mysql/slow.log 2>/dev/null || true

mysql_err=""
if mysql_err="$(sudo mysql -e "
  SET GLOBAL slow_query_log = 1;
  SET GLOBAL slow_query_log_file = '/var/log/mysql/slow.log';
  SET GLOBAL long_query_time = 0;
" 2>&1)"; then
  log "MySQL slow query log enabled dynamically"
else
  log "Dynamic config failed: ${mysql_err:-(no error message)}"
  log "Falling back to service restart..."
  MYSQL_SVC="$(detect_mysql_service)"
  if [ -n "$MYSQL_SVC" ]; then
    sudo systemctl restart "$MYSQL_SVC" \
      || log "WARNING: restart failed — check ${SLOW_CNF:-MySQL config}"
  else
    log "WARNING: no MySQL service found for restart"
  fi
fi
log "MySQL slow query log: /var/log/mysql/slow.log"
