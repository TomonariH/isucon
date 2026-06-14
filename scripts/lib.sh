#!/bin/bash
# 共通環境検出ライブラリ。各スクリプトから source して使う。
# このファイルは直接実行しない。

# CPU アーキテクチャ → alp などバイナリ名に使う文字列 (amd64 / arm64)
detect_arch() {
  case "$(uname -m)" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *) echo ""; return 1 ;;
  esac
}

# OS ファミリー: debian | rhel | unknown
detect_os_family() {
  if [ ! -f /etc/os-release ]; then
    echo "unknown"; return
  fi
  local id
  id="$(unset ID ID_LIKE; . /etc/os-release; echo "${ID_LIKE:-${ID:-}}")"
  case "$id" in
    *debian*|*ubuntu*) echo "debian" ;;
    *rhel*|*fedora*|*amzn*|*centos*) echo "rhel" ;;
    *) echo "unknown" ;;
  esac
}

# パッケージインストール（apt / dnf / yum を自動選択）
pkg_install() {
  case "$(detect_os_family)" in
    debian) sudo apt-get install -y "$@" ;;
    rhel)
      if command -v dnf &>/dev/null; then
        sudo dnf install -y "$@"
      else
        sudo yum install -y "$@"
      fi
      ;;
    *) echo "[lib] ERROR: unsupported OS — install manually: $*" >&2; return 1 ;;
  esac
}

# RHEL 系で Percona リポジトリを追加（percona-toolkit はデフォルトリポジトリにない）
ensure_percona_repo() {
  [ "$(detect_os_family)" = "debian" ] && return  # apt には標準で含まれる

  local repo_rpm="https://repo.percona.com/yum/percona-release-latest.noarch.rpm"
  if command -v dnf &>/dev/null; then
    dnf repolist 2>/dev/null | grep -q percona && return
    sudo dnf install -y "$repo_rpm"
  else
    yum repolist 2>/dev/null | grep -q percona && return
    sudo yum install -y "$repo_rpm"
  fi
}

# MySQL/MariaDB のサービス名を返す（mysql / mysqld / mariadb。なければ空文字）
detect_mysql_service() {
  local svc
  for svc in mysql mysqld mariadb; do
    if systemctl cat "${svc}.service" &>/dev/null; then
      echo "$svc"; return
    fi
  done
  echo ""
}

# MySQL の設定 include ディレクトリを返す
# Debian 系: /etc/mysql/conf.d  RHEL 系: /etc/my.cnf.d
detect_mysql_conf_dir() {
  [ -d /etc/mysql/conf.d ] && echo "/etc/mysql/conf.d" && return
  [ -d /etc/my.cnf.d ]    && echo "/etc/my.cnf.d"    && return
  # /etc/my.cnf はあるが .d がない場合（インストール直後など）
  [ -f /etc/my.cnf ]      && echo "/etc/my.cnf.d"    && return
  echo ""
}

# MySQL/MariaDB がインストールされているか判定
mysql_installed() {
  [ -d /etc/mysql ]          && return 0
  [ -f /etc/my.cnf ]         && return 0
  [ -n "$(detect_mysql_service)" ] && return 0
  return 1
}
