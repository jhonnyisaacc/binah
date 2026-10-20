#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-pr-body.sh
tmp=$(mktemp -d)

cat >"$tmp/empty.md" <<'EOF'
## Why

## What changed

## How to test

Phone:

## Design files

Design files:
EOF

if "$check" "$tmp/empty.md" >/dev/null 2>"$tmp/err"; then
  printf 'an unfilled template should fail\n' >&2
  exit 1
fi
if ! grep -q '## Why' "$tmp/err"; then
  printf 'expected a Why error\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

cat >"$tmp/docs.md" <<'EOF'
## Why

The branch check lived in two places.

## What changed

One regex file.

## How to test

Run tests/run.sh.
EOF

"$check" "$tmp/docs.md"

cat >"$tmp/mobile.md" <<'EOF'
## Why

The label was clipped.

## What changed

The weekday label stays on one line.

## How to test

Phone: on a phone, open Monday and confirm the label is fully visible.

## Design files

Design files: origin/main
EOF

if "$check" "$tmp/mobile.md" mobile/src/Week.tsx >/dev/null 2>"$tmp/err"; then
  :
else
  printf 'filled mobile body should pass:\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

if "$check" "$tmp/docs.md" mobile/src/Week.tsx >/dev/null 2>"$tmp/err"; then
  printf 'mobile diff without phone steps should fail\n' >&2
  exit 1
fi

if "$check" "$tmp/docs.md" web/src/App.tsx >/dev/null 2>"$tmp/err"; then
  printf 'UI diff without a design ref should fail\n' >&2
  exit 1
fi
if ! grep -q 'Design files' "$tmp/err"; then
  printf 'UI error should name Design files\n' >&2
  exit 1
fi

"$check" "$tmp/docs.md" web/src/App.test.tsx

# Sync pulls design files, leaves a branch edit alone, and leaves a dirty file alone.
repo=$tmp/repo
mkdir -p "$repo"
git init -q "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
echo readme >"$repo/README"
git -C "$repo" add README
git -C "$repo" -c core.hooksPath=/dev/null commit -q -m 'init'
git -C "$repo" branch -M main
git -C "$repo" switch -q -c feat/ui
git -C "$repo" switch -q main
mkdir -p "$repo/design"
echo v1 >"$repo/design/home.pen"
git -C "$repo" add design/home.pen
git -C "$repo" -c core.hooksPath=/dev/null commit -q -m 'design'
git -C "$repo" switch -q feat/ui

sync() {
  (cd "$repo" && bash "$root/scripts/sync-design-files.sh" main)
}

out=$(sync)
if [[ ! -f $repo/design/home.pen || $(cat "$repo/design/home.pen") != v1 ]]; then
  printf 'sync did not restore the design file\n' >&2
  exit 1
fi
if [[ $out != 'Design files: main' ]]; then
  printf 'sync output was %s\n' "$out" >&2
  exit 1
fi
out2=$(sync)
if [[ $out2 != 'Design files: main' ]]; then
  printf 'second sync output was %s\n' "$out2" >&2
  exit 1
fi

echo dirty >"$repo/design/home.pen"
out4=$(sync)
if [[ $(cat "$repo/design/home.pen") != dirty ]]; then
  printf 'sync overwrote a dirty design file\n' >&2
  exit 1
fi
if ! printf '%s\n' "$out4" | grep -q 'left in place'; then
  printf 'expected the dirty notice, got %s\n' "$out4" >&2
  exit 1
fi

git -C "$repo" checkout -q -- design/home.pen
echo 'branch edit' >"$repo/design/home.pen"
git -C "$repo" add design/home.pen
git -C "$repo" -c core.hooksPath=/dev/null commit -q -m 'edit design'
out3=$(sync)
if [[ $(cat "$repo/design/home.pen") != 'branch edit' ]]; then
  printf 'sync overwrote a branch design commit\n' >&2
  exit 1
fi
if ! printf '%s\n' "$out3" | grep -q 'already commits'; then
  printf 'expected the branch-commit notice, got %s\n' "$out3" >&2
  exit 1
fi

rm -rf "$tmp"
printf 'pr body ok\n'
