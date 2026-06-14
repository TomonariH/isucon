#!/bin/bash
# Claude Code CLI をインストールする。
# すでに claude が入っていれば何もしない。
set -euo pipefail

log() { echo "[install-claude] $*"; }

if command -v claude &>/dev/null; then
  log "claude already installed: $(claude --version 2>/dev/null | head -1)"
  exit 0
fi

if ! command -v curl &>/dev/null; then
  log "ERROR: curl is required"
  exit 1
fi

if ! command -v bash &>/dev/null; then
  log "ERROR: bash is required"
  exit 1
fi

INSTALL_URL="${CLAUDE_INSTALL_URL:-https://claude.ai/install.sh}"
TMP_INSTALL="$(mktemp)"
trap 'rm -f "$TMP_INSTALL"' EXIT

log "Downloading Claude Code installer..."
curl -fsSL "$INSTALL_URL" -o "$TMP_INSTALL"
log "Installing Claude Code..."
bash "$TMP_INSTALL"

if command -v claude &>/dev/null; then
  log "claude installed: $(claude --version 2>/dev/null | head -1)"
else
  log "ERROR: claude command not found after installation"
  exit 1
fi
