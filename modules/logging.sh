#!/usr/bin/env bash

JOURNAL_DROPIN=/etc/systemd/journald.conf.d/10-server-hardening.conf
RSYSLOG_ROTATE=/etc/logrotate.d/server-hardening-rsyslog

rsyslog_log_paths() {
  if [[ "$DISTRO_FAMILY" == rhel ]]; then
    printf '%s\n' /var/log/messages /var/log/secure /var/log/cron /var/log/maillog /var/log/spooler
  else
    printf '%s\n' /var/log/syslog /var/log/auth.log /var/log/mail.log /var/log/kern.log /var/log/daemon.log /var/log/user.log
  fi
}


find_rsyslog_logrotate_rules() {
  local f
  for f in /etc/logrotate.d/*; do
    [[ -f "$f" && "$f" != "$RSYSLOG_ROTATE" ]] || continue
    if grep -Eq '/var/log/(messages|secure|syslog|auth\.log)' "$f"; then printf '%s\n' "$f"; fi
  done
}


module_logging_audit() {
  journalctl --disk-usage 2>/dev/null || true
  grep -RHE '^(Storage|Compress|MaxRetentionSec|SystemMaxUse|SystemKeepFree|SystemMaxFileSize|RuntimeMaxUse)=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null || true
  printf 'rsyslog enabled=%s active=%s\n' "$(service_enabled_state rsyslog)" "$(service_active_state rsyslog)"
  printf 'logrotate.timer enabled=%s active=%s\n' "$(service_enabled_state logrotate.timer)" "$(service_active_state logrotate.timer)"
  logrotate -d /etc/logrotate.conf >/dev/null 2>&1 && pass "logrotate config valida" || fail "logrotate config invalida"
  local p s; while read -r p; do [[ -f "$p" ]] || continue; s="$(stat -c %s "$p")"; printf '%12s %s\n' "$s" "$p"; done < <(rsyslog_log_paths)
}

module_logging_apply() {
  ensure_package systemd yes
  ensure_package rsyslog yes
  ensure_package logrotate yes
  if [[ "$DISTRO_FAMILY" == rhel ]] && package_available rsyslog-logrotate; then ensure_package rsyslog-logrotate no || true; fi

  ensure_dir_tracked /etc/systemd/journald.conf.d 0755
  backup_path "$JOURNAL_DROPIN"
  if [[ "$MODE" != plan ]]; then
    cat > "$JOURNAL_DROPIN" <<EOF
[Journal]
Storage=persistent
Compress=yes
MaxRetentionSec=${LOG_RETENTION_DAYS}day
SystemMaxUse=$JOURNAL_SYSTEM_MAX_USE
SystemKeepFree=$JOURNAL_SYSTEM_KEEP_FREE
SystemMaxFileSize=$JOURNAL_SYSTEM_MAX_FILE_SIZE
RuntimeMaxUse=$JOURNAL_RUNTIME_MAX_USE
EOF
  fi

  if [[ "${MANAGE_RSYSLOG_ROTATION:-yes}" == yes ]]; then
    local target="$RSYSLOG_ROTATE" paths=""
    local -a existing_rules=()
    mapfile -t existing_rules < <(find_rsyslog_logrotate_rules)
    if (( ${#existing_rules[@]} > 1 )); then
      error "Se detectaron multiples reglas logrotate para rsyslog: ${existing_rules[*]}. Resolver duplicados antes de aplicar."
      return 1
    elif (( ${#existing_rules[@]} == 1 )); then
      target="${existing_rules[0]}"
    fi
    backup_path "$target"
    paths="$(rsyslog_log_paths | paste -sd' ' -)"
    if [[ "$MODE" != plan ]]; then
      cat > "$target" <<EOF
# Managed by server-hardening; original preserved in deployment backup.
$paths {
    daily
    rotate $RSYSLOG_ROTATE_DAYS
    maxsize $RSYSLOG_MAX_SIZE
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /usr/bin/systemctl kill -s HUP rsyslog.service >/dev/null 2>&1 || true
    endscript
}
EOF
      (( ${#existing_rules[@]} == 1 )) && log "Politica rsyslog gestionada sobre ${existing_rules[0]} (backup disponible)."
    fi
  fi

  [[ "$MODE" == plan ]] && return 0
  systemd-analyze cat-config systemd/journald.conf >/dev/null 2>&1 || true
  state_record_service systemd-journald
  systemctl restart systemd-journald
  journalctl --flush || true
  state_record_service rsyslog
  systemctl enable --now rsyslog
  state_record_service logrotate.timer
  systemctl enable --now logrotate.timer >/dev/null 2>&1 || true
  logrotate -d /etc/logrotate.conf >/dev/null 2>&1 || { error "logrotate invalido; no forzar rotacion"; return 1; }
  pass "Logging aplicado sin forzar rotaciones destructivas."
}
