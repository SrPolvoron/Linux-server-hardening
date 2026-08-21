#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/state.sh"
source "$ROOT/lib/rollback.sh"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "test_state: SKIP (rollback restore test requires root)"
  exit 0
fi

tmp="$(mktemp -d)"
testroot="/etc/server-hardening-test-$$"
trap 'rm -rf "$tmp" "$testroot"' EXIT
mkdir -p "$testroot"
printf 'before\n' > "$testroot/existing.conf"

BACKUP_ROOT="$tmp/backups"
DEPLOYMENT_ID=test-deployment
RUN_ID=test-deployment
MODE=apply
CURRENT_MODULE=test
DEPLOYMENT_DIR=""
MANIFEST_FILE=""

backup_path "$testroot/existing.conf"
backup_path "$testroot/new.conf"
printf 'after\n' > "$testroot/existing.conf"
printf 'new\n' > "$testroot/new.conf"

[[ "$(cat "$testroot/existing.conf")" == after ]]
restore_manifest "$BACKUP_ROOT/$DEPLOYMENT_ID" "$BACKUP_ROOT/$DEPLOYMENT_ID/manifest.tsv" test
[[ "$(cat "$testroot/existing.conf")" == before ]]
[[ ! -e "$testroot/new.conf" ]]


# Transaction test: if post-rollback validation fails, the state present just
# before rollback must be restored automatically.
DEPLOYMENT_ID=test-transaction
RUN_ID=test-transaction
CURRENT_MODULE=test
DEPLOYMENT_DIR=""
MANIFEST_FILE=""
printf 'original\n' > "$testroot/transaction.conf"
backup_path "$testroot/transaction.conf"
printf 'hardened\n' > "$testroot/transaction.conf"
validate_post_rollback() { return 1; }
if rollback_deployment test-transaction test <<< 'y'; then
  echo "rollback transaction test unexpectedly succeeded" >&2
  exit 1
fi
[[ "$(cat "$testroot/transaction.conf")" == hardened ]]

echo "test_state: OK"
