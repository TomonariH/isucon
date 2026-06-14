#!/bin/bash
# ISUCON アプリサーバー初期化
# git init と reports ディレクトリ作成。アプリが動いているサーバーで実行する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# /isucon-survey が生成した env.sh を読む（webapp パスなど）
[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"

log() { echo "[setup-app] $*"; }

git_cmd() {
  if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    local git_user="${SUDO_USER:-}"
    if [ -z "$git_user" ] || [ "$git_user" = "root" ]; then
      git_user="$(stat -c '%U' "$WEBAPP_DIR")"
    fi
    if [ -z "$git_user" ] || [ "$git_user" = "root" ]; then
      log "ERROR: refusing to initialize webapp git as root. Run as the webapp owner or set ISUCON_WEBAPP_DIR correctly."
      exit 1
    fi
    sudo -u "$git_user" git -C "$WEBAPP_DIR" "$@"
  else
    git -C "$WEBAPP_DIR" "$@"
  fi
}

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
git_cmd init
git_cmd add .
git_cmd -c user.name="isucon" -c user.email="isucon@isucon" \
  commit -m "initial commit (before optimization)"
log "git initialized"
