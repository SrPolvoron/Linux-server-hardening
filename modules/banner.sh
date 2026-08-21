#!/usr/bin/env bash

SECURITY_BANNER='Acceso restringido a usuarios autorizados. Las actividades pueden ser registradas y auditadas.'

module_banner_audit() {
  local f
  for f in /etc/issue /etc/issue.net /etc/motd; do
    [[ -s "$f" ]] && pass "$f configurado" || warn "$f ausente o vacio"
  done
  command_exists sshd && [[ "$(ssh_effective_value banner || true)" == /etc/issue.net ]] && pass "Banner SSH efectivo" || warn "Banner SSH no efectivo"
}

module_banner_apply() {
  local f
  for f in /etc/issue /etc/issue.net /etc/motd; do
    backup_path "$f"
    [[ "$MODE" == plan ]] || printf '%s\n' "$SECURITY_BANNER" > "$f"
  done
}
