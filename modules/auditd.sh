#!/usr/bin/env bash

AUDIT_RULES_FILE=/etc/audit/rules.d/50-server-hardening.rules
AUDITD_CONF=/etc/audit/auditd.conf

audit_arches() {
  case "$(uname -m)" in
    x86_64) printf '%s\n' b64 b32 ;;
    aarch64|ppc64le|s390x) printf '%s\n' b64 ;;
    *) printf '%s\n' b64 ;;
  esac
}

write_audit_rule() {
  local arch="$1" kind="$2" path="$3" key="$4"
  printf -- '-a always,exit -F arch=%s -F %s=%s -F perm=wa -k %s\n' "$arch" "$kind" "$path" "$key"
}

set_audit_conf_key() {
  local key="$1" value="$2" file="$AUDITD_CONF"
  if grep -Eq "^[[:space:]]*$key[[:space:]]*=" "$file"; then
    sed -ri "s|^[[:space:]]*$key[[:space:]]*=.*|$key = $value|" "$file"
  else
    printf '%s = %s\n' "$key" "$value" >> "$file"
  fi
}

module_auditd_audit() {
  command_exists auditctl || { fail "auditd no instalado"; return 1; }
  auditctl -s || true
  echo "Reglas hardening:"; [[ -f "$AUDIT_RULES_FILE" ]] && cat "$AUDIT_RULES_FILE" || echo "No configuradas"
  grep -E '^(max_log_file|num_logs|max_log_file_action|space_left|space_left_action|admin_space_left|admin_space_left_action|disk_full_action|disk_error_action)[[:space:]]*=' "$AUDITD_CONF" 2>/dev/null || true
}

module_auditd_apply() {
  if [[ "$DISTRO_FAMILY" == debian ]]; then ensure_package auditd yes; else ensure_package audit yes; fi
  backup_path "$AUDIT_RULES_FILE"; backup_path "$AUDITD_CONF"
  ensure_dir_tracked /etc/audit/rules.d 0750
  [[ "$MODE" == plan ]] && { log "Configurar auditd y reglas modernas"; return 0; }

  : > "$AUDIT_RULES_FILE"
  printf '# Managed by server-hardening\n' >> "$AUDIT_RULES_FILE"
  local arch
  while read -r arch; do
    write_audit_rule "$arch" path /etc/passwd identity >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" path /etc/group identity >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" path /etc/shadow identity >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" path /etc/gshadow identity >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" path /etc/sudoers privilege >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" dir /etc/sudoers.d privilege >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" dir /etc/ssh ssh_config >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" dir /etc/audit audit_config >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" dir /etc/systemd systemd_config >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" path /etc/hostname system_identity >> "$AUDIT_RULES_FILE"
    write_audit_rule "$arch" path /etc/hosts system_identity >> "$AUDIT_RULES_FILE"
  done < <(audit_arches)
  chmod 0640 "$AUDIT_RULES_FILE"

  set_audit_conf_key max_log_file "$AUDIT_MAX_LOG_FILE_MB"
  set_audit_conf_key num_logs "$AUDIT_NUM_LOGS"
  set_audit_conf_key max_log_file_action ROTATE
  set_audit_conf_key space_left "$AUDIT_SPACE_LEFT"
  set_audit_conf_key space_left_action "$AUDIT_SPACE_LEFT_ACTION"
  set_audit_conf_key admin_space_left "$AUDIT_ADMIN_SPACE_LEFT"
  set_audit_conf_key admin_space_left_action "$AUDIT_ADMIN_SPACE_LEFT_ACTION"
  set_audit_conf_key disk_full_action "$AUDIT_DISK_FULL_ACTION"
  set_audit_conf_key disk_error_action "$AUDIT_DISK_ERROR_ACTION"

  state_record_service "$AUDIT_SERVICE"
  systemctl enable "$AUDIT_SERVICE" >/dev/null 2>&1 || true
  if [[ "$(service_active_state "$AUDIT_SERVICE")" != active ]]; then
    if command_exists service; then service "$AUDIT_SERVICE" start
    else systemctl start "$AUDIT_SERVICE"
    fi
  fi

  local audit_enabled
  audit_enabled="$(auditctl -s 2>/dev/null | awk '$1=="enabled"{print $2}')"
  if [[ "$audit_enabled" == 2 ]]; then
    warn "Audit rules are immutable (enabled=2); new rules/config are staged for next boot."
  else
    augenrules --load
    if command_exists service; then
      service "$AUDIT_SERVICE" reload >/dev/null 2>&1 || warn "No se pudo recargar auditd.conf en caliente; aplicar en siguiente reinicio."
    fi
  fi
  auditctl -s | awk '$1=="enabled" && ($2=="1" || $2=="2"){found=1} END{exit found?0:1}' || { error "auditd no quedo habilitado"; return 1; }
}
