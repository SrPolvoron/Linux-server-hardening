#!/usr/bin/env bash

module_apparmor_audit() {
  command_exists aa-status || { warn "apparmor-utils no instalado"; return 0; }
  aa-status || true
}

module_apparmor_apply() {
  [[ "$DISTRO_FAMILY" == debian ]] || { warn "AppArmor no aplica a esta familia"; return 0; }
  ensure_package apparmor yes
  ensure_package apparmor-utils yes
  state_record_service apparmor
  run_cmd systemctl enable --now apparmor
  [[ "$MODE" == plan ]] || aa-status >/dev/null || { error "AppArmor no esta operativo"; return 1; }
  pass "AppArmor activo. No se generan perfiles automaticamente."
}
