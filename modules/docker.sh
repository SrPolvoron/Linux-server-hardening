#!/usr/bin/env bash

json_bool() { [[ "$1" == true ]] && echo true || echo false; }

docker_running_containers() {
  docker ps -q 2>/dev/null | awk 'NF{n++} END{print n+0}'
}

docker_validate_daemon_json() {
  jq empty "$DOCKER_DAEMON_JSON" >/dev/null 2>&1 || return 1
  if command_exists dockerd; then dockerd --validate --config-file "$DOCKER_DAEMON_JSON" >/dev/null 2>&1 || return 1; fi
}

docker_daemon_flag_conflict() {
  local execstart
  execstart="$(systemctl show docker -p ExecStart --value 2>/dev/null || true)"
  [[ "$execstart" == *"--log-driver"* || "$execstart" == *"--log-opt"* ]]
}

module_docker_audit() {
  command_exists docker || { log "Docker no instalado"; return 0; }
  docker info --format 'LoggingDriver={{.LoggingDriver}} Swarm={{.Swarm.LocalNodeState}}' 2>/dev/null || true
  [[ -f "$DOCKER_DAEMON_JSON" ]] && jq . "$DOCKER_DAEMON_JSON" || warn "$DOCKER_DAEMON_JSON no existe"
  docker ps --format '{{.ID}} {{.Names}} {{.Status}}' || true
  docker service ls 2>/dev/null || true
  docker system df 2>/dev/null || true
  local id name driver maxsize maxfile daemon_driver
  daemon_driver="$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || echo unknown)"
  while read -r id; do
    [[ -n "$id" ]] || continue
    name="$(docker inspect -f '{{.Name}}' "$id" | sed 's#^/##')"
    driver="$(docker inspect -f '{{.HostConfig.LogConfig.Type}}' "$id")"
    [[ -z "$driver" || "$driver" == '<no value>' ]] && driver="$daemon_driver"
    maxsize="$(docker inspect -f '{{index .HostConfig.LogConfig.Config "max-size"}}' "$id")"
    maxfile="$(docker inspect -f '{{index .HostConfig.LogConfig.Config "max-file"}}' "$id")"
    [[ "$maxsize" == '<no value>' ]] && maxsize=''
    [[ "$maxfile" == '<no value>' ]] && maxfile=''
    [[ "$driver" == json-file && -z "$maxsize" ]] && warn "Contenedor $name usa json-file sin max-size efectivo"
    printf '%s driver=%s max-size=%s max-file=%s\n' "$name" "$driver" "${maxsize:-default}" "${maxfile:-default}"
  done < <(docker ps -q)
}

module_docker_apply() {
  [[ "${DOCKER_MANAGE_LOGGING:-yes}" == yes ]] || return 0
  command_exists docker || { log "Docker no instalado; modulo omitido"; return 0; }
  ensure_package jq yes
  if docker_daemon_flag_conflict; then
    error "Docker arranca con --log-driver/--log-opt en ExecStart; daemon.json entraria en conflicto con flags. Ajusta primero el unit/drop-in."
    return 1
  fi
  ensure_dir_tracked /etc/docker 0755
  backup_path "$DOCKER_DAEMON_JSON"

  local current_driver=""
  if [[ -f "$DOCKER_DAEMON_JSON" ]]; then
    jq empty "$DOCKER_DAEMON_JSON" >/dev/null 2>&1 || { error "$DOCKER_DAEMON_JSON contiene JSON invalido"; return 1; }
    current_driver="$(jq -r '."log-driver" // empty' "$DOCKER_DAEMON_JSON")"
  fi
  if [[ -n "$current_driver" && "$current_driver" != "$DOCKER_LOG_DRIVER" && "${DOCKER_FORCE_LOG_DRIVER:-no}" != yes ]]; then
    warn "Docker usa log-driver=$current_driver. No se sobrescribe sin DOCKER_FORCE_LOG_DRIVER=yes."
    return 0
  fi
  [[ "$MODE" == plan ]] && { log "Fusionar limites de logging en $DOCKER_DAEMON_JSON"; return 0; }

  local tmp; tmp="$(mktemp)"
  if [[ -f "$DOCKER_DAEMON_JSON" ]]; then cat "$DOCKER_DAEMON_JSON" > "$tmp"; else echo '{}' > "$tmp"; fi
  jq --arg driver "$DOCKER_LOG_DRIVER" --arg size "$DOCKER_LOG_MAX_SIZE" --arg file "$DOCKER_LOG_MAX_FILE" --argjson compress "$(json_bool "$DOCKER_LOG_COMPRESS")" '
    . + {"log-driver":$driver} |
    .["log-opts"] = ((.["log-opts"] // {}) + {"max-size":$size,"max-file":$file,"compress":($compress|tostring)})
  ' "$tmp" > "$DOCKER_DAEMON_JSON"
  rm -f "$tmp"
  chmod 0644 "$DOCKER_DAEMON_JSON"
  docker_validate_daemon_json || { error "Configuracion Docker invalida; no se reinicia Docker"; return 1; }

  local running; running="$(docker_running_containers)"
  case "${DOCKER_RESTART_ON_APPLY:-auto}" in
    yes) state_record_service docker; systemctl restart docker ;;
    no) warn "Docker no se reinicia. Los defaults se aplicaran tras el proximo restart y recreacion de contenedores." ;;
    auto)
      if (( running == 0 )); then state_record_service docker; systemctl restart docker
      else warn "Hay $running contenedores activos: no se reinicia Docker automaticamente."; fi
      ;;
  esac
  warn "Los contenedores existentes conservan su LogConfig hasta ser recreados."
}
