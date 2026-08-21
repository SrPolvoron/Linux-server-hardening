#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULTS_FILE="$BASE_DIR/config/defaults.conf"
LOCAL_FILE="$BASE_DIR/config/local.conf"

[[ -f "$DEFAULTS_FILE" ]] && source "$DEFAULTS_FILE"
[[ -f "$LOCAL_FILE" ]] && source "$LOCAL_FILE"

MODE="${MODE:-apply}"
DRY_RUN="${DRY_RUN:-0}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d_%H%M%S)}"
DEPLOYMENT_ID="${DEPLOYMENT_ID:-$RUN_ID}"
CURRENT_MODULE="${CURRENT_MODULE:-core}"

log()   { printf '[INFO] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; [[ "${AUDIT_MODE:-0}" == 1 ]] && AUDIT_WARNINGS=$((AUDIT_WARNINGS+1)); return 0; }
error() { printf '[ERROR] %s\n' "$*" >&2; }
pass()  { printf '[OK] %s\n' "$*"; }
fail()  { printf '[FAIL] %s\n' "$*" >&2; [[ "${AUDIT_MODE:-0}" == 1 ]] && AUDIT_FAILURES=$((AUDIT_FAILURES+1)); return 0; }

on_error() {
  local rc=$? line=${BASH_LINENO[0]:-?} cmd=${BASH_COMMAND:-?}
  [[ "${SUPPRESS_ERR_TRAP:-0}" == 1 ]] && return 0
  error "Fallo rc=$rc modulo=${CURRENT_MODULE:-unknown} linea=$line comando=$cmd"
  return "$rc"
}
trap on_error ERR

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    error "Este comando debe ejecutarse como root."
    exit 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_cmd() {
  if [[ "$MODE" == "plan" || "$DRY_RUN" == "1" ]]; then
    printf '[PLAN]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

confirm() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

service_exists() {
  systemctl list-unit-files "${1}.service" --no-legend 2>/dev/null | awk 'NF{found=1} END{exit found?0:1}'
}

service_enabled_state() {
  systemctl is-enabled "$1" 2>/dev/null || true
}

service_active_state() {
  systemctl is-active "$1" 2>/dev/null || true
}

service_reload_or_restart() {
  local svc="$1"
  service_exists "$svc" || return 1
  run_cmd systemctl reload-or-restart "$svc"
}

primary_group() { id -gn "$1"; }
user_home() { getent passwd "$1" | awk -F: '{print $6}'; }

acquire_lock() {
  local lock="${LOCK_FILE:-/run/lock/server-hardening.lock}"
  mkdir -p "$(dirname "$lock")"
  exec 9>"$lock"
  if ! flock -n 9; then
    error "Ya hay otra ejecucion de server-hardening en curso: $lock"
    exit 1
  fi
}

safe_mkdir() {
  local path="$1" mode="${2:-0755}"
  if [[ "$MODE" == "plan" ]]; then
    log "Crear/ajustar directorio $path ($mode)"
    return 0
  fi
  if [[ -d "$path" ]]; then
    chmod "$mode" "$path"
  else
    install -d -m "$mode" "$path"
  fi
}

file_mode() { stat -c '%a' "$1" 2>/dev/null || true; }
file_owner() { stat -c '%u:%g' "$1" 2>/dev/null || true; }
