#!/usr/bin/env bash
# One fix task per failing pull request or main build. Claim before launching.
set -euo pipefail

plan_tasks() {
  local runs_file=$1
  local prs_file=$2
  local claims_file=$3
  jq -ncr --slurpfile runs "$runs_file" --slurpfile prs "$prs_file" --rawfile claims "$claims_file" '
    ($claims | split("\n") | map(select(length > 0))) as $claimed
    | [ $runs[0][] as $run
        | ([$prs[0][] | select(.headRefName == $run.headBranch and .headRefOid == $run.headSha)][0]) as $pr
        | if $pr != null then
            {id: ("pr/" + ($pr.number|tostring) + "/" + $run.headSha), pr: $pr.number, sha: $run.headSha, branch: $run.headBranch, run: {databaseId: $run.databaseId, name: $run.name, url: $run.url}}
          elif ($run.headBranch == "main" or $run.headBranch == "master") then
            {id: ("main/" + $run.headSha), pr: null, sha: $run.headSha, branch: $run.headBranch, run: {databaseId: $run.databaseId, name: $run.name, url: $run.url}}
          else empty end
      ]
    | group_by(.id)
    | map(select(.[0].id as $id | $claimed | index($id) | not))
    | .[]
    | {id: .[0].id, pr: .[0].pr, sha: .[0].sha, branch: .[0].branch, runs: map(.run)}
  '
}

marker_for() {
  printf '<!-- ci-babysit: %s -->\n' "$1"
}

main() {
  local repo= claim= mode=list
  while [[ $# -gt 0 ]]; do
    case $1 in
      --repo)
        repo=$2
        shift
        ;;
      --list) mode=list ;;
      --claim)
        mode=claim
        claim=$2
        shift
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done
  if [[ -z $repo ]]; then
    printf 'usage: ci-babysit.sh --repo owner/name --list|--claim <id>\n' >&2
    exit 2
  fi

  local runs prs claims_text
  runs=$(gh run list --repo "$repo" --status failure --limit 40 --json databaseId,headSha,headBranch,url,name,displayTitle)
  prs=$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName,headRefOid)
  claims_text=$(
    {
      gh api "repos/${repo}/issues/comments?per_page=100" --jq '.[].body'
      gh issue list --repo "$repo" --state all --limit 100 --json body --jq '.[].body'
    } | grep -o 'ci-babysit: [^ -]*' | sed 's/^ci-babysit: //' || true
  )

  if [[ $mode == list ]]; then
    local tmp
    tmp=$(mktemp -d)
    printf '%s' "$runs" >"$tmp/runs.json"
    printf '%s' "$prs" >"$tmp/prs.json"
    printf '%s\n' "$claims_text" >"$tmp/claims"
    plan_tasks "$tmp/runs.json" "$tmp/prs.json" "$tmp/claims"
    rm -rf "$tmp"
    return 0
  fi

  if printf '%s\n' "$claims_text" | grep -F -x -q "$claim"; then
    printf 'already claimed %s\n' "$claim"
    return 0
  fi
  local body
  body=$(marker_for "$claim")
  case $claim in
    pr/*/*)
      local number=${claim#pr/}
      number=${number%%/*}
      gh pr comment "$number" --repo "$repo" --body "$body"
      ;;
    main/*)
      gh issue create --repo "$repo" --title "ci-babysit ${claim}" --body "$body"
      ;;
    *)
      printf 'claim id must be pr/<number>/<sha> or main/<sha>\n' >&2
      exit 2
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
