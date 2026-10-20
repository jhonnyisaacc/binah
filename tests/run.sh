#!/usr/bin/env bash
set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"
fail=0
for t in "$root"/tests/test-*.sh; do
  printf '== %s\n' "$(basename "$t")"
  if ! bash "$t"; then
    printf 'FAIL %s\n' "$(basename "$t")" >&2
    fail=1
  fi
done
exit "$fail"
