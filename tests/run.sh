#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/tests/test_static.sh"
"$ROOT/tests/test_distro.sh"
"$ROOT/tests/test_state.sh"
"$ROOT/tests/test_apply_rollback.sh"
echo "All tests: OK"
