#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$BASE_DIR/lib/common.sh"
source "$BASE_DIR/lib/distro.sh"
source "$BASE_DIR/lib/state.sh"
source "$BASE_DIR/lib/deps.sh"
source "$BASE_DIR/lib/rollback.sh"

for f in "$BASE_DIR"/modules/*.sh; do source "$f"; done

detect_distro

MODULES=(users ssh banner auditd logging ntp sysctl locale fail2ban etckeeper docker)
[[ "$DISTRO_FAMILY" == rhel ]] && MODULES+=(selinux)
[[ "$DISTRO_FAMILY" == debian ]] && MODULES+=(apparmor)

usage() {
cat <<EOF
Usage:
  sudo ./hardening.sh audit
  sudo ./hardening.sh plan [module]
  sudo ./hardening.sh apply <module>
  sudo ./hardening.sh first-deploy
  sudo ./hardening.sh report
  sudo ./hardening.sh rollback list
  sudo ./hardening.sh rollback latest [module]
  sudo ./hardening.sh rollback <deployment-id> [module]

EOF
  printf 'Modules:'
  printf ' %s' "${MODULES[@]}"
  printf '\n'
}

module_exists() { local m="$1" x; for x in "${MODULES[@]}"; do [[ "$x" == "$m" ]] && return 0; done; return 1; }

run_module_audit() {
  local m fn
  m="$1"; fn="module_${m}_audit"
  CURRENT_MODULE="$m"
  declare -F "$fn" >/dev/null || { warn "Modulo $m no tiene audit"; return 0; }
  echo; echo "===== ${m^^} ====="; "$fn"
}

run_module_apply() {
  local m fn rc=0
  m="$1"; fn="module_${m}_apply"
  module_exists "$m" || { error "Modulo desconocido: $m"; return 1; }
  CURRENT_MODULE="$m"; init_deployment
  declare -F "$fn" >/dev/null || { error "Modulo $m no implementa apply"; return 1; }
  echo; echo "===== APPLY ${m^^} ====="

  if [[ "$MODE" == plan ]]; then
    "$fn"
    return $?
  fi

  deployment_status "$m" START
  set +e
  ( set -Eeuo pipefail; "$fn" )
  rc=$?
  set -e

  if (( rc == 0 )); then
    deployment_status "$m" OK
    return 0
  fi

  deployment_status "$m" FAIL "rc=$rc"
  error "El modulo $m fallo (rc=$rc). Restaurando automaticamente los cambios registrados de este modulo."
  if [[ -s "$MANIFEST_FILE" ]] && awk -F '	' -v m="$m" '$2==m{found=1} END{exit found?0:1}' "$MANIFEST_FILE"; then
    restore_manifest "$DEPLOYMENT_DIR" "$MANIFEST_FILE" "$m" || error "La restauracion automatica del modulo $m tambien fallo."
    validate_post_rollback || warn "El modulo $m fue restaurado, pero alguna validacion global sigue fallando."
  fi
  return "$rc"
}

cmd_audit() {
  AUDIT_MODE=1; AUDIT_FAILURES=0; AUDIT_WARNINGS=0
  echo "===== AUDIT ====="
  echo "Sistema: $DISTRO_NAME"
  echo "Familia: $DISTRO_FAMILY | Gestor: $PACKAGE_MANAGER | MAC: $MAC_SYSTEM"
  local m; for m in "${MODULES[@]}"; do run_module_audit "$m" || true; done
  echo; echo "===== AUDIT SUMMARY ====="
  echo "Failures: $AUDIT_FAILURES | Warnings: $AUDIT_WARNINGS"
  if (( AUDIT_FAILURES > 0 )); then SUPPRESS_ERR_TRAP=1; return 2; fi
}

cmd_first_deploy() {
  require_root; acquire_lock; MODE=apply; init_deployment
  local order=(users banner)
  [[ "$DISTRO_FAMILY" == rhel ]] && order+=(selinux)
  [[ "$DISTRO_FAMILY" == debian ]] && order+=(apparmor)
  order+=(ssh auditd logging ntp sysctl locale fail2ban etckeeper docker)
  local m; for m in "${order[@]}"; do run_module_apply "$m"; done
  module_report_generate
  pass "First deploy completado. Deployment ID: $DEPLOYMENT_ID"
}

main() {
  local cmd="${1:-}" arg="${2:-}" arg2="${3:-}"
  case "$cmd" in
    audit) cmd_audit ;;
    plan)
      MODE=plan
      if [[ -n "$arg" ]]; then run_module_apply "$arg"; else local m; for m in "${MODULES[@]}"; do run_module_apply "$m"; done; fi
      ;;
    apply) require_root; acquire_lock; [[ -n "$arg" ]] || { usage; return 1; }; MODE=apply; run_module_apply "$arg" ;;
    first-deploy) cmd_first_deploy ;;
    report) require_root; CURRENT_MODULE=report; module_report_generate ;;
    rollback)
      require_root; acquire_lock
      case "$arg" in
        list) module_rollback_list ;;
        latest) module_rollback_latest "$arg2" ;;
        "") usage; return 1 ;;
        *) module_rollback_id "$arg" "$arg2" ;;
      esac
      ;;
    -h|--help|help|"") usage ;;
    *) error "Comando desconocido: $cmd"; usage; return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
