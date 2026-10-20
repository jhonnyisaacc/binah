#!/usr/bin/env bash
# The written rules and the policy files name the same pattern and author.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
regex=$(tr -d '\n' < "$root/policy/branch-name.regex")
email=$(sed -n 's/^email=//p' "$root/policy/author")

if ! grep -F -q -- "$regex" "$root/rules.md"; then
  printf 'rules.md does not quote policy/branch-name.regex\n' >&2
  exit 1
fi
if ! grep -F -q -- "$email" "$root/rules.md"; then
  printf 'rules.md does not name the author email from policy/author\n' >&2
  exit 1
fi
if ! grep -F -q -- "$email" "$root/setup/signing.md"; then
  printf 'setup/signing.md does not name the author email from policy/author\n' >&2
  exit 1
fi
if ! head -n 1 "$root/rules.md" | grep -F -q 'v4.6'; then
  printf 'rules.md header is not v4.6\n' >&2
  exit 1
fi
if ! grep -F -q 'Version: 4.6 (matches rules.md).' "$root/merge-playbook.md"; then
  printf 'merge-playbook.md version does not match rules.md\n' >&2
  exit 1
fi
printf 'policy sync ok\n'
