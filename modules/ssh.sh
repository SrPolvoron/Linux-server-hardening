#!/usr/bin/env bash

ssh_dropin=/etc/ssh/sshd_config.d/00-server-hardening.conf

ssh_effective_value() {
  local key="$1" user="${2:-}" host addr
  host="$(hostname 2>/dev/null || echo localhost)"; addr=127.0.0.1
  if [[ -n "$user" ]]; then
    sshd -T -C "user=$user,host=$host,addr=$addr" 2>/dev/null | awk -v k="$key" '$1==k && !found {print $2; found=1} END{exit found?0:1}'
  else
    sshd -T 2>/dev/null | awk -v k="$key" '$1==k && !found {print $2; found=1} END{exit found?0:1}'
  fi
}

ensure_sshd_include() {
  local main=/etc/ssh/sshd_config managed_include='Include /etc/ssh/sshd_config.d/00-server-hardening.conf'
  local first_directive
  first_directive="$(awk '!/^[[:space:]]*(#|$)/ && !found {print; found=1} END{exit found?0:1}' "$main" 2>/dev/null || true)"
  [[ "$first_directive" == "$managed_include" ]] && return 0

  backup_path "$main"
  if [[ "$MODE" == plan ]]; then
    log "Insertar Include explicito del hardening como primera directiva global de $main"
    return 0
  fi

  local tmp has_wildcard=no; tmp="$(mktemp)"
  grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)' "$main" && has_wildcard=yes
  {
    printf '%s\n' "$managed_include"
    [[ "$has_wildcard" == no ]] && printf 'Include /etc/ssh/sshd_config.d/*.conf\n'
    awk '!/^[[:space:]]*Include[[:space:]]+\/etc\/ssh\/sshd_config\.d\/00-server-hardening\.conf([[:space:]]|$)/ {print}' "$main"
  } > "$tmp"
  cat "$tmp" > "$main"
  rm -f "$tmp"
}


admin_has_key() {
  [[ -n "${ADMIN_USER:-}" ]] || return 1
  local home sshdir auth mode
  home="$(user_home "$ADMIN_USER" 2>/dev/null || true)"
  [[ -n "$home" ]] || return 1
  sshdir="$home/.ssh"; auth="$sshdir/authorized_keys"
  [[ -d "$sshdir" && -s "$auth" ]] || return 1

  mode="$(stat -c '%a' "$sshdir" 2>/dev/null || echo 777)"
  (( (8#$mode & 022) == 0 )) || return 1
  mode="$(stat -c '%a' "$auth" 2>/dev/null || echo 777)"
  (( (8#$mode & 022) == 0 )) || return 1

  if command_exists ssh-keygen; then
    ssh-keygen -lf "$auth" >/dev/null 2>&1 || return 1
  fi
  return 0
}

ssh_validate_effective() {
  local failed=0 key expected actual
  while IFS='=' read -r key expected; do
    actual="$(ssh_effective_value "$key" 2>/dev/null || echo unknown)"
    [[ "$actual" == "$expected" ]] || { error "SSH efectivo $key=$actual esperado=$expected"; failed=1; }
  done <<EOF
port=$SSH_PORT
logingracetime=$SSH_LOGIN_GRACE_TIME
maxauthtries=$SSH_MAX_AUTH_TRIES
clientaliveinterval=$SSH_CLIENT_ALIVE_INTERVAL
clientalivecountmax=$SSH_CLIENT_ALIVE_COUNT_MAX
pubkeyauthentication=yes
banner=/etc/issue.net
EOF

  if [[ -n "${ADMIN_USER:-}" ]]; then
    actual="$(ssh_effective_value passwordauthentication "$ADMIN_USER" 2>/dev/null || echo unknown)"
    [[ "$actual" == "$SSH_PASSWORD_AUTH" ]] || { error "PasswordAuthentication efectivo para $ADMIN_USER=$actual esperado=$SSH_PASSWORD_AUTH"; failed=1; }
    actual="$(ssh_effective_value kbdinteractiveauthentication "$ADMIN_USER" 2>/dev/null || echo unknown)"
    [[ "$actual" == no ]] || { error "KbdInteractiveAuthentication efectivo para $ADMIN_USER=$actual esperado=no"; failed=1; }
  fi
  actual="$(ssh_effective_value permitrootlogin root 2>/dev/null || echo unknown)"
  [[ "$actual" == "$SSH_ROOT_LOGIN" ]] || { error "PermitRootLogin efectivo=$actual esperado=$SSH_ROOT_LOGIN"; failed=1; }
  return "$failed"
}


module_ssh_audit() {
  command_exists sshd || { fail "sshd no instalado"; return 1; }
  sshd -t || { fail "Configuracion SSH invalida"; return 1; }
  local keys=(port logingracetime maxauthtries clientaliveinterval clientalivecountmax permitrootlogin pubkeyauthentication passwordauthentication kbdinteractiveauthentication banner)
  local k; for k in "${keys[@]}"; do printf '%-30s %s\n' "$k" "$(ssh_effective_value "$k" || echo unknown)"; done
  [[ "$(ssh_effective_value port || true)" == "$SSH_PORT" ]] && pass "Puerto SSH efectivo $SSH_PORT" || warn "Puerto SSH efectivo distinto de $SSH_PORT"
}

module_ssh_apply() {
  ensure_package openssh-server yes
  if [[ "$DISTRO_FAMILY" == rhel ]]; then
    selinux_ensure_tools
    selinux_prepare_ssh_port
  fi
  if [[ "${SSH_PASSWORD_AUTH:-no}" == no ]] && ! admin_has_key; then
    error "Se rehusa desactivar PasswordAuthentication: ADMIN_USER no tiene authorized_keys utilizable."
    return 1
  fi
  ensure_dir_tracked /etc/ssh/sshd_config.d 0755
  ensure_sshd_include
  backup_path "$ssh_dropin"
  if [[ "$MODE" == plan ]]; then log "Escribir hardening SSH en $ssh_dropin"; return 0; fi

  cat > "$ssh_dropin" <<EOF
# Managed by server-hardening
Port $SSH_PORT
PermitRootLogin $SSH_ROOT_LOGIN
PubkeyAuthentication yes
PasswordAuthentication $SSH_PASSWORD_AUTH
KbdInteractiveAuthentication no
PermitEmptyPasswords no
IgnoreRhosts yes
HostbasedAuthentication no
X11Forwarding no
MaxAuthTries $SSH_MAX_AUTH_TRIES
LoginGraceTime $SSH_LOGIN_GRACE_TIME
ClientAliveInterval $SSH_CLIENT_ALIVE_INTERVAL
ClientAliveCountMax $SSH_CLIENT_ALIVE_COUNT_MAX
Banner /etc/issue.net
EOF
  chmod 0644 "$ssh_dropin"
  if ! sshd -t; then
    error "sshd -t fallo; no se recarga SSH."
    return 1
  fi
  state_record_service "$SSH_SERVICE"
  service_reload_or_restart "$SSH_SERVICE"
  sshd -t
  ssh_validate_effective || { error "La configuracion efectiva SSH no coincide con la politica esperada."; return 1; }
  pass "SSH aplicado y validado. Verifica una segunda sesion antes de cerrar la actual."
}
