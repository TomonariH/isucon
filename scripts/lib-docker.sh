#!/bin/bash
# Docker Compose 環境向け helper。Docker 専用処理から呼び出す。
# このファイルは直接実行しない。

detect_compose_file() {
  local compose_dir="${1:-${DOCKER_COMPOSE_DIR:-.}}"

  if [ -n "${DOCKER_COMPOSE_FILE:-}" ]; then
    [ -f "$DOCKER_COMPOSE_FILE" ] || return 1
    realpath "$DOCKER_COMPOSE_FILE"
    return 0
  fi

  if [ -f "$compose_dir/compose.yml" ]; then
    realpath "$compose_dir/compose.yml"
    return 0
  fi
  if [ -f "$compose_dir/docker-compose.yml" ]; then
    realpath "$compose_dir/docker-compose.yml"
    return 0
  fi
  return 1
}

detect_compose_dir() {
  if [ -n "${DOCKER_COMPOSE_DIR:-}" ]; then
    realpath "$DOCKER_COMPOSE_DIR"
    return 0
  fi
  if [ -n "${DOCKER_COMPOSE_FILE:-}" ] && [ -f "$DOCKER_COMPOSE_FILE" ]; then
    dirname "$(realpath "$DOCKER_COMPOSE_FILE")"
    return 0
  fi

  local dir
  for dir in "." "${ISUCON_WEBAPP_DIR:-/home/isucon/webapp}"; do
    [ -z "$dir" ] && continue
    if DOCKER_COMPOSE_FILE= detect_compose_file "$dir" >/dev/null 2>&1; then
      realpath "$dir"
      return 0
    fi
  done
  return 1
}

compose_services_for_file() {
  local compose_dir="$1"
  local compose_file="$2"
  (cd "$compose_dir" && docker compose -f "$compose_file" config --services 2>/dev/null)
}

detect_named_service() {
  local services="$1"
  local preferred="$2"
  shift 2
  local candidate svc

  if [ -n "$preferred" ] && { [ -z "$services" ] || echo "$services" | grep -Fxq "$preferred"; }; then
    echo "$preferred"
    return 0
  fi

  for candidate in "$@"; do
    if echo "$services" | grep -Fxq "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  for candidate in "$@"; do
    svc="$(echo "$services" | grep -E "$candidate" | head -1 || true)"
    if [ -n "$svc" ]; then
      echo "$svc"
      return 0
    fi
  done

  return 1
}

filter_compose_app_services() {
  local services="$1"
  local nginx_service="$2"
  local mysql_service="$3"
  local requested="${4:-}"
  local source svc

  if [ -n "$requested" ]; then
    source="$(echo "$requested" | tr ' ' '\n')"
  else
    source="$services"
  fi

  while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    case "$svc" in
      "$nginx_service"|"$mysql_service") continue ;;
      memcached|redis|*memcached*|*redis*) continue ;;
      *fluentd*|*jaeger*|*prometheus*|*grafana*|*adminer*|*redis-commander*) continue ;;
    esac
    echo "$svc"
  done <<< "$source"
}

docker_compose_env() {
  if [ -n "${DOCKER_COMPOSE_FILE_ARGS:-}" ]; then
    local -a compose_args
    eval "compose_args=($DOCKER_COMPOSE_FILE_ARGS)"
    (cd "${DOCKER_COMPOSE_DIR:-.}" && docker compose "${compose_args[@]}" "$@")
    return
  fi

  local compose_dir="${DOCKER_COMPOSE_DIR:-.}"
  local compose_file
  compose_file="$(detect_compose_file "$compose_dir")" || return 1
  (cd "$compose_dir" && docker compose -f "$compose_file" "$@")
}
