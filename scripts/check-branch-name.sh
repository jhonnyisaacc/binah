#!/usr/bin/env bash
# Exit 0 when the branch name matches policy/branch-name.regex.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
# shellcheck source=lib/common.sh
source "$root/scripts/lib/common.sh"

if [[ $# -ge 1 ]]; then
  name=$1
else
  name=$(git symbolic-ref --short HEAD)
fi
regex_file=$root/policy/branch-name.regex

if branch_name_allowed "$name" "$regex_file"; then
  exit 0
fi

printf 'branch %s does not match %s\n' "$name" "$(head -n 1 "$regex_file")" >&2
exit 1
