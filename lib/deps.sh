#!/usr/bin/env bash

package_installed() {
  local pkg="$1"
  case "$PACKAGE_MANAGER" in
    apt) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | awk '/install ok installed/{found=1} END{exit found?0:1}' ;;
    dnf|yum) rpm -q "$pkg" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

package_available() {
  local pkg="$1"
  case "$PACKAGE_MANAGER" in
    apt)
      apt-cache show "$pkg" >/dev/null 2>&1
      ;;
    dnf)
      dnf -q list --available "$pkg" >/dev/null 2>&1 || dnf -q list --installed "$pkg" >/dev/null 2>&1
      ;;
    yum)
      yum -q list available "$pkg" >/dev/null 2>&1 || yum -q list installed "$pkg" >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

refresh_package_metadata() {
  [[ "${PKG_METADATA_REFRESHED:-0}" == 1 ]] && return 0
  case "$PACKAGE_MANAGER" in
    apt) run_cmd apt-get update ;;
    dnf) run_cmd dnf -q makecache ;;
    yum) run_cmd yum -q makecache ;;
  esac
  PKG_METADATA_REFRESHED=1
}

pkg_install() {
  local pkgs=("$@")
  ((${#pkgs[@]})) || return 0
  case "$PACKAGE_MANAGER" in
    apt)
      refresh_package_metadata
      run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
      ;;
    dnf) run_cmd dnf install -y "${pkgs[@]}" ;;
    yum) run_cmd yum install -y "${pkgs[@]}" ;;
    *) error "Gestor de paquetes no soportado: $PACKAGE_MANAGER"; return 1 ;;
  esac
}

ensure_package() {
  local pkg="$1" required="${2:-yes}"
  if package_installed "$pkg"; then return 0; fi
  if [[ "$MODE" == plan ]]; then
    [[ "$required" == yes ]] && log "Instalar dependencia requerida: $pkg" || log "Instalar dependencia opcional si esta disponible: $pkg"
    return 0
  fi
  refresh_package_metadata
  if ! package_available "$pkg"; then
    if [[ "$required" == yes ]]; then
      error "Dependencia requerida no disponible: $pkg"
      return 1
    fi
    warn "Dependencia opcional no disponible: $pkg"
    return 2
  fi
  state_record_package_if_new "$pkg"
  pkg_install "$pkg"
  package_installed "$pkg" || { error "No se pudo instalar $pkg"; return 1; }
}

ensure_epel_if_allowed() {
  [[ "$DISTRO_FAMILY" == rhel ]] || return 0
  if [[ "$MODE" == plan ]]; then
    [[ "${ALLOW_REPO_ENABLE:-no}" == yes ]] && log "Habilitar EPEL si es necesario" || warn "EPEL no se habilitara automaticamente (ALLOW_REPO_ENABLE=no)"
    return 0
  fi
  package_available fail2ban && return 0
  [[ "${ALLOW_REPO_ENABLE:-no}" == yes ]] || {
    warn "fail2ban no esta disponible. EPEL no se habilita automaticamente (ALLOW_REPO_ENABLE=no)."
    return 1
  }
  if package_available epel-release; then
    state_record_package_if_new epel-release
    pkg_install epel-release
    return 0
  fi
  error "No se encuentra epel-release en los repositorios habilitados."
  return 1
}
