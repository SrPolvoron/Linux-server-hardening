#!/usr/bin/env bash

OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

version_ge() {
  local a="$1" b="$2"
  [[ "$(printf '%s\n%s\n' "$b" "$a" | sort -V | tail -n1)" == "$a" ]]
}

detect_distro() {
  local id like version name
  [[ -r "$OS_RELEASE_FILE" ]] || { error "No se puede leer $OS_RELEASE_FILE"; return 1; }

  id="$(. "$OS_RELEASE_FILE"; printf '%s' "${ID:-unknown}")"
  like="$(. "$OS_RELEASE_FILE"; printf '%s' "${ID_LIKE:-}")"
  version="$(. "$OS_RELEASE_FILE"; printf '%s' "${VERSION_ID:-unknown}")"
  name="$(. "$OS_RELEASE_FILE"; printf '%s' "${PRETTY_NAME:-${NAME:-unknown}}")"

  DISTRO_ID="$id"
  DISTRO_VERSION="$version"
  DISTRO_NAME="$name"

  case "$id" in
    debian|ubuntu) DISTRO_FAMILY=debian ;;
    rhel|almalinux|rocky|centos|ol) DISTRO_FAMILY=rhel ;;
    *)
      if [[ " $like " == *" debian "* ]]; then
        DISTRO_FAMILY=debian
      elif [[ " $like " == *" rhel "* || " $like " == *" fedora "* ]]; then
        DISTRO_FAMILY=rhel
      else
        DISTRO_FAMILY=unknown
      fi
      ;;
  esac

  case "$DISTRO_FAMILY" in
    debian)
      command_exists apt-get || { error "Familia Debian detectada pero apt-get no existe."; return 1; }
      PACKAGE_MANAGER=apt
      source "$BASE_DIR/config/debian.conf"
      ;;
    rhel)
      if command_exists dnf; then PACKAGE_MANAGER=dnf
      elif command_exists yum; then PACKAGE_MANAGER=yum
      else error "Familia RHEL detectada pero no existe dnf/yum."; return 1
      fi
      source "$BASE_DIR/config/rhel.conf"
      ;;
    *) error "Distribucion no soportada: $DISTRO_NAME"; return 1 ;;
  esac

  export DISTRO_ID DISTRO_VERSION DISTRO_NAME DISTRO_FAMILY PACKAGE_MANAGER ADMIN_GROUP SSH_SERVICE AUDIT_SERVICE NTP_SERVICE MAC_SYSTEM
}
