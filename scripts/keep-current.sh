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
  local pattern
  case $1 in
    main | master | refactor/run-*) return 0 ;;
  esac
  while IFS= read -r pattern; do
    if [[ -n $pattern && $1 == $pattern ]]; then
      return 0
    fi
  done <<<"${integration_names:-}"
  return 1
}

read_open_branches() {
  gh pr list --repo "$1" --state open --limit 200 --json number,headRefName,baseRefName |
    jq -r '.[].baseRefName, .[].headRefName'
}

read_integration_names() {
  local workdir=$1 default_ref
  default_ref=$(git -C "$workdir" ls-remote --symref origin HEAD | awk '$1 == "ref:" { print $2 }')
  if [[ -z $default_ref ]]; then
    return 0
  fi
  git -C "$workdir" show "origin/${default_ref#refs/heads/}:policy/integration-branches" 2>/dev/null |
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' || true
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
  merged=$(gh pr list --repo "$repo" --state merged --limit 200 --json headRefName,headRefOid)
  git -C "$workdir" fetch --quiet origin
  integration_names=$(read_integration_names "$workdir")

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

  local branch merged_oid tip open_now
  while IFS=$'\t' read -r branch merged_oid; do
    [[ -n $branch ]] || continue
    tip=$(git -C "$workdir" rev-parse "origin/${branch}" 2>/dev/null || true)
    if [[ $tip != "$merged_oid" ]] || protected_branch "$branch"; then
      printf 'keep %s\n' "$branch"
      continue
    fi
    if ! open_now=$(read_open_branches "$repo") || ! should_delete_branch "$branch" "$open_now"; then
      printf 'keep %s\n' "$branch"
      continue
    fi
    if [[ $apply -eq 1 ]] && ! git -C "$workdir" push --quiet --force-with-lease="refs/heads/${branch}:${merged_oid}" origin --delete "refs/heads/${branch}"; then
      printf 'keep %s\n' "$branch"
      continue
    fi
    printf 'delete %s\n' "$branch"
  done < <(printf '%s' "$merged" | jq -r '.[] | "\(.headRefName)\t\(.headRefOid)"')
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
