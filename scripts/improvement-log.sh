#!/bin/bash
# Record candidate extraction, branch evaluation, and cleanup decisions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${IMPROVEMENT_LOG:-$REPO_DIR/reports/improvement-loop.md}"

[ -f "$SCRIPT_DIR/env.sh" ] && source "$SCRIPT_DIR/env.sh"
APP_REPO="${APP_REPO:-}"
if [ -z "$APP_REPO" ] && [ -n "${ISUCON_WEBAPP_DIR:-}" ]; then
  APP_REPO="$(dirname "$ISUCON_WEBAPP_DIR")"
fi
APP_REPO="${APP_REPO:-$REPO_DIR}"

usage() {
  cat <<'EOF'
Usage:
  scripts/improvement-log.sh candidate <id> <impact> <difficulty> <branch> <summary>
  scripts/improvement-log.sh eval <id> <branch> <score> <pass> <decision> <note>
  scripts/improvement-log.sh cleanup <branch> <worktree> <decision> <note>

Examples:
  scripts/improvement-log.sh candidate C1 high low feature/cache-user "cache user lookup"
  scripts/improvement-log.sh eval C1 feature/cache-user 12345 true merged "improved baseline"
  scripts/improvement-log.sh cleanup feature/cache-user /tmp/wt kept "left for audit"
EOF
}

init_file() {
  if [ ! -s "$LOG_FILE" ]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    cat > "$LOG_FILE" <<'EOF'
# ISUCON Improvement Loop Log

## Candidates

| Time | ID | Impact | Difficulty | Branch | App Commit | Summary |
|------|----|--------|------------|--------|------------|---------|

## Evaluations

| Time | ID | Branch | Score | Pass | Decision | App Commit | Note |
|------|----|--------|-------|------|----------|------------|------|

## Worktree Cleanup

| Time | Branch | Worktree | Decision | Note |
|------|--------|----------|----------|------|
EOF
  fi
}

escape_cell() {
  printf '%s' "$1" | sed 's/|/\\|/g'
}

append_after_heading() {
  local heading="$1"
  local line="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v heading="$heading" -v line="$line" '
    $0 == heading { in_section=1; print; next }
    in_section == 1 && /^\|[-| ]+\|$/ { print; print line; in_section=0; next }
    { print }
  ' "$LOG_FILE" > "$tmp"
  mv "$tmp" "$LOG_FILE"
}

cmd="${1:-}"
if [ -z "$cmd" ] || [ "$cmd" = "-h" ] || [ "$cmd" = "--help" ]; then
  usage
  exit 0
fi
shift

init_file
timestamp="$(date +%Y-%m-%d\ %H:%M:%S)"
app_commit="$(git -C "$APP_REPO" rev-parse --short HEAD 2>/dev/null || echo 'N/A')"

case "$cmd" in
  candidate)
    [ "$#" -ge 5 ] || { usage >&2; exit 2; }
    id="$(escape_cell "$1")"
    impact="$(escape_cell "$2")"
    difficulty="$(escape_cell "$3")"
    branch="$(escape_cell "$4")"
    shift 4
    summary="$(escape_cell "$*")"
    append_after_heading "## Candidates" "| $timestamp | $id | $impact | $difficulty | $branch | $app_commit | $summary |"
    ;;
  eval)
    [ "$#" -ge 6 ] || { usage >&2; exit 2; }
    id="$(escape_cell "$1")"
    branch="$(escape_cell "$2")"
    score="$(escape_cell "$3")"
    pass="$(escape_cell "$4")"
    decision="$(escape_cell "$5")"
    shift 5
    note="$(escape_cell "$*")"
    append_after_heading "## Evaluations" "| $timestamp | $id | $branch | $score | $pass | $decision | $app_commit | $note |"
    ;;
  cleanup)
    [ "$#" -ge 4 ] || { usage >&2; exit 2; }
    branch="$(escape_cell "$1")"
    worktree="$(escape_cell "$2")"
    decision="$(escape_cell "$3")"
    shift 3
    note="$(escape_cell "$*")"
    append_after_heading "## Worktree Cleanup" "| $timestamp | $branch | $worktree | $decision | $note |"
    ;;
  *)
    echo "[improvement-log] unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac

echo "[improvement-log] updated: $LOG_FILE"
