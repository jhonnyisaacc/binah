#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/templates/expo-release/check_expo_release.py
fix=$root/tests/fixtures/expo

run() {
  python3 "$check" --app "$1" --repo "$1"
}

if ! run "$fix/good" >/dev/null; then
  printf 'good fixture should pass\n' >&2
  run "$fix/good" >&2 || true
  exit 1
fi

expect_fail() {
  local dir=$1
  local needle=$2
  local err
  if err=$(run "$fix/$dir" 2>&1); then
    printf '%s should fail\n' "$dir" >&2
    exit 1
  fi
  if ! printf '%s\n' "$err" | grep -q "$needle"; then
    printf '%s failed without %s:\n%s\n' "$dir" "$needle" "$err" >&2
    exit 1
  fi
}

expect_fail bad-api 'non-loopback fallback'
expect_fail bad-ignore '.easignore drops data/chapters'
expect_fail bad-platform 'platform is all'
expect_fail bad-no-platform 'needs --platform android'
expect_fail bad-version 'expo.version'
expect_fail bad-version 'autoIncrement must be true'

python3 - <<'PY'
import importlib.util
from pathlib import Path
path = Path("/workspace/templates/expo-release/check_expo_release.py")
spec = importlib.util.spec_from_file_location("check", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
patterns = mod.ignore_patterns("*.log\ndata/\n!data/keep.json\n")
assert mod.ignored("notes.log", patterns)
assert not mod.ignored("data/keep.json", patterns)
assert mod.ignored("data/chapters", patterns)
assert not mod.ignored("src/app.tsx", patterns)
PY

# Refa copies the template only when the repo has a mobile app.
tmp=$(mktemp -d)
mkdir -p "$tmp/repo"
bash "$root/scripts/install-policy-kit.sh" --mobile "$tmp/repo" >/dev/null
test -f "$tmp/repo/templates/expo-release/check_expo_release.py"
test -f "$tmp/repo/templates/expo-release/README.md"
rm -rf "$tmp"

printf 'expo release ok\n'
