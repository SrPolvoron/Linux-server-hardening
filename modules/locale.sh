#!/usr/bin/env bash

locale_exists() { local t; t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/utf-8/utf8/g')"; locale -a 2>/dev/null | awk -v t="$t" '{s=tolower($0); gsub(/utf-8/,"utf8",s); if(s==t) found=1} END{exit found?0:1}'; }

module_locale_audit() {
  local configured="${LANG:-}"
  command_exists localectl && configured="$(localectl status 2>/dev/null | awk -F= '/System Locale: LANG=/{print $2}' | awk '{print $1}')"
  printf 'Configured LANG=%s\n' "${configured:-unknown}"
  locale_exists "$LOCALE_NAME" && pass "Locale $LOCALE_NAME disponible" || warn "Locale $LOCALE_NAME no disponible"
}

module_locale_apply() {
  locale_exists "$LOCALE_NAME" && return 0
  if [[ "$MODE" == plan ]]; then
    case "$DISTRO_FAMILY" in
      rhel) ensure_package glibc-langpack-en yes ;;
      debian) ensure_package locales yes ;;
    esac
    log "Generar/verificar locale $LOCALE_NAME"
    return 0
  fi
  case "$DISTRO_FAMILY" in
    rhel) ensure_package glibc-langpack-en yes ;;
    debian)
      ensure_package locales yes
      [[ "$MODE" == plan ]] || { grep -qE "^${LOCALE_NAME}[[:space:]]" /etc/locale.gen 2>/dev/null || echo "$LOCALE_NAME UTF-8" >> /etc/locale.gen; locale-gen "$LOCALE_NAME"; }
      ;;
  esac
  locale_exists "$LOCALE_NAME" || { error "Locale $LOCALE_NAME sigue sin estar disponible"; return 1; }
}
