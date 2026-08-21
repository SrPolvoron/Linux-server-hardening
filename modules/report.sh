#!/usr/bin/env bash

module_report_generate() {
  local root="${REPORT_ROOT:-/var/log/server-hardening}" ts report
  ts="$(date -u +%Y%m%d_%H%M%S)"; report="$root/report_$ts.txt"
  [[ "$MODE" == plan ]] && { log "Generar informe en $report"; return 0; }
  mkdir -p "$root"
  {
    echo "SERVER HARDENING REPORT"
    echo "Generated: $(date --iso-8601=seconds 2>/dev/null || date)"
    echo "Version: $(cat "$BASE_DIR/VERSION" 2>/dev/null || echo unknown)"
    echo
    echo "== DISTRIBUTION =="; printf '%s %s family=%s pm=%s\n' "$DISTRO_NAME" "$DISTRO_VERSION" "$DISTRO_FAMILY" "$PACKAGE_MANAGER"
    echo
    echo "== FAILED UNITS =="; systemctl --failed --no-pager || true
    echo
    echo "== SSH =="; sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication|maxauthtries|banner) ' || true
    echo
    echo "== AUDITD =="; auditctl -s 2>/dev/null || true
    echo
    echo "== TIME =="; timedatectl status 2>/dev/null || true; chronyc tracking 2>/dev/null || true
    echo
    echo "== MAC =="; case "$MAC_SYSTEM" in selinux) sestatus 2>/dev/null || true ;; apparmor) aa-status 2>/dev/null || true ;; esac
    echo
    echo "== FAIL2BAN =="; fail2ban-client status sshd 2>/dev/null || true
    echo
    echo "== ETCKEEPER =="; git -C /etc status --short 2>/dev/null || true; git -C /etc log -1 --oneline 2>/dev/null || true
    echo
    echo "== LOGGING =="; journalctl --disk-usage 2>/dev/null || true; systemctl is-active rsyslog 2>/dev/null || true; systemctl is-active logrotate.timer 2>/dev/null || true
    echo
    echo "== DOCKER =="; docker info --format 'LoggingDriver={{.LoggingDriver}} Swarm={{.Swarm.LocalNodeState}}' 2>/dev/null || true; docker system df 2>/dev/null || true; docker service ls 2>/dev/null || true
    echo
    echo "== LISTENING PORTS =="; ss -lntup 2>/dev/null || true
    echo
    echo "== DISK =="; df -hT -x overlay -x tmpfs -x devtmpfs
  } > "$report"
  chmod 0600 "$report"
  pass "Informe generado: $report"
}
