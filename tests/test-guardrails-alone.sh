#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-guardrails-alone.sh
err=$(mktemp)
trap 'rm -f "$err"' EXIT

pass() {
  if ! "$check" "$@" >/dev/null 2>"$err"; then
    printf 'expected pass:' >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    cat "$err" >&2
    exit 1
  fi
}

fail() {
  local needle=$1
  shift
  local err
  err=$(mktemp)
  if "$check" "$@" >/dev/null 2>"$err"; then
    printf 'expected fail:' >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    rm -f "$err"
    exit 1
  fi
  if ! grep -q "$needle" "$err"; then
    printf 'failure did not mention %s:\n' "$needle" >&2
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  if ! grep -q 'guardrail changes ride alone' "$err"; then
    printf 'failure should say guardrail changes ride alone\n' >&2
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  rm -f "$err"
}

pass
pass src/app.ts README.md tests/test-guardrails-alone.sh
pass .github/workflows/hygiene.yml
pass .github/workflows/nested/ci.yml
pass scripts/check-secrets.sh
pass scripts/check-guardrails-alone.sh policy/secret-allowlist .github/workflows/hygiene.yml
pass policy/dir/name

fail src/app.ts .github/workflows/hygiene.yml src/app.ts
fail README.md policy/secret-allowlist README.md
fail tests/test-one-pr.sh scripts/check-one-pr.sh tests/test-one-pr.sh

# scripts/binah-install and scripts/lib are not guardrail paths.
pass scripts/binah-install scripts/lib/wire-hygiene.py

if "$check" scripts/check-secrets.sh scripts/lib/wire-hygiene.py >/dev/null 2>"$err"; then
  printf 'a check script plus another script should fail\n' >&2
  exit 1
fi
if ! grep -q 'scripts/lib/wire-hygiene.py' "$err"; then
  printf 'mixed failure should name the other path\n' >&2
  cat "$err" >&2
  exit 1
fi

printf 'guardrails alone ok\n'
