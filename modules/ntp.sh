#!/usr/bin/env bash

module_ntp_audit() {
  timedatectl status 2>/dev/null || true
  command_exists chronyc && chronyc tracking || true
  command_exists chronyc && chronyc sources -v || true
}

module_ntp_apply() {
  ensure_package chrony yes
  state_record_service "$NTP_SERVICE"
  run_cmd systemctl enable --now "$NTP_SERVICE"
  [[ "$MODE" == plan ]] && return 0
  [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == yes ]] && pass "Reloj sincronizado" || warn "Chrony activo pero el reloj aun no figura sincronizado"
}
