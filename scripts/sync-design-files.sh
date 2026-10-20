#!/usr/bin/env bash
# Pull design files from a ref when this branch has not changed them.
set -euo pipefail

base=${1:-origin/main}

if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  printf 'sync-design-files: ref %s is not available. Fetch it first.\n' "$base" >&2
  exit 1
fi

mapfile -t files < <(git ls-tree -r --name-only "$base" | grep -E '(^|/)design/|\.pen$' || true)

if [[ ${#files[@]} -eq 0 ]]; then
  printf 'sync-design-files: no design files on %s\n' "$base"
  printf 'Design files: %s\n' "$base"
  exit 0
fi

if git diff --quiet "$base" -- "${files[@]}"; then
  printf 'Design files: %s\n' "$base"
  exit 0
fi

if [[ -n $(git diff --name-only "$base"...HEAD -- "${files[@]}") ]]; then
  printf 'sync-design-files: this branch already commits design files\n'
  printf 'Design files: %s\n' "$base"
  exit 0
fi

if ! git diff --quiet HEAD -- "${files[@]}" || ! git diff --cached --quiet HEAD -- "${files[@]}"; then
  printf 'sync-design-files: local design edits left in place\n'
  printf 'Design files: %s\n' "$base"
  exit 0
fi

git checkout "$base" -- "${files[@]}"
printf 'Design files: %s\n' "$base"
