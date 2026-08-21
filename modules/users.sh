#!/usr/bin/env bash

module_users_audit() {
  [[ -n "${ADMIN_USER:-}" ]] || { warn "ADMIN_USER no configurado."; return 0; }
  if ! id "$ADMIN_USER" >/dev/null 2>&1; then fail "Usuario admin inexistente: $ADMIN_USER"; return 1; fi
  id "$ADMIN_USER"
  id -nG "$ADMIN_USER" | awk -v g="$ADMIN_GROUP" '{for(i=1;i<=NF;i++) if($i==g) found=1} END{exit found?0:1}' && pass "$ADMIN_USER pertenece a $ADMIN_GROUP" || fail "$ADMIN_USER no pertenece a $ADMIN_GROUP"
  if [[ "${ADD_ADMIN_TO_DOCKER_GROUP:-yes}" == yes && -n "$(getent group docker || true)" ]]; then
    id -nG "$ADMIN_USER" | awk '{for(i=1;i<=NF;i++) if($i=="docker") found=1} END{exit found?0:1}' && pass "$ADMIN_USER pertenece a docker" || warn "$ADMIN_USER no pertenece a docker"
  fi
}

module_users_apply() {
  [[ -n "${ADMIN_USER:-}" ]] || { error "ADMIN_USER es obligatorio para apply users."; return 1; }
  state_record_user "$ADMIN_USER"
  if ! id "$ADMIN_USER" >/dev/null 2>&1; then
    run_cmd useradd -m -s /bin/bash "$ADMIN_USER"
  fi

  getent group "$ADMIN_GROUP" >/dev/null || { error "Grupo administrativo inexistente: $ADMIN_GROUP"; return 1; }
  state_record_group_membership "$ADMIN_USER" "$ADMIN_GROUP"
  run_cmd usermod -aG "$ADMIN_GROUP" "$ADMIN_USER"

  if [[ "${ADD_ADMIN_TO_DOCKER_GROUP:-yes}" == yes ]] && getent group docker >/dev/null 2>&1; then
    state_record_group_membership "$ADMIN_USER" docker
    run_cmd usermod -aG docker "$ADMIN_USER"
    warn "El grupo docker concede privilegios equivalentes a root."
  fi

  if [[ -n "${ADMIN_SSH_PUBLIC_KEY:-}" ]]; then
    local home sshdir auth
    home="$(user_home "$ADMIN_USER")"
    sshdir="$home/.ssh"; auth="$sshdir/authorized_keys"
    ensure_dir_tracked "$sshdir" 0700
    backup_path "$auth"
    touch "$auth"
    grep -qxF "$ADMIN_SSH_PUBLIC_KEY" "$auth" || printf '%s\n' "$ADMIN_SSH_PUBLIC_KEY" >> "$auth"
    chmod 0600 "$auth"
    chown -R "$ADMIN_USER:$(primary_group "$ADMIN_USER")" "$sshdir"
  fi
}
