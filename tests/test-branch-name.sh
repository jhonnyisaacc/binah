#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-branch-name.sh

pass() {
  if "$check" "$1" >/dev/null; then
    return 0
  fi
  printf 'expected allow: %s\n' "$1" >&2
  return 1
}

fail() {
  if "$check" "$1" >/dev/null 2>&1; then
    printf 'expected reject: %s\n' "$1" >&2
    return 1
  fi
}

pass feat/widget
pass fix/a
pass hotfix/prod-outage
pass chore/deps
pass docs/rules
pass refactor/run-01
pass test/pins
pass release/1-4-0
pass feat/definitions-ae37

fail cursor/widget
fail cursor/widget-fa93
fail feat/android-1.0.1-r8
fail feat/foo.bar
fail staging
fail feat/Widget
fail feat/-leading-dash
fail feat/foo/bar
fail Feat/widget
fail ''

# pre-push allows trunk and rejects a bad head. Deletes are allowed.
tmp=$(mktemp -d)
git init -q "$tmp/repo"
git -C "$tmp/repo" config user.email test@example.com
git -C "$tmp/repo" config user.name test
mkdir -p "$tmp/repo/scripts" "$tmp/repo/policy" "$tmp/repo/.githooks"
cp "$root/scripts/check-branch-name.sh" "$tmp/repo/scripts/"
cp "$root/scripts/lib/common.sh" "$tmp/repo/scripts/lib/common.sh" 2>/dev/null || {
  mkdir -p "$tmp/repo/scripts/lib"
  cp "$root/scripts/lib/common.sh" "$tmp/repo/scripts/lib/"
}
cp "$root/policy/branch-name.regex" "$tmp/repo/policy/"
cp "$root/.githooks/pre-push" "$tmp/repo/.githooks/pre-push"
cp "$root/scripts/check-agent-layout.sh" "$tmp/repo/scripts/"
chmod +x "$tmp/repo/.githooks/pre-push" "$tmp/repo/scripts/check-branch-name.sh"
mkdir -p "$tmp/repo/.agents/skills" "$tmp/repo/.claude"
ln -s ../.agents/skills "$tmp/repo/.claude/skills"
echo a >"$tmp/repo/a"
git -C "$tmp/repo" add a .claude/skills
git -C "$tmp/repo" -c core.hooksPath=/dev/null commit -q -m init
git -C "$tmp/repo" branch -M main
git -C "$tmp/repo" config core.hooksPath .githooks

bare=$tmp/bare
git init -q --bare "$bare"
git -C "$tmp/repo" remote add origin "$bare"

if ! git -C "$tmp/repo" push -q origin main; then
  printf 'main push should pass\n' >&2
  exit 1
fi
git -C "$tmp/repo" switch -q -c feat/ok
if ! git -C "$tmp/repo" push -q -u origin feat/ok; then
  printf 'feat/ok push should pass\n' >&2
  exit 1
fi
git -C "$tmp/repo" switch -q -c 'feat/bad.name'
if git -C "$tmp/repo" push -q -u origin 'feat/bad.name' 2>"$tmp/err"; then
  printf 'dotted branch push should fail\n' >&2
  exit 1
fi
if ! grep -q 'does not match' "$tmp/err"; then
  printf 'dotted branch error should name the regex\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

git -C "$tmp/repo" switch -q -c feat/cursor-skill
mkdir -p "$tmp/repo/.cursor/skills/x"
printf -- '---\nname: x\n---\n' >"$tmp/repo/.cursor/skills/x/SKILL.md"
git -C "$tmp/repo" add .cursor
git -C "$tmp/repo" -c core.hooksPath=/dev/null commit -q -m 'cursor skill'
if git -C "$tmp/repo" push -q -u origin feat/cursor-skill 2>"$tmp/err"; then
  printf 'a push with tracked .cursor/skills files should fail\n' >&2
  exit 1
fi
if ! grep -q 'agent-layout: .cursor/skills holds 1 tracked files' "$tmp/err"; then
  printf 'the layout failure should name .cursor/skills:\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

# The regex is the one next to the script, not the git toplevel of the cwd.
base=$tmp/base
mkdir -p "$base/scripts/lib" "$base/policy" "$tmp/head"
cp "$root/scripts/check-branch-name.sh" "$base/scripts/"
cp "$root/scripts/lib/common.sh" "$base/scripts/lib/"
cp "$root/policy/branch-name.regex" "$base/policy/"
printf '.*\n' >"$tmp/head/policy-would-allow-anything"
git init -q "$tmp/head"
mkdir -p "$tmp/head/policy"
printf '.*\n' >"$tmp/head/policy/branch-name.regex"
if (cd "$tmp/head" && bash "$base/scripts/check-branch-name.sh" cursor/bad) >/dev/null 2>"$tmp/err"; then
  printf 'branch check used the head regex instead of the script tree\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'branch-name ok\n'
