#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: check-guardrails-alone.sh (--repo <owner/name> --number <n> | <changed-path>...)\n' >&2
  exit 2
}

is_guardrail() {
  case $1 in
    .github/workflows | .github/workflows/*) return 0 ;;
    policy | policy/*) return 0 ;;
    scripts/check-*.sh | scripts/lib/common.sh) return 0 ;;
  esac
  return 1
}

is_kit() {
  case $1 in
    .cursor/environment.json | .cursor/skills/agent-preflight/*) return 0 ;;
    .githooks/* | .github/pull_request_template.md) return 0 ;;
    scripts/agent-preflight.sh | scripts/sync-design-files.sh) return 0 ;;
    templates/expo-release/* | rules.md) return 0 ;;
  esac
  return 1
}

paths=()
if [[ ${1:-} == --repo ]]; then
  [[ $# -eq 4 && $3 == --number ]] || usage
  repo=$2
  number=$4
  expected=$(gh api "repos/$repo/pulls/$number" --jq .changed_files)
  listed=0
  while IFS=$'\t' read -r name previous; do
    [[ -n $name ]] || continue
    listed=$((listed + 1))
    paths+=("$name")
    if [[ -n $previous ]]; then
      paths+=("$previous")
    fi
  done < <(gh api --paginate "repos/$repo/pulls/$number/files?per_page=100" \
    --jq '.[] | [.filename, (.previous_filename // "")] | @tsv')
  if [[ $listed -ne $expected ]]; then
    printf 'guardrail changes ride alone: GitHub lists %s of %s changed files, so this pull cannot be checked\n' "$listed" "$expected" >&2
    exit 1
  fi
else
  paths=("$@")
fi

guard_sample=
other_sample=
for path in ${paths[@]+"${paths[@]}"}; do
  if is_guardrail "$path"; then
    guard_sample=$path
  elif ! is_kit "$path"; then
    other_sample=$path
  fi
done

if [[ -n $guard_sample && -n $other_sample ]]; then
  printf 'guardrail changes ride alone (%s); other changes: %s\n' "$guard_sample" "$other_sample" >&2
  exit 1
fi
