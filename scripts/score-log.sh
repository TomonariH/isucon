#!/bin/bash
# ISUCON スコア記録スクリプト
# 使い方: scripts/score-log.sh <score> [メモ]
# 例: scripts/score-log.sh 1710 "画像をファイルシステムに移動"
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SCORE_FILE="$REPO_DIR/reports/scores.md"

SCORE="${1:-}"
NOTE="${2:-}"
NOTE="${NOTE//|/\\|}"  # Markdown テーブルのセル区切りと衝突しないようエスケープ

if [ -z "$SCORE" ]; then
  echo "Usage: $0 <score> [note]"
  exit 1
fi

TIMESTAMP="$(date +%Y-%m-%d\ %H:%M:%S)"
COMMIT="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"

# ヘッダー初期化
if [ ! -f "$SCORE_FILE" ]; then
  mkdir -p "$(dirname "$SCORE_FILE")"
  cat > "$SCORE_FILE" << 'EOF'
# ISUCON Score Log

| Time | Score | Commit | Note |
|------|-------|--------|------|
EOF
fi

echo "| $TIMESTAMP | **$SCORE** | $COMMIT | $NOTE |" >> "$SCORE_FILE"
echo "[score-log] Recorded: score=$SCORE note='$NOTE'"
