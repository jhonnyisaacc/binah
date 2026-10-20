#!/usr/bin/env bash
# Merge each open pull request's base into its head. Never rebase.
set -euo pipefail

pr_action() {
  local ancestor=$1
  local same_tree=$2
  if [[ $ancestor == yes || $same_tree == yes ]]; then
    printf 'close\n'
  else
    printf 'merge\n'
  fi
}

protected_branch() {
  case $1 in
    main | master | refactor/run-*) return 0 ;;
  esac
  return 1
}

should_delete_branch() {
  local branch=$1
  local open_bases=$2
  local base
  if protected_branch "$branch"; then
    return 1
  fi
  for base in $open_bases; do
    if [[ $base == "$branch" ]]; then
      return 1
    fi
  done
  return 0
}

main() {
  local apply=0 repo= workdir= base_name
  while [[ $# -gt 0 ]]; do
    case $1 in
      --apply) apply=1 ;;
      --repo)
        repo=$2
        shift
        ;;
      --workdir)
        workdir=$2
        shift
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done
  if [[ -z $repo || -z $workdir ]]; then
    printf 'usage: keep-current.sh --repo owner/name --workdir <clone> [--apply]\n' >&2
    exit 2
  fi
  if [[ -n $(git -C "$workdir" status --porcelain) ]]; then
    printf 'keep-current: %s has uncommitted changes\n' "$workdir" >&2
    exit 1
  fi

  local open merged
  open=$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName,baseRefName)
  merged=$(gh pr list --repo "$repo" --state merged --limit 200 --json headRefName)
  git -C "$workdir" fetch --quiet origin

  local open_bases
  open_bases=$(printf '%s' "$open" | jq -r '.[].baseRefName')

  local number head base ancestor same action files
  while IFS=$'\t' read -r number head base; do
    [[ -n $number ]] || continue
    git -C "$workdir" switch --quiet -C "kc/${head}" "origin/${head}"
    if git -C "$workdir" merge-base --is-ancestor HEAD "origin/${base}"; then
      ancestor=yes
    else
      ancestor=no
    fi
    if git -C "$workdir" diff --quiet HEAD "origin/${base}"; then
      same=yes
    else
      same=no
    fi
    action=$(pr_action "$ancestor" "$same")
    if [[ $action == close ]]; then
      printf 'close #%s %s\n' "$number" "$head"
      if [[ $apply -eq 1 ]]; then
        gh pr close "$number" --repo "$repo" --comment "Already on ${base}. Closing."
      fi
      continue
    fi
    if git -C "$workdir" merge --no-edit "origin/${base}"; then
      printf 'merge #%s %s\n' "$number" "$head"
      if [[ $apply -eq 1 ]]; then
        git -C "$workdir" push --quiet origin "HEAD:refs/heads/${head}"
      fi
    else
      files=$(git -C "$workdir" diff --name-only --diff-filter=U | paste -sd ' ' -)
      git -C "$workdir" merge --abort
      printf 'conflict #%s %s %s\n' "$number" "$head" "$files"
      if [[ $apply -eq 1 ]]; then
        gh pr comment "$number" --repo "$repo" --body "Merge conflict with ${base}. Not rebasing. Files: ${files}"
      fi
    fi
  done < <(printf '%s' "$open" | jq -r '.[] | "\(.number)\t\(.headRefName)\t\(.baseRefName)"')

  local branch
  while IFS= read -r branch; do
    [[ -n $branch ]] || continue
    if should_delete_branch "$branch" "$open_bases"; then
      printf 'delete %s\n' "$branch"
      if [[ $apply -eq 1 ]]; then
        git -C "$workdir" push --quiet origin --delete "$branch" || true
      fi
    else
      printf 'keep %s\n' "$branch"
    fi
  done < <(printf '%s' "$merged" | jq -r '.[].headRefName')
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
