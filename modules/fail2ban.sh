#!/usr/bin/env bash

FAIL2BAN_JAIL=/etc/fail2ban/jail.d/99-server-hardening.local

fail2ban_action() {
  if command_exists firewall-cmd && [[ "$(service_active_state firewalld)" == active ]] && [[ -f /etc/fail2ban/action.d/firewallcmd-rich-rules.conf ]]; then echo firewallcmd-rich-rules
  elif command_exists nft && [[ -f /etc/fail2ban/action.d/nftables-multiport.conf ]]; then echo nftables-multiport
  elif command_exists iptables && [[ -f /etc/fail2ban/action.d/iptables-multiport.conf ]]; then echo iptables-multiport
  else return 1
  fi
}

module_fail2ban_audit() {
  command_exists fail2ban-client || { warn "Fail2ban no instalado"; return 0; }
  fail2ban-client -t >/dev/null 2>&1 && pass "Configuracion Fail2ban valida" || fail "Configuracion Fail2ban invalida"
  fail2ban-client status || true
  fail2ban-client status sshd || warn "Jail sshd no activa"
  [[ -f "$FAIL2BAN_JAIL" ]] && grep -E '^(enabled|port|backend|banaction|maxretry|findtime|bantime)[[:space:]]*=' "$FAIL2BAN_JAIL" || true
}

module_fail2ban_apply() {
  [[ "${ENABLE_FAIL2BAN:-yes}" == yes ]] || { warn "Fail2ban deshabilitado por configuracion"; return 0; }
  if [[ "$MODE" == plan ]]; then
    [[ "$DISTRO_FAMILY" == rhel && "${ALLOW_REPO_ENABLE:-no}" != yes ]] && warn "Fail2ban puede requerir EPEL; no se habilitara automaticamente."
    ensure_package fail2ban yes
    log "Configurar jail sshd port=$SSH_PORT backend=systemd y seleccionar banaction disponible"
    return 0
  fi
  if ! package_available fail2ban; then ensure_epel_if_allowed || return 1; fi
  ensure_package fail2ban yes
  ensure_dir_tracked /etc/fail2ban/jail.d 0755
  backup_path "$FAIL2BAN_JAIL"
  local action; action="$(fail2ban_action)" || { error "No se encuentra backend de bloqueo firewalld/nftables/iptables"; return 1; }
  [[ "$MODE" == plan ]] && { log "Configurar jail sshd con action=$action"; return 0; }
  cat > "$FAIL2BAN_JAIL" <<EOF
[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
banaction = $action
maxretry = 5
findtime = 10m
bantime = 1h
EOF
  fail2ban-client -t >/dev/null || { error "fail2ban-client -t fallo"; return 1; }
  state_record_service fail2ban
  systemctl enable --now fail2ban
  systemctl restart fail2ban
  fail2ban-client status sshd >/dev/null || { error "Jail sshd no quedo activa"; return 1; }
}
