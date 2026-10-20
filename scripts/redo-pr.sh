#!/usr/bin/env bash
# Open the replacement link, close the old pull request, delete its branch.
# The replacement branch already exists and its commits are signed.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/common.sh
source "$root/scripts/lib/common.sh"

main() {
  local apply=0 repo= old= branch= title= base=main
  while [[ $# -gt 0 ]]; do
    case $1 in
      --apply) apply=1 ;;
      --repo)
        repo=$2
        shift
        ;;
      --old)
        old=$2
        shift
        ;;
      --branch)
        branch=$2
        shift
        ;;
      --title)
        title=$2
        shift
        ;;
      --base)
        base=$2
        shift
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done
  if [[ -z $repo || -z $old || -z $branch || -z $title ]]; then
    printf 'usage: redo-pr.sh --repo owner/name --old <n> --branch <name> --title <title> [--base main] [--apply]\n' >&2
    exit 2
  fi
  if ! branch_name_allowed "$branch" "$root/policy/branch-name.regex"; then
    printf 'branch %s does not match %s\n' "$branch" "$(head -n 1 "$root/policy/branch-name.regex")" >&2
    exit 1
  fi

  local old_branch open_bases
  old_branch=$(gh pr view "$old" --repo "$repo" --json headRefName | jq -r .headRefName)
  open_bases=$(gh pr list --repo "$repo" --state open --limit 200 --json baseRefName | jq -r '.[].baseRefName')

  printf 'open draft #%s replacement from %s as %s\n' "$old" "$base" "$branch"
  printf 'comment on #%s with the new pull request\n' "$old"
  printf 'close #%s\n' "$old"
  if printf '%s\n' "$open_bases" | grep -F -x -q "$old_branch"; then
    printf 'keep branch %s because an open pull request uses it as a base\n' "$old_branch"
  else
    printf 'delete branch %s\n' "$old_branch"
  fi

  if [[ $apply -ne 1 ]]; then
    return 0
  fi

  local body new_url new_number
  body=$(printf 'Replaces #%s.\n\n## Why\n\nThe previous pull request could not be kept.\n\n## What changed\n\n%s\n\n## How to test\n\nSame checks as #%s.\n' "$old" "$title" "$old")
  new_url=$(gh pr create --repo "$repo" --draft --base "$base" --head "$branch" --title "$title" --body "$body")
  new_number=${new_url##*/}
  gh pr comment "$old" --repo "$repo" --body "Replaced by #${new_number}."
  gh pr close "$old" --repo "$repo" --comment "Replaced by #${new_number}."
  if ! printf '%s\n' "$open_bases" | grep -F -x -q "$old_branch"; then
    gh api -X DELETE "repos/${repo}/git/refs/heads/${old_branch}"
  fi
  printf '%s\n' "$new_url"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
