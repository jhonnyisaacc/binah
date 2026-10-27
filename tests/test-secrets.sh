#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-secrets.sh
tmp=$(mktemp -d)

if ! bash "$check" >/dev/null; then
  printf 'binah tree should pass the current-tree scan\n' >&2
  bash "$check" >&2 || true
  exit 1
fi

mkdir -p "$tmp/repo/policy" "$tmp/repo/scripts"
cp "$check" "$tmp/repo/scripts/check-secrets.sh"
cp "$root/policy/secret-allowlist" "$tmp/repo/policy/secret-allowlist"
echo 'readme' >"$tmp/repo/README"

if ! bash "$tmp/repo/scripts/check-secrets.sh"; then
  printf 'clean tree should pass\n' >&2
  exit 1
fi

token=$(printf 'ghp_%s' "$(printf 'a%.0s' {1..36})")
printf '%s\n' "$token" >"$tmp/repo/secret.txt"
if bash "$tmp/repo/scripts/check-secrets.sh" >/dev/null 2>"$tmp/err"; then
  printf 'a token in the tree should fail\n' >&2
  exit 1
fi
if ! grep -q 'secret in secret.txt' "$tmp/err"; then
  printf 'token error should name the file\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

mkdir -p "$tmp/repo/tests/fixtures" "$tmp/repo/tests/fixtures-evil"
mv "$tmp/repo/secret.txt" "$tmp/repo/tests/fixtures/token.txt"
printf 'tests/fixtures\n' >>"$tmp/repo/policy/secret-allowlist"
printf '%s\n' "$token" >"$tmp/repo/tests/fixtures-evil/token.txt"
if bash "$tmp/repo/scripts/check-secrets.sh" >/dev/null 2>"$tmp/err"; then
  printf 'allowlist prefix must not cover a sibling directory\n' >&2
  exit 1
fi
rm "$tmp/repo/tests/fixtures-evil/token.txt"
if ! bash "$tmp/repo/scripts/check-secrets.sh"; then
  printf 'allowlisted fixture should pass\n' >&2
  exit 1
fi

begin=$(printf '%s%s%s' '-----BEGIN ' 'RSA PRIVATE KEY' '-----')
printf '%s\n' "$begin" >"$tmp/repo/key.pem"
if bash "$tmp/repo/scripts/check-secrets.sh" >/dev/null 2>"$tmp/err"; then
  printf 'a private key in the tree should fail\n' >&2
  exit 1
fi
if ! grep -q 'secret in key.pem' "$tmp/err"; then
  printf 'key error should name the file\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

if grep -E -v '^#' "$check" | grep -E -q 'gitleaks|git log|fetch-depth'; then
  printf 'the scan must not run a history scan\n' >&2
  exit 1
fi
if ! grep -q 'stays off' "$check"; then
  printf 'the scan should say the Gitleaks history job stays off\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'secrets ok\n'
