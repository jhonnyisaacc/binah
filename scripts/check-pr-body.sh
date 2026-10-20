#!/usr/bin/env bash
# Exit 0 when a pull request body has the required sections.
# Changed paths on the command line turn on the phone and design checks.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'usage: check-pr-body.sh <body-file> [changed-path...]\n' >&2
  exit 2
fi

body=$1
shift

section() {
  awk -v heading="$1" '
    $0 == "## " heading { grab = 1; next }
    grab && /^## / { exit }
    grab { print }
  ' "$body"
}

section_text() {
  local heading=$1
  section "$heading" | grep -E -v '^[[:space:]]*$' | grep -E -v '^Phone:[[:space:]]*$' || true
}

status=0
for heading in "Why" "What changed" "How to test"; do
  if [[ -z $(section_text "$heading") ]]; then
    printf 'pull request body needs a non-empty "## %s" section\n' "$heading" >&2
    status=1
  fi
done

mobile=0
ui=0
for f in "$@"; do
  case $f in
    *.test.* | *.spec.*) continue ;;
  esac
  case $f in
    mobile/* | */mobile/* | ios/* | */ios/* | android/* | */android/*) mobile=1 ;;
  esac
  case $f in
    *.pen | design/* | */design/* | *.tsx | *.jsx | *.vue | *.css | *.scss) ui=1 ;;
  esac
done

if [[ $mobile -eq 1 ]]; then
  if ! section "How to test" | grep -E -q '^Phone:[[:space:]]*[^[:space:]]'; then
    printf 'mobile changes need phone steps on a "Phone:" line under How to test\n' >&2
    status=1
  fi
fi

if [[ $ui -eq 1 ]]; then
  if ! grep -E -q '^Design files:[[:space:]]*[^[:space:]]+' "$body"; then
    printf 'UI changes need a "Design files: <ref>" line\n' >&2
    status=1
  fi
fi

exit "$status"
