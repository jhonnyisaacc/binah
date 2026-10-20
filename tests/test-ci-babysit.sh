#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
# shellcheck source=../scripts/ci-babysit.sh
source "$root/scripts/ci-babysit.sh"

tmp=$(mktemp -d)
cat >"$tmp/runs.json" <<'EOF'
[
  {"databaseId":1,"headSha":"abc","headBranch":"feat/x","url":"https://example/1","name":"gate","displayTitle":"feat/x"},
  {"databaseId":2,"headSha":"abc","headBranch":"feat/x","url":"https://example/2","name":"mobile","displayTitle":"feat/x"},
  {"databaseId":3,"headSha":"def","headBranch":"main","url":"https://example/3","name":"eas","displayTitle":"main"},
  {"databaseId":4,"headSha":"fff","headBranch":"feat/closed","url":"https://example/4","name":"gate","displayTitle":"closed"}
]
EOF
cat >"$tmp/prs.json" <<'EOF'
[{"number":12,"headRefName":"feat/x","headRefOid":"abc"}]
EOF
printf '\n' >"$tmp/claims"
tasks=$(plan_tasks "$tmp/runs.json" "$tmp/prs.json" "$tmp/claims")
count=$(printf '%s\n' "$tasks" | jq -s 'length')
if [[ $count -ne 2 ]]; then
  printf 'expected 2 tasks, got %s\n%s\n' "$count" "$tasks" >&2
  exit 1
fi
pr_runs=$(printf '%s\n' "$tasks" | jq -s 'map(select(.id=="pr/12/abc"))[0].runs | length')
if [[ $pr_runs -ne 2 ]]; then
  printf 'one PR should be one task with both runs, got %s\n' "$pr_runs" >&2
  exit 1
fi
printf 'pr/12/abc\n' >"$tmp/claims"
tasks2=$(plan_tasks "$tmp/runs.json" "$tmp/prs.json" "$tmp/claims")
if printf '%s\n' "$tasks2" | jq -s 'map(.id)' | grep -q 'pr/12/abc'; then
  printf 'claimed PR was listed again\n' >&2
  exit 1
fi
if ! printf '%s\n' "$tasks2" | jq -s 'map(.id)' | grep -q 'main/def'; then
  printf 'main failure was dropped with the PR claim\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'ci-babysit ok\n'
