#!/usr/bin/env bash

module_rollback_latest() { rollback_deployment latest "${1:-}"; }
module_rollback_id() { rollback_deployment "$1" "${2:-}"; }
module_rollback_list() {
  local root="${BACKUP_ROOT:-/etc/server-hardening/backups}"
  [[ -d "$root" ]] || return 0
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}
