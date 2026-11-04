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
  if (cd "$here" && "$check" --prs "$tmp/prs.json" --number "$number") >/dev/null 2>"$tmp/err"; then
    printf 'expected pull #%s to fail\n' "$number" >&2
    exit 1
  fi
  if ! grep -q "$needle" "$tmp/err"; then
    printf 'pull #%s failed without %s:\n' "$number" "$needle" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
}

here=.

expect_pass() {
  local number=$1
  if ! (cd "$here" && "$check" --prs "$tmp/prs.json" --number "$number") >/dev/null 2>"$tmp/err"; then
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
expect_fail 1 'policy/backlog-recovery'

fold='[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one"},
  {"number":2,"state":"MERGED","createdAt":"2026-10-02T00:00:00Z","baseRefName":"feat/one","headRefName":"feat/two"}
]'

commit_repo() {
  git -C "$1" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$2"
}

new_repo() {
  local name=$1
  local bare=$tmp/bare-$name
  local repo=$tmp/work-$name
  git init -q --bare "$bare"
  git init -q "$repo"
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" checkout -q -B main
  git -C "$repo" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  git -C "$repo" fetch -q origin
  printf '%s\n' "$repo"
}

# Listed on the base branch. The head copy drops the number and still passes.
repo=$(new_repo listed)
mkdir -p "$repo/policy"
printf '# approved\n1 # bottom pull\n' >"$repo/policy/backlog-recovery"
git -C "$repo" add policy/backlog-recovery
commit_repo "$repo" list
git -C "$repo" push -q origin main
git -C "$repo" fetch -q origin
git -C "$repo" checkout -q -b feat/one
printf '# not on the base\n' >"$repo/policy/backlog-recovery"
git -C "$repo" add policy/backlog-recovery
commit_repo "$repo" drop
write "$fold"
here=$repo
expect_pass 1

# Present in the file, but not this pull.
repo=$(new_repo unlisted)
mkdir -p "$repo/policy"
printf '# 1 is a comment, not a listing\n12\n' >"$repo/policy/backlog-recovery"
git -C "$repo" add policy/backlog-recovery
commit_repo "$repo" other
git -C "$repo" push -q origin main
git -C "$repo" fetch -q origin
write "$fold"
here=$repo
expect_fail 1 'later pull request #2'

# The number exists only on the pull's head.
repo=$(new_repo head)
mkdir -p "$repo/policy"
printf '# none\n' >"$repo/policy/backlog-recovery"
git -C "$repo" add policy/backlog-recovery
commit_repo "$repo" empty
git -C "$repo" push -q origin main
git -C "$repo" fetch -q origin
git -C "$repo" checkout -q -b feat/one
printf '1\n' >"$repo/policy/backlog-recovery"
git -C "$repo" add policy/backlog-recovery
commit_repo "$repo" head-only
write "$fold"
here=$repo
expect_fail 1 'merge-playbook.md section 10'

# The base branch has no policy file.
repo=$(new_repo missing)
write "$fold"
here=$repo
expect_fail 1 'later pull request #2'

here=.

write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one","labels":[{"name":"other"}]},
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
expect_pass 1
expect_pass 2
expect_pass 3
expect_pass 4
expect_pass 5
expect_fail 6 'pull #6 is the 6th open pull; the limit is 5'

# createdAt order, not number order. The 6th and later fail.
write '[
  {"number":9,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/old"},
  {"number":8,"state":"OPEN","createdAt":"2026-10-02T00:00:00Z","baseRefName":"main","headRefName":"feat/b"},
  {"number":7,"state":"OPEN","createdAt":"2026-10-03T00:00:00Z","baseRefName":"main","headRefName":"feat/c"},
  {"number":4,"state":"OPEN","createdAt":"2026-10-04T00:00:00Z","baseRefName":"main","headRefName":"feat/d"},
  {"number":3,"state":"OPEN","createdAt":"2026-10-05T00:00:00Z","baseRefName":"main","headRefName":"feat/e"},
  {"number":1,"state":"OPEN","createdAt":"2026-10-06T00:00:00Z","baseRefName":"main","headRefName":"feat/sixth"},
  {"number":2,"state":"OPEN","createdAt":"2026-10-07T00:00:00Z","baseRefName":"main","headRefName":"feat/seventh"}
]'
expect_pass 9
expect_pass 3
expect_fail 1 'pull #1 is the 6th open pull; the limit is 5'
expect_fail 2 'pull #2 is the 7th open pull; the limit is 5'

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

repo=$(new_repo fold-chosen-base)
git -C "$repo" checkout -q -b feat/recovery
mkdir -p "$repo/policy"
printf '1\n' >"$repo/policy/backlog-recovery"
git -C "$repo" add policy/backlog-recovery
commit_repo "$repo" 'list on a branch the pull chose'
git -C "$repo" push -q origin feat/recovery
git -C "$repo" fetch -q origin
write '[
  {"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"feat/recovery","headRefName":"feat/one"},
  {"number":2,"state":"MERGED","createdAt":"2026-10-02T00:00:00Z","baseRefName":"feat/one","headRefName":"feat/two"}
]'
(
  cd "$repo"
  if "$check" --prs "$tmp/prs.json" --number 1 >/dev/null 2>"$tmp/err"; then
    printf 'a listing on a base the pull chose must not grant a fold\n' >&2
    exit 1
  fi
)

repo=$(new_repo fold-live)
git -C "$repo" remote set-url origin "file://$tmp/bare-fold-live"
git -C "$repo" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m second
git -C "$repo" push -q origin main
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "repo view acme/app --json defaultBranchRef --jq .defaultBranchRef.name") printf 'main\n' ;;
  "pr list --repo acme/app "*) printf '%s\n' '[{"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one"}]' ;;
  *) printf 'unexpected gh: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
git -C "$repo" update-ref -d refs/remotes/origin/main
(
  cd "$repo"
  PATH="$tmp/bin:$PATH" "$check" --repo acme/app --number 1
  if [[ $(git rev-parse --is-shallow-repository) != false ]]; then
    printf 'a live run made a full clone shallow\n' >&2
    exit 1
  fi
)

rm -rf "$tmp"
printf 'one pr ok\n'
