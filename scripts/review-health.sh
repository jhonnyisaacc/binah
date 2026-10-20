#!/usr/bin/env bash
# Flag ready pull requests that have no Bugbot result and no review pass.
set -euo pipefail

classify_pr_json() {
  jq -r '
    if .isDraft then "draft"
    elif (
      [
        .statusCheckRollup[]?
        | select((.name // .context // "") | test("bugbot"; "i"))
        | select((.conclusion // .state // "") | test("^(SUCCESS|FAILURE|NEUTRAL)$"; "i"))
      ] | length
    ) > 0 then "ok"
    elif (
      [.comments[]?.body // empty | select(test("(^|\n)Review pass:"))] | length
    ) > 0 then "ok"
    else "flag"
    end
  '
}

main() {
  local repo= flagged=0 list number is_draft title view status
  while [[ $# -gt 0 ]]; do
    case $1 in
      --repo)
        repo=$2
        shift
        ;;
      -h | --help)
        printf 'usage: review-health.sh --repo owner/name\n' >&2
        exit 2
        ;;
      *)
        printf 'unknown argument: %s\n' "$1" >&2
        exit 2
        ;;
    esac
    shift
  done
  if [[ -z $repo ]]; then
    printf 'usage: review-health.sh --repo owner/name\n' >&2
    exit 2
  fi
  list=$(gh pr list --repo "$repo" --state open --limit 200 --json number,isDraft,title)
  while IFS=$'\t' read -r number is_draft title; do
    [[ -n $number ]] || continue
    if [[ $is_draft == true ]]; then
      continue
    fi
    view=$(gh pr view "$number" --repo "$repo" --json isDraft,statusCheckRollup,comments)
    status=$(printf '%s' "$view" | classify_pr_json)
    if [[ $status == flag ]]; then
      printf 'flag %s %s\n' "$number" "$title"
      flagged=1
    fi
  done < <(printf '%s' "$list" | jq -r '.[] | "\(.number)\t\(.isDraft)\t\(.title)"')
  exit "$flagged"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
