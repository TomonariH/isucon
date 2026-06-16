#!/bin/bash
# ISUCON 分析ツールインストール
# alp と pt-query-digest を入れる。分析を実行するサーバーで実行する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
STATE_DIR="$SCRIPT_DIR/.setup-state"

log() { echo "[setup-tools] $*"; }

install_alp() {
  if command -v alp &>/dev/null; then
    log "alp already installed: $(alp --version 2>&1 | head -1)"
    return
  fi
  local arch
  arch="$(detect_arch)" || { log "ERROR: unsupported arch $(uname -m)"; return 1; }
  log "Installing alp ($arch)..."
  ALP_VERSION="1.0.21"
  curl -fsSL "https://github.com/tkuchiki/alp/releases/download/v${ALP_VERSION}/alp_linux_${arch}.tar.gz" \
    | sudo tar xz -C /usr/local/bin alp
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/alp-installed"
  log "alp installed: $(alp --version 2>&1 | head -1)"
}

install_pt_query_digest() {
  if command -v pt-query-digest &>/dev/null; then
    log "pt-query-digest already installed"
    return
  fi
  log "Installing percona-toolkit..."
  # Amazon Linux 2023 など RHEL 系では percona repo / 依存解決に失敗することがある。
  # pt-query-digest が無くても analyze.sh / analyze-rds.sh はスロークエリ解析を
  # スキップして継続するため、ここで失敗しても setup 全体を止めない。
  if { ensure_percona_repo && pkg_install percona-toolkit; } 2>/dev/null; then
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/percona-toolkit-installed"
    log "pt-query-digest installed"
  else
    log "WARNING: could not install percona-toolkit (pt-query-digest)."
    log "  analyze.sh / analyze-rds.sh はスロークエリ解析をスキップして継続します。"
  fi
}

install_dstat() {
  if command -v dstat &>/dev/null; then
    log "dstat already installed"
    return
  fi
  log "Installing dstat..."
  # Amazon Linux 2023 などでは dstat パッケージが pcp-dstat に統合されており、
  # dstat という名前のパッケージが無い。dstat → pcp-dstat の順で試す。
  # dstat は bench-locked.sh では任意（未導入ならスキップ）なので、
  # ここで失敗しても setup 全体を止めない。
  if pkg_install dstat 2>/dev/null || pkg_install pcp-dstat 2>/dev/null; then
    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/dstat-installed"
    log "dstat installed"
  else
    log "WARNING: could not install dstat (tried dstat, pcp-dstat)."
    log "  bench-locked.sh は dstat 未導入ならリソース計測をスキップして継続します。"
  fi
}

install_alp
install_pt_query_digest
install_dstat
log "Tools ready."
