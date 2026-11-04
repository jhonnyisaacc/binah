#!/usr/bin/env bash
# A pull that changes guardrail files must not change anything else.
# Guardrail paths are .github/workflows/**, scripts/check-*.sh, and policy/**.
set -euo pipefail

is_guardrail() {
  case $1 in
    .github/workflows | .github/workflows/*) return 0 ;;
    policy | policy/*) return 0 ;;
    scripts/check-*.sh) return 0 ;;
  esac
  return 1
}

guardrail=0
other=0
guard_sample=
other_sample=
for path in "$@"; do
  if is_guardrail "$path"; then
    guardrail=1
    guard_sample=$path
  else
    other=1
    other_sample=$path
  fi
done

if [[ $guardrail -eq 1 && $other -eq 1 ]]; then
  printf 'guardrail changes ride alone (%s); other changes: %s\n' "$guard_sample" "$other_sample" >&2
  exit 1
fi
