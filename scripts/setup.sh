#!/bin/bash
# ISUCON 初動セットアップ（1台構成用ラッパー）
# nginx / MySQL / アプリが同一サーバーの場合に使う。
#
# コンポーネントが別サーバーに分かれている場合は個別スクリプトを使う:
#   setup-tools.sh  — alp / pt-query-digest（分析実行サーバー）
#   setup-nginx.sh  — nginx LTSV ログ（nginx サーバー）
#   setup-mysql.sh  — MySQL スロークエリログ（DB サーバー）
#   setup-app.sh    — git init / reports ディレクトリ（アプリサーバー）
#
# MySQL が RDS / Aurora の場合は setup-rds.sh を使う。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[setup] $*"; }

log "=== ISUCON setup start ==="
bash "$SCRIPT_DIR/setup-tools.sh"
bash "$SCRIPT_DIR/setup-nginx.sh"
bash "$SCRIPT_DIR/setup-mysql.sh"
bash "$SCRIPT_DIR/setup-app.sh"
log "=== ISUCON setup done ==="
log ""
log "Next steps:"
log "  1. Run benchmark"
log "  2. bash scripts/analyze.sh"
log "  3. /isucon-analyze"
