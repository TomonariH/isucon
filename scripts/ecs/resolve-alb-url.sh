#!/bin/bash
# ALB name/ARN/DNS から benchmark target URL を解決する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/ecs/lib.sh
source "$SCRIPT_DIR/lib.sh"
ecs_load_env

KIND="backend"

usage() {
  cat <<'EOF'
Usage:
  scripts/ecs/resolve-alb-url.sh [--kind backend|frontend]

Environment:
  BACKEND_ALB_URL / FRONTEND_ALB_URL
  BACKEND_ALB_DNS_NAME / FRONTEND_ALB_DNS_NAME
  BACKEND_ALB_ARN / FRONTEND_ALB_ARN
  BACKEND_ALB_NAME / FRONTEND_ALB_NAME
  BACKEND_ALB_PROTOCOL / FRONTEND_ALB_PROTOCOL  default: http
  BACKEND_ALB_PORT / FRONTEND_ALB_PORT
  BACKEND_ALB_PATH / FRONTEND_ALB_PATH          default: /
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --kind)
      [ "$#" -ge 2 ] || {
        echo "[ecs] ERROR: --kind requires a value" >&2
        exit 2
      }
      KIND="$2"; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "[ecs] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$KIND" in
  backend|frontend) ;;
  *)
    echo "[ecs] ERROR: --kind must be backend or frontend: $KIND" >&2
    exit 2
    ;;
esac

ecs_alb_url_for "$KIND"
