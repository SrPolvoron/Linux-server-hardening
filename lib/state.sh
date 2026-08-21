#!/usr/bin/env bash

DEPLOYMENT_DIR=""
MANIFEST_FILE=""

init_deployment() {
  DEPLOYMENT_DIR="${BACKUP_ROOT:-/etc/server-hardening/backups}/${DEPLOYMENT_ID}"
  MANIFEST_FILE="$DEPLOYMENT_DIR/manifest.tsv"
  if [[ "$MODE" == plan ]]; then return 0; fi
  mkdir -p "${BACKUP_ROOT:-/etc/server-hardening/backups}" "$DEPLOYMENT_DIR/files" "$DEPLOYMENT_DIR/state"
  chmod 0700 "${BACKUP_ROOT:-/etc/server-hardening/backups}" "$DEPLOYMENT_DIR" "$DEPLOYMENT_DIR/files" "$DEPLOYMENT_DIR/state"
  touch "$MANIFEST_FILE"
  chmod 0600 "$MANIFEST_FILE"
  if [[ ! -f "$DEPLOYMENT_DIR/metadata.conf" ]]; then
    cat > "$DEPLOYMENT_DIR/metadata.conf" <<EOF
DEPLOYMENT_ID=$DEPLOYMENT_ID
CREATED_AT=$(date --iso-8601=seconds 2>/dev/null || date)
HOSTNAME=$(hostname)
DISTRO_ID=${DISTRO_ID:-unknown}
DISTRO_VERSION=${DISTRO_VERSION:-unknown}
DISTRO_FAMILY=${DISTRO_FAMILY:-unknown}
PACKAGE_MANAGER=${PACKAGE_MANAGER:-unknown}
EOF
    chmod 0600 "$DEPLOYMENT_DIR/metadata.conf"
  fi
}

deployment_status() {
  local module="$1" status="$2" detail="${3:-}" file
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  file="$DEPLOYMENT_DIR/status.log"
  printf '%s\t%s\t%s\t%s\n' "$(date --iso-8601=seconds 2>/dev/null || date)" "$module" "$status" "$detail" >> "$file"
  chmod 0600 "$file"
}

manifest_has() {
  local kind="$1" module="$2" key="$3"
  [[ -f "$MANIFEST_FILE" ]] && awk -F '\t' -v k="$kind" -v m="$module" -v p="$key" '$1==k && $2==m && $3==p {found=1} END{exit found?0:1}' "$MANIFEST_FILE"
}

manifest_add() {
  local kind="$1" module="$2" key="$3" state="${4:-}" extra="${5:-}"
  [[ "$MODE" == plan ]] && return 0
  manifest_has "$kind" "$module" "$key" && return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$module" "$key" "$state" "$extra" >> "$MANIFEST_FILE"
}

backup_path() {
  local path="$1" module="${2:-$CURRENT_MODULE}" rel saved
  init_deployment
  rel="${path#/}"
  saved="$DEPLOYMENT_DIR/files/$module/$rel"
  if [[ "$MODE" == plan ]]; then
    [[ -e "$path" || -L "$path" ]] && log "Backup previsto: $path" || log "Registrar ruta nueva: $path"
    return 0
  fi
  manifest_has PATH "$module" "$path" && return 0
  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$(dirname "$saved")"
    cp -a -- "$path" "$saved"
    manifest_add PATH "$module" "$path" existing "$rel"
    log "Backup: $path"
  else
    manifest_add PATH "$module" "$path" absent "$rel"
  fi
}

backup_dir_metadata() {
  local path="$1" module="${2:-$CURRENT_MODULE}" mode owner
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  manifest_has DIR_META "$module" "$path" && return 0
  if [[ -d "$path" ]]; then
    mode="$(stat -c '%a' "$path")"
    owner="$(stat -c '%u:%g' "$path")"
    manifest_add DIR_META "$module" "$path" existing "$mode,$owner"
  else
    manifest_add DIR_META "$module" "$path" absent ""
  fi
}

ensure_dir_tracked() {
  local path="$1" mode="${2:-0755}" module="${3:-$CURRENT_MODULE}"
  backup_dir_metadata "$path" "$module"
  safe_mkdir "$path" "$mode"
}

state_record_service() {
  local svc="$1" module="${2:-$CURRENT_MODULE}"
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  service_exists "$svc" || return 0
  manifest_add SERVICE "$module" "$svc" "$(service_enabled_state "$svc")" "$(service_active_state "$svc")"
}

state_record_package_if_new() {
  local pkg="$1" module="${2:-$CURRENT_MODULE}"
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  if package_installed "$pkg"; then
    manifest_add PACKAGE "$module" "$pkg" existing ""
  else
    manifest_add PACKAGE "$module" "$pkg" absent ""
  fi
}

state_record_group_membership() {
  local user="$1" group="$2" module="${3:-$CURRENT_MODULE}" state=no
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  id -nG "$user" 2>/dev/null | awk -v g="$group" '{for(i=1;i<=NF;i++) if($i==g) found=1} END{exit found?0:1}' && state=yes
  manifest_add GROUPMEM "$module" "$user:$group" "$state" ""
}

state_record_user() {
  local user="$1" module="${2:-$CURRENT_MODULE}"
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  if id "$user" >/dev/null 2>&1; then manifest_add USER "$module" "$user" existing ""
  else manifest_add USER "$module" "$user" absent ""
  fi
}

state_record_selinux_port() {
  local type="$1" proto="$2" port="$3" module="${4:-$CURRENT_MODULE}" state=absent
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  if command_exists semanage && semanage port -l 2>/dev/null | awk -v t="$type" -v p="$proto" -v n="$port" '$1==t && $2==p {for(i=3;i<=NF;i++) if($i==n || $i ~ ("(^|,)" n "(,|$)")) found=1} END{exit found?0:1}'; then
    state=existing
  fi
  manifest_add SELINUX_PORT "$module" "$type:$proto:$port" "$state" ""
}

state_record_selinux_mode() {
  local module="${1:-$CURRENT_MODULE}" runtime persistent
  init_deployment
  [[ "$MODE" == plan ]] && return 0
  runtime="$(getenforce 2>/dev/null || echo unavailable)"
  persistent="$(awk -F= '/^SELINUX=/{print $2}' /etc/selinux/config 2>/dev/null || true)"
  manifest_add SELINUX_MODE "$module" selinux "$runtime" "$persistent"
}
