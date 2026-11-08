#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-agent-layout.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=0

good_repo() {
  n=$((n + 1))
  repo=$tmp/repo$n
  git init -q "$repo"
  mkdir -p "$repo/.agents/skills/demo" "$repo/.claude"
  printf -- '---\nname: demo\ndescription: A demo skill.\n---\n\n# Demo\n' >"$repo/.agents/skills/demo/SKILL.md"
  printf '# Agents\n\nRun `sh scripts/handoff-check.sh` before reporting done.\n' >"$repo/AGENTS.md"
  ln -s ../.agents/skills "$repo/.claude/skills"
  git -C "$repo" add -A
}

expect_ok() {
  if ! (cd "$repo" && bash "$check") >"$tmp/out" 2>"$tmp/err"; then
    printf '%s: expected agent-layout ok:\n' "$1" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
  if [[ $(cat "$tmp/out") != 'agent-layout ok' ]]; then
    printf '%s: expected agent-layout ok, got:\n' "$1" >&2
    cat "$tmp/out" >&2
    exit 1
  fi
}

expect_fail() {
  local label=$1
  shift
  if (cd "$repo" && bash "$check") >/dev/null 2>"$tmp/err"; then
    printf '%s: expected a layout failure\n' "$label" >&2
    exit 1
  fi
  for needle in "$@"; do
    if ! grep -qF -- "$needle" "$tmp/err"; then
      printf '%s: failure did not say %s:\n' "$label" "$needle" >&2
      cat "$tmp/err" >&2
      exit 1
    fi
  done
}

good_repo
expect_ok 'canonical layout'
(cd "$repo/.agents/skills/demo" && bash "$check") >/dev/null 2>&1 || {
  printf 'the check should find the repo root from a subfolder\n' >&2
  exit 1
}

good_repo
git -C "$repo" rm -q --cached .claude/skills
expect_fail 'untracked link' '.claude/skills is not tracked' 'ln -s ../.agents/skills .claude/skills'

good_repo
git -C "$repo" rm -q --cached .claude/skills
rm "$repo/.claude/skills"
mkdir -p "$repo/.claude/skills/demo"
cp "$repo/.agents/skills/demo/SKILL.md" "$repo/.claude/skills/demo/SKILL.md"
git -C "$repo" add -A
expect_fail 'directory link' '.claude/skills is a directory of 1 tracked files' 'move its skills into .agents/skills'

good_repo
git -C "$repo" rm -q --cached .claude/skills
rm "$repo/.claude/skills"
printf '../.agents/skills\n' >"$repo/.claude/skills"
git -C "$repo" add -A
expect_fail 'regular file link' '.claude/skills is a regular file' 'git rm -r --cached .claude/skills'

good_repo
rm "$repo/.claude/skills"
ln -s /tmp/skills "$repo/.claude/skills"
git -C "$repo" add -A
expect_fail 'wrong target' '.claude/skills points to /tmp/skills, not ../.agents/skills'

for folder in .cursor/skills .github/skills .codex/skills; do
  good_repo
  mkdir -p "$repo/$folder/demo"
  printf -- '---\nname: demo\n---\n' >"$repo/$folder/demo/SKILL.md"
  git -C "$repo" add -A
  expect_fail "$folder" "$folder holds 1 tracked files" 'git mv them there'
done

good_repo
mkdir -p "$repo/.cursor/skills"
printf 'local only\n' >"$repo/.cursor/skills/notes.md"
expect_ok 'untracked files under .cursor/skills'

good_repo
printf -- '---\nname: other\n---\n' >"$repo/.agents/skills/demo/SKILL.md"
git -C "$repo" add -A
expect_fail 'name mismatch' "has name 'other' but lives in 'demo'" "set 'name: demo'"

good_repo
printf -- "---\nname: 'demo'\n---\n" >"$repo/.agents/skills/demo/SKILL.md"
git -C "$repo" add -A
expect_ok 'quoted name'

good_repo
printf '# Demo\n' >"$repo/.agents/skills/demo/SKILL.md"
git -C "$repo" add -A
expect_fail 'no frontmatter' '.agents/skills/demo/SKILL.md has no frontmatter name' "add 'name: demo'"

good_repo
mkdir -p "$repo/.agents/skills/demo/features"
printf -- '---\nname: unrelated\n---\n' >"$repo/.agents/skills/demo/features/SKILL.md"
git -C "$repo" add -A
expect_ok 'nested SKILL.md is not a skill root'

good_repo
printf 'Open /Users/jhonny/binah/rules.md\nand /home/agent/x and /Users/jhonny/y\n' >>"$repo/AGENTS.md"
printf 'cache at /home/agent/.cache/\n' >"$repo/.agents/skills/demo/notes.md"
git -C "$repo" add -A
expect_fail 'home paths' \
  'AGENTS.md:4 has the home path /Users/jhonny/' \
  'AGENTS.md:5 has the home path /home/agent/' \
  '.agents/skills/demo/notes.md:1 has the home path /home/agent/' \
  'use a repo-relative path or ~ instead'
if [[ $(grep -c 'AGENTS.md:5' "$tmp/err") -ne 1 ]]; then
  printf 'a line with two home paths should be reported once\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

good_repo
printf 'Use ~/.claude/plugins/cache/ and /Users/ alone\n' >>"$repo/AGENTS.md"
ln -s /Users/someone/skill "$repo/.agents/skills/linked"
git -C "$repo" add -A
expect_ok 'tilde paths and symlink targets'

good_repo
git -C "$repo" rm -q --cached .claude/skills
printf -- '---\nname: other\n---\n' >"$repo/.agents/skills/demo/SKILL.md"
mkdir -p "$repo/.cursor/skills/x"
printf 'x\n' >"$repo/.cursor/skills/x/SKILL.md"
git -C "$repo" add .agents .cursor
expect_fail 'every failure at once' '.claude/skills is not tracked' '.cursor/skills holds 1' "has name 'other'"
if [[ $(grep -c '^agent-layout: ' "$tmp/err") -ne 3 ]]; then
  printf 'each failure should be its own agent-layout line:\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

printf 'agent layout ok\n'
