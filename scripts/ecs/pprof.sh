#!/bin/bash
# ECS 環境で pprof を取得する補助。URL 取得方式を正本とし、ECS Exec は手順を表示する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

PPROF_URL="${PPROF_URL:-}"
SECONDS_TO_CAPTURE="${PPROF_SECONDS:-30}"
OUT_PREFIX="${PPROF_OUT:-$TOOL_REPO/reports/pprof-$(date +%Y%m%d-%H%M%S)}"

usage() {
  cat <<'EOF'
Usage:
  PPROF_URL=http://<reachable-host>:6060/debug/pprof/profile scripts/ecs/pprof.sh

Environment:
  PPROF_URL       full pprof profile URL. If empty, this script prints ECS Exec guidance.
  PPROF_SECONDS   profile seconds, default: 30
  PPROF_OUT       output prefix, default: reports/pprof-<timestamp>
EOF
}

case "${1:-}" in
  -h|--help)
    usage; exit 0
    ;;
esac

mkdir -p "$TOOL_REPO/reports"
if [ -z "$PPROF_URL" ]; then
  task="$(ecs_latest_task_arn 2>/dev/null || true)"
  cat <<EOF
[ecs-pprof] PPROF_URL is empty.

Preferred options:
1. ECS Exec into the app container and curl localhost:6060 from inside the task.
2. Temporarily allow access from the workstation/bastion to the task IP pprof port.
3. Add a temporary internal route/proxy for pprof and remove it in Phase 6.

Candidate ECS Exec command:
aws ecs execute-command \\
  --cluster "${ECS_CLUSTER:-<cluster>}" \\
  --task "${task:-<task-arn>}" \\
  --container "${ECS_APP_CONTAINER:-<app-container>}" \\
  --interactive \\
  --command "sh"

Then run inside the container:
curl -s "http://127.0.0.1:6060/debug/pprof/profile?seconds=$SECONDS_TO_CAPTURE" > /tmp/profile.pprof
EOF
  exit 0
fi

url="$PPROF_URL"
case "$url" in
  *seconds=*) ;;
  *\?*) url="${url}&seconds=$SECONDS_TO_CAPTURE" ;;
  *) url="${url}?seconds=$SECONDS_TO_CAPTURE" ;;
esac

ecs_require_cmd curl go
ecs_log "capturing pprof: $url"
curl -fsS "$url" -o "${OUT_PREFIX}.pprof"
go tool pprof -top "${OUT_PREFIX}.pprof" > "${OUT_PREFIX}-top.txt"
echo "--- cum ---" >> "${OUT_PREFIX}-top.txt"
go tool pprof -top -cum "${OUT_PREFIX}.pprof" >> "${OUT_PREFIX}-top.txt"
ecs_log "wrote: ${OUT_PREFIX}.pprof and ${OUT_PREFIX}-top.txt"
