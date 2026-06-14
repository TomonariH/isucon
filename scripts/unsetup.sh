#!/bin/bash
# setup.sh の変更をすべて元に戻す
set -euo pipefail

log() { echo "[unsetup] $*"; }

log "=== ISUCON unsetup start ==="

# alp 削除
if [ -f /usr/local/bin/alp ]; then
  sudo rm /usr/local/bin/alp
  log "Removed /usr/local/bin/alp"
else
  log "alp not found, skipping"
fi

# percona-toolkit 削除
if command -v pt-query-digest &>/dev/null; then
  sudo apt-get remove -y percona-toolkit
  log "Removed percona-toolkit"
else
  log "percona-toolkit not found, skipping"
fi

# nginx LTSV 設定削除
if [ -f /etc/nginx/conf.d/ltsv.conf ]; then
  sudo rm /etc/nginx/conf.d/ltsv.conf
  sudo nginx -t && sudo systemctl reload nginx
  log "Removed nginx ltsv.conf and reloaded"
else
  log "nginx ltsv.conf not found, skipping"
fi

# MySQL スロークエリ設定削除
if [ -f /etc/mysql/conf.d/slow-query.cnf ]; then
  sudo rm /etc/mysql/conf.d/slow-query.cnf
  # 動的に無効化（再起動不要）
  sudo mysql -e "SET GLOBAL slow_query_log = 0;" 2>/dev/null \
    || sudo systemctl restart mysql
  log "Removed mysql slow-query.cnf and disabled slow query log"
else
  log "mysql slow-query.cnf not found, skipping"
fi

log "=== ISUCON unsetup done ==="
