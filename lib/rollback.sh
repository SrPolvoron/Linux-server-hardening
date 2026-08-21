#!/usr/bin/env bash

latest_deployment() {
  local root="${BACKUP_ROOT:-/etc/server-hardening/backups}"
  [[ -d "$root" ]] || return 1
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n1
}

safe_remove_path() {
  local path="$1"
  case "$path" in
    /etc/*|/var/log/server-hardening/*|/home/*/.ssh/authorized_keys|/.autorelabel)
      rm -rf --one-file-system -- "$path"
      ;;
    *)
      error "Rollback rehusa eliminar ruta fuera de prefijos gestionados: $path"
      return 1
      ;;
  esac
}

restore_path_entry() {
  local dep="$1" module="$2" path="$3" state="$4" rel="$5" saved
  saved="$dep/files/$module/$rel"
  if [[ "$state" == existing ]]; then
    [[ -e "$saved" || -L "$saved" ]] || { error "Backup ausente para $path"; return 1; }
    [[ -e "$path" || -L "$path" ]] && safe_remove_path "$path"
    mkdir -p "$(dirname "$path")"
    cp -a -- "$saved" "$path"
    command_exists restorecon && restorecon -RF "$path" >/dev/null 2>&1 || true
    log "Restaurado: $path"
  elif [[ "$state" == absent ]]; then
    [[ -e "$path" || -L "$path" ]] && safe_remove_path "$path" || true
    log "Eliminada ruta creada por hardening: $path"
  fi
}

restore_dir_meta_entry() {
  local path="$1" state="$2" extra="$3" mode owner uid gid
  if [[ "$state" == absent ]]; then
    [[ -d "$path" ]] && rmdir --ignore-fail-on-non-empty "$path" 2>/dev/null || true
    return 0
  fi
  [[ -d "$path" ]] || return 0
  mode="${extra%%,*}"; owner="${extra#*,}"; uid="${owner%%:*}"; gid="${owner#*:}"
  chmod "$mode" "$path"
  chown "$uid:$gid" "$path"
}

restore_service_entry() {
  local svc="$1" enabled="$2" active="$3"
  service_exists "$svc" || return 0
  case "$enabled" in
    enabled) systemctl unmask "$svc" >/dev/null 2>&1 || true; systemctl enable "$svc" >/dev/null 2>&1 || true ;;
    disabled) systemctl unmask "$svc" >/dev/null 2>&1 || true; systemctl disable "$svc" >/dev/null 2>&1 || true ;;
    masked) systemctl mask "$svc" >/dev/null 2>&1 || true ;;
  esac
  case "$active" in
    active) systemctl start "$svc" >/dev/null 2>&1 || true ;;
    inactive|failed) systemctl stop "$svc" >/dev/null 2>&1 || true; systemctl reset-failed "$svc" >/dev/null 2>&1 || true ;;
  esac
}

restore_groupmem_entry() {
  local key state user group
  key="$1"; state="$2"; user="${key%%:*}"; group="${key#*:}"
  id "$user" >/dev/null 2>&1 || return 0
  getent group "$group" >/dev/null 2>&1 || return 0
  if [[ "$state" == yes ]]; then
    usermod -aG "$group" "$user"
  else
    gpasswd -d "$user" "$group" >/dev/null 2>&1 || true
  fi
}

selinux_port_key_exists() {
  local key="$1" type proto port
  IFS=: read -r type proto port <<< "$key"
  command_exists semanage || return 1
  semanage port -l 2>/dev/null | awk -v t="$type" -v p="$proto" -v n="$port" '$1==t && $2==p {for(i=3;i<=NF;i++) if($i==n || $i ~ ("(^|,)" n "(,|$)")) found=1} END{exit found?0:1}'
}

restore_selinux_port_entry() {
  local key="$1" state="$2" type proto port
  IFS=: read -r type proto port <<< "$key"
  command_exists semanage || return 0
  if [[ "$state" == absent ]]; then
    selinux_port_key_exists "$key" && semanage port -d -t "$type" -p "$proto" "$port" >/dev/null 2>&1 || true
  elif [[ "$state" == existing ]] && ! selinux_port_key_exists "$key"; then
    semanage port -a -t "$type" -p "$proto" "$port" >/dev/null 2>&1 || semanage port -m -t "$type" -p "$proto" "$port" >/dev/null 2>&1 || true
  fi
}

restore_selinux_mode_entry() {
  local runtime="$1" persistent="$2"
  if [[ -f /etc/selinux/config && -n "$persistent" && "$persistent" != unknown ]]; then
    if grep -qE '^SELINUX=' /etc/selinux/config; then sed -i "s/^SELINUX=.*/SELINUX=$persistent/" /etc/selinux/config
    else printf 'SELINUX=%s\n' "$persistent" >> /etc/selinux/config
    fi
  fi
  case "$runtime" in
    Enforcing) setenforce 1 >/dev/null 2>&1 || true ;;
    Permissive) setenforce 0 >/dev/null 2>&1 || true ;;
  esac
}

validate_post_rollback() {
  local failed=0
  if command_exists sshd; then
    if sshd -t; then
      service_exists "${SSH_SERVICE:-sshd}" && systemctl reload-or-restart "${SSH_SERVICE:-sshd}" >/dev/null 2>&1 || true
    else
      fail "sshd -t fallo tras rollback"; failed=1
    fi
  fi
  if command_exists logrotate && ! logrotate -d /etc/logrotate.conf >/dev/null 2>&1; then fail "logrotate invalido tras rollback"; failed=1; fi
  if command_exists fail2ban-client; then
    if fail2ban-client -t >/dev/null 2>&1; then
      service_exists fail2ban && [[ "$(service_active_state fail2ban)" == active ]] && systemctl restart fail2ban >/dev/null 2>&1 || true
    else
      fail "fail2ban invalido tras rollback"; failed=1
    fi
  fi
  if [[ -f /etc/sysctl.d/99-server-hardening.conf ]] && ! sysctl --system >/dev/null 2>&1; then fail "sysctl fallo tras rollback"; failed=1; fi
  return "$failed"
}

checkpoint_manifest_has() {
  local manifest="$1" kind="$2" module="$3" key="$4"
  [[ -f "$manifest" ]] && awk -F '\t' -v k="$kind" -v m="$module" -v p="$key" '$1==k && $2==m && $3==p {found=1} END{exit found?0:1}' "$manifest"
}

checkpoint_add() {
  local manifest="$1" kind="$2" module="$3" key="$4" state="$5" extra="${6:-}"
  checkpoint_manifest_has "$manifest" "$kind" "$module" "$key" && return 0
  printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$module" "$key" "$state" "$extra" >> "$manifest"
}

create_pre_rollback_checkpoint() {
  local source_dep="$1" source_manifest="$2" module_filter="$3" checkpoint manifest kind module key state extra rel saved mode owner user group current
  checkpoint="$source_dep/pre-rollback-$(date -u +%Y%m%d_%H%M%S)"
  manifest="$checkpoint/manifest.tsv"
  mkdir -p "$checkpoint/files"
  chmod 0700 "$checkpoint" "$checkpoint/files"
  touch "$manifest"
  chmod 0600 "$manifest"

  while IFS=$'\t' read -r kind module key state extra; do
    [[ -n "$module_filter" && "$module" != "$module_filter" ]] && continue
    case "$kind" in
      PATH)
        rel="${key#/}"; saved="$checkpoint/files/$module/$rel"
        if [[ -e "$key" || -L "$key" ]]; then
          mkdir -p "$(dirname "$saved")"; cp -a -- "$key" "$saved"
          checkpoint_add "$manifest" PATH "$module" "$key" existing "$rel"
        else
          checkpoint_add "$manifest" PATH "$module" "$key" absent "$rel"
        fi
        ;;
      DIR_META)
        if [[ -d "$key" ]]; then
          mode="$(stat -c '%a' "$key")"; owner="$(stat -c '%u:%g' "$key")"
          checkpoint_add "$manifest" DIR_META "$module" "$key" existing "$mode,$owner"
        else
          checkpoint_add "$manifest" DIR_META "$module" "$key" absent ""
        fi
        ;;
      SERVICE)
        checkpoint_add "$manifest" SERVICE "$module" "$key" "$(service_enabled_state "$key")" "$(service_active_state "$key")"
        ;;
      GROUPMEM)
        user="${key%%:*}"; group="${key#*:}"; current=no
        if id "$user" >/dev/null 2>&1 && id -nG "$user" | awk -v g="$group" '{for(i=1;i<=NF;i++) if($i==g) found=1} END{exit found?0:1}'; then current=yes; fi
        checkpoint_add "$manifest" GROUPMEM "$module" "$key" "$current" ""
        ;;
      SELINUX_PORT)
        current=absent; selinux_port_key_exists "$key" && current=existing
        checkpoint_add "$manifest" SELINUX_PORT "$module" "$key" "$current" ""
        ;;
      SELINUX_MODE)
        checkpoint_add "$manifest" SELINUX_MODE "$module" selinux "$(getenforce 2>/dev/null || echo Unavailable)" "$(awk -F= '/^SELINUX=/{print $2}' /etc/selinux/config 2>/dev/null || echo unknown)"
        ;;
    esac
  done < "$source_manifest"

  printf '%s\n' "$checkpoint"
}

restore_manifest() {
  local dep="$1" manifest="$2" module_filter="${3:-}" kind module key state extra

  while IFS=$'\t' read -r kind module key state extra; do
    [[ "$kind" == PATH ]] || continue
    [[ -n "$module_filter" && "$module" != "$module_filter" ]] && continue
    restore_path_entry "$dep" "$module" "$key" "$state" "$extra"
  done < <(tac "$manifest")

  while IFS=$'\t' read -r kind module key state extra; do
    [[ "$kind" == DIR_META ]] || continue
    [[ -n "$module_filter" && "$module" != "$module_filter" ]] && continue
    restore_dir_meta_entry "$key" "$state" "$extra"
  done < <(tac "$manifest")

  while IFS=$'\t' read -r kind module key state extra; do
    [[ -n "$module_filter" && "$module" != "$module_filter" ]] && continue
    case "$kind" in
      GROUPMEM) restore_groupmem_entry "$key" "$state" ;;
      SELINUX_PORT) restore_selinux_port_entry "$key" "$state" ;;
      SELINUX_MODE) restore_selinux_mode_entry "$state" "$extra" ;;
    esac
  done < <(tac "$manifest")

  while IFS=$'\t' read -r kind module key state extra; do
    [[ "$kind" == SERVICE ]] || continue
    [[ -n "$module_filter" && "$module" != "$module_filter" ]] && continue
    restore_service_entry "$key" "$state" "$extra"
  done < <(tac "$manifest")
}

rollback_deployment() {
  local selector="${1:-latest}" module_filter="${2:-}" id dep manifest checkpoint
  if [[ "$selector" == latest ]]; then id="$(latest_deployment)" || { error "No hay deployments"; return 1; }
  else id="$selector"; fi
  dep="${BACKUP_ROOT:-/etc/server-hardening/backups}/$id"
  manifest="$dep/manifest.tsv"
  [[ -f "$manifest" ]] || { error "Deployment sin manifest: $dep"; return 1; }

  echo "Deployment: $id"
  [[ -n "$module_filter" ]] && echo "Modulo: $module_filter"
  awk -F '\t' -v m="$module_filter" 'm=="" || $2==m {printf "  %-13s %-12s %s (%s)\n",$1,$2,$3,$4}' "$manifest"
  confirm "¿Aplicar rollback?" || { warn "Rollback cancelado."; return 0; }

  checkpoint="$(create_pre_rollback_checkpoint "$dep" "$manifest" "$module_filter")" || return 1
  log "Checkpoint pre-rollback: $checkpoint"

  if ! restore_manifest "$dep" "$manifest" "$module_filter"; then
    error "Fallo durante la restauracion; recuperando checkpoint pre-rollback."
    restore_manifest "$checkpoint" "$checkpoint/manifest.tsv" "" || true
    return 1
  fi

  if validate_post_rollback; then
    pass "Rollback validado desde $id${module_filter:+ modulo $module_filter}."
    return 0
  fi

  error "La validacion posterior al rollback fallo. Restaurando estado pre-rollback."
  restore_manifest "$checkpoint" "$checkpoint/manifest.tsv" "" || {
    error "Tambien fallo la recuperacion automatica. Checkpoint: $checkpoint"
    return 1
  }
  validate_post_rollback || warn "El estado previo se restauro, pero alguna validacion sigue fallando."
  error "Rollback abortado y estado previo recuperado desde $checkpoint"
  return 1
}
