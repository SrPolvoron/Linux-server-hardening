#!/usr/bin/env bash

selinux_runtime() { getenforce 2>/dev/null || echo Unavailable; }
selinux_persistent() { awk -F= '/^SELINUX=/{print $2}' /etc/selinux/config 2>/dev/null || echo unknown; }

selinux_ensure_tools() {
  ensure_package policycoreutils yes
  if ! command_exists semanage; then ensure_package policycoreutils-python-utils yes; fi
}

selinux_prepare_ssh_port() {
  local port="$SSH_PORT"
  state_record_selinux_port ssh_port_t tcp "$port"
  if [[ "$MODE" == plan ]] && ! command_exists semanage; then
    log "Registrar tcp/$port como ssh_port_t cuando semanage este disponible"
    return 0
  fi
  command_exists semanage || { error "semanage no disponible"; return 1; }
  if semanage port -l | awk -v n="$port" '$1=="ssh_port_t" && $2=="tcp" {for(i=3;i<=NF;i++) if($i==n || $i ~ ("(^|,)" n "(,|$)")) found=1} END{exit found?0:1}'; then return 0; fi
  run_cmd semanage port -a -t ssh_port_t -p tcp "$port"
}

selinux_update_policy() {
  [[ "${SELINUX_UPDATE_POLICY:-yes}" == yes ]] || return 0
  [[ "$MODE" == plan ]] && { log "Actualizar politica SELinux si hay version disponible"; return 0; }
  case "$PACKAGE_MANAGER" in
    dnf) dnf upgrade -y selinux-policy selinux-policy-targeted || warn "No se pudo actualizar selinux-policy; se continua con la version instalada." ;;
    yum) yum update -y selinux-policy selinux-policy-targeted || warn "No se pudo actualizar selinux-policy; se continua con la version instalada." ;;
  esac
  semodule -B || warn "semodule -B no pudo reconstruir la politica; revisar antes de Enforcing."
}

selinux_blocking_avc_since() {
  local since="${1:-recent}"
  command_exists ausearch || return 1
  ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -ts "$since" 2>/dev/null | awk '/permissive=0/{found=1} END{exit found?0:1}'
}

selinux_blocking_avc_recent() { selinux_blocking_avc_since recent; }

selinux_validate_active_services() {
  local svc failed=0
  for svc in "${SSH_SERVICE:-sshd}" docker auditd rsyslog fail2ban mdmonitor; do
    service_exists "$svc" || continue
    [[ "$(service_active_state "$svc")" == active ]] || continue
    systemctl is-active "$svc" >/dev/null 2>&1 || { warn "Servicio $svc dejo de estar activo durante prueba SELinux"; failed=1; }
  done
  return "$failed"
}

module_selinux_audit() {
  printf 'Runtime: %s\nPersistent: %s\n' "$(selinux_runtime)" "$(selinux_persistent)"
  sestatus 2>/dev/null || true
  command_exists semanage && semanage port -l | grep '^ssh_port_t' || true
  if selinux_blocking_avc_recent; then warn "Hay AVC recientes con permissive=0"; else pass "Sin AVC bloqueantes recientes detectados"; fi
  [[ -e /.autorelabel ]] && warn "Hay autorelabel pendiente para el proximo arranque"
}

module_selinux_apply() {
  [[ "$DISTRO_FAMILY" == rhel ]] || { warn "SELinux no aplica a esta familia"; return 0; }
  selinux_ensure_tools
  state_record_selinux_mode
  backup_path /etc/selinux/config
  selinux_prepare_ssh_port
  selinux_update_policy

  if [[ "$MODE" == plan ]] && ! command_exists getenforce; then
    log "Determinar runtime SELinux tras instalar dependencias; nunca se hara Disabled -> Enforcing directo."
    return 0
  fi

  local runtime; runtime="$(selinux_runtime)"
  if [[ "$MODE" == plan ]]; then
    case "$runtime" in
      Disabled) log "Preparar SELinux Permissive + /.autorelabel; reboot requerido" ;;
      Permissive) log "Mantener Permissive salvo opt-in de prueba Enforcing" ;;
      Enforcing) log "Mantener Enforcing y validar AVC/servicios" ;;
      *) warn "Runtime SELinux no determinable en plan: $runtime" ;;
    esac
    return 0
  fi
  case "$runtime" in
    Disabled)
      if [[ "$MODE" != plan ]]; then
        sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
        backup_path /.autorelabel
        touch /.autorelabel
      fi
      warn "SELinux estaba Disabled: preparado Permissive + autorelabel. Requiere reboot y validacion antes de Enforcing."
      ;;
    Permissive)
      if [[ "${SELINUX_TARGET_MODE:-enforcing}" == enforcing ]]; then
        if [[ "${SELINUX_AUTO_ENFORCE:-no}" == yes ]]; then
          warn "SELINUX_AUTO_ENFORCE=yes: prueba controlada Enforcing. Mantener una sesion SSH y consola de emergencia disponibles."
          if [[ "$MODE" != plan ]]; then
            local start md_was_active=no
            start="$(date '+%m/%d/%Y %H:%M:%S')"
            [[ "$(service_active_state mdmonitor)" == active ]] && md_was_active=yes
            setenforce 1
            sleep 2
            if [[ "$md_was_active" == yes ]]; then systemctl restart mdmonitor || true; sleep 2; fi
            if ! selinux_validate_active_services || selinux_blocking_avc_since "$start"; then
              setenforce 0
              error "La prueba Enforcing genero fallo/AVC; se vuelve a Permissive."
              return 1
            fi
            sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
            warn "Enforcing persistido tras checks locales. Aun debes verificar una NUEVA conexion SSH desde otro terminal."
          fi
        else
          warn "SELinux permanece Permissive. Ejecuta validacion operativa y habilita SELINUX_AUTO_ENFORCE solo tras comprobar servicios y nueva sesion SSH."
        fi
      fi
      ;;
    Enforcing)
      [[ "$MODE" == plan ]] || sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
      pass "SELinux ya esta Enforcing."
      ;;
    *) error "Estado SELinux no reconocido: $runtime"; return 1 ;;
  esac
}
