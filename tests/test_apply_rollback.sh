#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "test_apply_rollback: SKIP (requires root)"
  exit 0
fi

source "$ROOT/hardening.sh"

tmp="$(mktemp -d)"
testroot="/etc/server-hardening-test-apply-$$"
trap 'rm -rf "$tmp" "$testroot"' EXIT
mkdir -p "$testroot"
printf 'original\n' > "$testroot/value.conf"

BACKUP_ROOT="$tmp/backups"
DEPLOYMENT_ID=apply-rollback
RUN_ID=apply-rollback
DEPLOYMENT_DIR=""
MANIFEST_FILE=""
MODE=apply
MODULES+=(testfail)
validate_post_rollback() { return 0; }

module_testfail_apply() {
  backup_path "$testroot/value.conf"
  printf 'changed\n' > "$testroot/value.conf"
  false
}

if run_module_apply testfail; then
  echo "failing module unexpectedly succeeded" >&2
  exit 1
fi
[[ "$(cat "$testroot/value.conf")" == original ]]
awk -F '\t' '$2=="testfail" && $3=="FAIL"{found=1} END{exit found?0:1}' "$BACKUP_ROOT/$DEPLOYMENT_ID/status.log"

echo "test_apply_rollback: OK"
