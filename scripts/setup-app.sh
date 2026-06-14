#!/bin/bash
# ISUCON アプリサーバー初期化
# git init と reports ディレクトリ作成。アプリが動いているサーバーで実行する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

log() { echo "[setup-app] $*"; }

mkdir -p "$REPO_DIR/reports"
log "reports dir ready: $REPO_DIR/reports"

WEBAPP_DIR="${ISUCON_WEBAPP_DIR:-/home/isucon/webapp}"
if [ ! -d "$WEBAPP_DIR" ]; then
  log "webapp dir not found at $WEBAPP_DIR, skipping git setup"
  log "  Set ISUCON_WEBAPP_DIR env var to override"
  exit 0
fi

if [ -d "$WEBAPP_DIR/.git" ]; then
  log "git already initialized at $WEBAPP_DIR"
  exit 0
fi

log "Initializing git at $WEBAPP_DIR..."
git -C "$WEBAPP_DIR" init
git -C "$WEBAPP_DIR" add .
git -C "$WEBAPP_DIR" -c user.name="isucon" -c user.email="isucon@isucon" \
  commit -m "initial commit (before optimization)"
log "git initialized"
