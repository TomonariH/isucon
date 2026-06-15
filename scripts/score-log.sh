#!/bin/bash
# ISUCON スコア記録スクリプト
# 使い方: scripts/score-log.sh <score> [メモ]
# 例: scripts/score-log.sh 1710 "画像をファイルシステムに移動"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SCORE_FILE="${SCORE_FILE:-$REPO_DIR/reports/scores.md}"

[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"
APP_REPO="${APP_REPO:-}"
if [ -z "$APP_REPO" ] && [ -n "${ISUCON_WEBAPP_DIR:-}" ]; then
  APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"
fi
APP_REPO="${APP_REPO:-$REPO_DIR}"

SCORE="${1:-}"
NOTE="${2:-}"
NOTE="${NOTE//|/\\|}"  # Markdown テーブルのセル区切りと衝突しないようエスケープ

if [ -z "$SCORE" ]; then
  echo "Usage: $0 <score> [note]"
  exit 1
fi

TIMESTAMP="$(date +%Y-%m-%d\ %H:%M:%S)"
APP_COMMIT="$(git -C "$APP_REPO" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
TOOL_COMMIT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"

# ヘッダー初期化
if [ ! -f "$SCORE_FILE" ]; then
  mkdir -p "$(dirname "$SCORE_FILE")"
  cat > "$SCORE_FILE" << 'EOF'
# ISUCON Score Log

| Time | Score | App Commit | Tool Commit | Note |
|------|-------|------------|-------------|------|
EOF
fi

echo "| $TIMESTAMP | **$SCORE** | $APP_COMMIT | $TOOL_COMMIT | $NOTE |" >> "$SCORE_FILE"
echo "[score-log] Recorded: score=$SCORE app_commit=$APP_COMMIT tool_commit=$TOOL_COMMIT note='$NOTE'"
