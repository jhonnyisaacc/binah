#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)
mkdir -p "$tmp/repo/scripts/lib" "$tmp/repo/policy" "$tmp/repo/.githooks"
cp "$root/scripts/lib/common.sh" "$tmp/repo/scripts/lib/"
cp "$root/policy/forbidden-trailers" "$tmp/repo/policy/"
cp "$root/.githooks/commit-msg" "$tmp/repo/.githooks/commit-msg"
chmod +x "$tmp/repo/.githooks/commit-msg"
git init -q "$tmp/repo"
git -C "$tmp/repo" config user.email test@example.com
git -C "$tmp/repo" config user.name test
git -C "$tmp/repo" config core.hooksPath .githooks
echo a >"$tmp/repo/a"
git -C "$tmp/repo" add a

msg=$tmp/msg
cat >"$msg" <<'EOF'
Keep the weekday labels.

Co-authored-by: Cursor <cursoragent@cursor.com>
Co-authored-by: Ada Lovelace <ada@example.com>
EOF

git -C "$tmp/repo" commit -q -F "$msg"
body=$(git -C "$tmp/repo" log -1 --format=%B)
if printf '%s\n' "$body" | grep -E -q 'Co-authored-by:.*[Cc]ursor'; then
  printf 'Cursor trailer survived the hook:\n%s\n' "$body" >&2
  exit 1
fi
if ! printf '%s\n' "$body" | grep -q 'Co-authored-by: Ada Lovelace <ada@example.com>'; then
  printf 'a human trailer was dropped:\n%s\n' "$body" >&2
  exit 1
fi
if ! printf '%s\n' "$body" | grep -q 'Keep the weekday labels.'; then
  printf 'subject was dropped:\n%s\n' "$body" >&2
  exit 1
fi

rm -rf "$tmp"
printf 'commit-msg ok\n'
