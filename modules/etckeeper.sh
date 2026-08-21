#!/usr/bin/env bash

module_etckeeper_audit() {
  command_exists etckeeper || { warn "Etckeeper no instalado"; return 0; }
  [[ -d /etc/.git ]] || { warn "Etckeeper instalado pero /etc no inicializado"; return 0; }
  git -C /etc status --short || true
  git -C /etc log -1 --oneline || true
}

module_etckeeper_apply() {
  [[ "${ENABLE_ETCKEEPER:-yes}" == yes ]] || return 0
  if ! package_available etckeeper && [[ "$DISTRO_FAMILY" == rhel ]]; then ensure_epel_if_allowed || true; fi
  ensure_package git yes
  ensure_package etckeeper no || { warn "Etckeeper no disponible; se omite"; return 0; }
  [[ "$MODE" == plan ]] && return 0
  if [[ ! -d /etc/.git ]]; then
    etckeeper init
    etckeeper commit "Initial server-hardening baseline" || true
  fi
  if [[ -f /etc/.gitignore ]]; then
    grep -qxF 'server-hardening/backups/' /etc/.gitignore || printf 'server-hardening/backups/\n' >> /etc/.gitignore
  fi
  warn "No publiques /etc/.git en remotos: contiene configuracion sensible y puede incluir claves privadas."
}
