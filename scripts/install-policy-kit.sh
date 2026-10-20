#!/usr/bin/env bash
# Copy the binah policy kit into another repository. Does not commit.
set -euo pipefail

usage() {
  printf 'usage: install-policy-kit.sh [--mobile] <target-repo>\n' >&2
  exit 2
}

mobile=0
target=
while [[ $# -gt 0 ]]; do
  case $1 in
    --mobile) mobile=1 ;;
    -h | --help) usage ;;
    *)
      if [[ -n $target ]]; then
        usage
      fi
      target=$1
      ;;
  esac
  shift
done
[[ -n $target ]] || usage

src=$(cd "$(dirname "$0")/.." && pwd)
target=$(cd "$target" && pwd)

copy_file() {
  local from=$1
  local to=$2
  mkdir -p "$(dirname "$to")"
  if [[ -f $to ]] && cmp -s "$from" "$to"; then
    return 0
  fi
  cp "$from" "$to"
  if [[ -x $from ]]; then
    chmod +x "$to"
  fi
}

copy_file "$src/policy/author" "$target/policy/author"
copy_file "$src/policy/branch-name.regex" "$target/policy/branch-name.regex"
copy_file "$src/policy/forbidden-trailers" "$target/policy/forbidden-trailers"
copy_file "$src/scripts/lib/common.sh" "$target/scripts/lib/common.sh"
copy_file "$src/scripts/agent-preflight.sh" "$target/scripts/agent-preflight.sh"
copy_file "$src/scripts/check-branch-name.sh" "$target/scripts/check-branch-name.sh"
copy_file "$src/.githooks/commit-msg" "$target/.githooks/commit-msg"
copy_file "$src/.githooks/pre-push" "$target/.githooks/pre-push"
copy_file "$src/skills/agent-preflight/SKILL.md" "$target/.cursor/skills/agent-preflight/SKILL.md"

if [[ -f $src/scripts/check-pr-body.sh ]]; then
  copy_file "$src/scripts/check-pr-body.sh" "$target/scripts/check-pr-body.sh"
fi
if [[ -f $src/scripts/sync-design-files.sh ]]; then
  copy_file "$src/scripts/sync-design-files.sh" "$target/scripts/sync-design-files.sh"
fi
if [[ -f $src/templates/pull_request_template.md ]]; then
  copy_file "$src/templates/pull_request_template.md" "$target/.github/pull_request_template.md"
fi
if [[ $mobile -eq 1 && -f $src/templates/expo-release/check_expo_release.py ]]; then
  copy_file "$src/templates/expo-release/check_expo_release.py" "$target/templates/expo-release/check_expo_release.py"
  if [[ -f $src/templates/expo-release/README.md ]]; then
    copy_file "$src/templates/expo-release/README.md" "$target/templates/expo-release/README.md"
  fi
fi

python3 "$src/scripts/merge-cursor-environment.py" "$target/.cursor/environment.json"
printf 'installed policy kit into %s\n' "$target"
