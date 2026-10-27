#!/usr/bin/env bash
# One pull request, one job. A sentence in a template is not a pass.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-one-pr.sh
tmp=$(mktemp -d)

write() {
  printf '%s\n' "$1" >"$tmp/prs.json"
}

expect_fail() {
  local number=$1
  local needle=$2
  if "$check" --prs "$tmp/prs.json" --number "$number" >/dev/null 2>"$tmp/err"; then
    printf 'expected pull #%s to fail\n' "$number" >&2
    exit 1
  fi
  if ! grep -q "$needle" "$tmp/err"; then
    printf 'pull #%s failed without %s:\n' "$number" "$needle" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
}

expect_pass() {
  local number=$1
  if ! "$check" --prs "$tmp/prs.json" --number "$number" >/dev/null 2>"$tmp/err"; then
    printf 'expected pull #%s to pass:\n' "$number" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
}

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one"}
]'
expect_pass 1

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one"},
  {"number":2,"state":"MERGED","createdAt":"2026-10-02T00:00:00Z","baseRefName":"feat/one","headRefName":"feat/two"}
]'
expect_fail 1 'later pull request #2'

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one"},
  {"number":2,"state":"MERGED","createdAt":"2026-10-02T00:00:00Z","baseRefName":"main","headRefName":"feat/two"}
]'
expect_pass 1

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"refactor/run-01"},
  {"number":2,"state":"MERGED","createdAt":"2026-10-02T00:00:00Z","baseRefName":"refactor/run-01","headRefName":"feat/a"}
]'
expect_pass 1

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/a"},
  {"number":2,"state":"OPEN","createdAt":"2026-10-02T00:00:00Z","baseRefName":"feat/a","headRefName":"feat/b"},
  {"number":3,"state":"OPEN","createdAt":"2026-10-03T00:00:00Z","baseRefName":"feat/b","headRefName":"feat/c"}
]'
expect_pass 1
expect_pass 2
expect_fail 3 'stack depth 3 is over the limit of 2'

open='['
for n in 1 2 3 4 5 6; do
  open+=$(printf '{"number":%s,"state":"OPEN","createdAt":"2026-10-0%sT00:00:00Z","baseRefName":"main","headRefName":"feat/p%s"}' "$n" "$n" "$n")
  if [[ $n -ne 6 ]]; then
    open+=','
  fi
done
open+=']'
write "$open"
expect_fail 1 'over the limit of 5'

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"refactor/run-01"},
  {"number":2,"state":"OPEN","createdAt":"2026-10-02T00:00:00Z","baseRefName":"refactor/run-01","headRefName":"feat/a"},
  {"number":3,"state":"OPEN","createdAt":"2026-10-03T00:00:00Z","baseRefName":"refactor/run-01","headRefName":"feat/b"},
  {"number":4,"state":"OPEN","createdAt":"2026-10-04T00:00:00Z","baseRefName":"refactor/run-01","headRefName":"feat/c"},
  {"number":5,"state":"OPEN","createdAt":"2026-10-05T00:00:00Z","baseRefName":"refactor/run-01","headRefName":"feat/d"},
  {"number":6,"state":"OPEN","createdAt":"2026-10-06T00:00:00Z","baseRefName":"refactor/run-01","headRefName":"feat/e"}
]'
expect_pass 2

# The rule text is not the check. The script has to exit non-zero.
printf 'One pull request is one job. Stack depth at most 2.\n' >"$tmp/sentence.txt"
if "$check" --prs "$tmp/sentence.txt" --number 1 >/dev/null 2>"$tmp/err"; then
  printf 'a template sentence must not pass\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'one pr ok\n'
