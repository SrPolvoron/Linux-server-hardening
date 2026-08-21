#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
find "$ROOT" -type f -name '*.sh' -print0 | while IFS= read -r -d '' f; do bash -n "$f"; done
if grep -RniE '\|[[:space:]]*(head([[:space:]]|$)|grep[[:space:]].*(-q|-m))' "$ROOT" --include='*.sh'; then
  echo "Potential pipefail early-consumer pattern found" >&2
  exit 1
fi
if grep -RniE 'logrotate[[:space:]]+-f[[:space:]]+/etc/logrotate\.d/' "$ROOT" --include='*.sh'; then
  echo "Unsafe fragment force-rotation found" >&2
  exit 1
fi
echo "test_static: OK"
