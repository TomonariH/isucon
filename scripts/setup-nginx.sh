#!/bin/bash
# ISUCON nginx LTSV アクセスログ設定
# nginx が動いているサーバーで実行する。nginx がなければ何もしない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

log() { echo "[setup-nginx] $*"; }

if [ ! -f "/etc/nginx/nginx.conf" ]; then
  log "nginx not found, skipping"
  exit 0
fi

if grep -rE '^\s*log_format\s+ltsv' /etc/nginx/ &>/dev/null; then
  log "nginx LTSV already configured"
  exit 0
fi

log "Setting up nginx LTSV access log..."
sudo cp "$REPO_DIR/templates/nginx-ltsv.conf" /etc/nginx/conf.d/ltsv.conf
sudo nginx -t && sudo systemctl reload nginx
log "nginx LTSV log enabled"
