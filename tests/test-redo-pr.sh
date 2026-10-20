#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
tmp=$(mktemp -d)

if bash "$root/scripts/redo-pr.sh" --repo acme/app --old 12 --branch 'cursor/bad' --title 'Redo' >/dev/null 2>"$tmp/err"; then
  printf 'a cursor/ branch should be rejected\n' >&2
  exit 1
fi
if bash "$root/scripts/redo-pr.sh" --repo acme/app --old 12 --branch 'feat/bad.name' --title 'Redo' >/dev/null 2>"$tmp/err"; then
  printf 'a dotted branch should be rejected\n' >&2
  exit 1
fi

cat >"$tmp/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/log"
case "\$*" in
  "pr view 12 --repo acme/app --json headRefName")
    printf '%s\n' '{"headRefName":"feat/old"}'
    ;;
  "pr list --repo acme/app --state open --limit 200 --json baseRefName")
    printf '%s\n' '[{"baseRefName":"main"}]'
    ;;
  "pr create --repo acme/app --draft --base main --head feat/widget --title Redo the label --body "*)
    printf '%s\n' 'https://github.com/acme/app/pull/40'
    ;;
  "pr comment 12 --repo acme/app --body Replaced by #40.")
    ;;
  "pr close 12 --repo acme/app --comment Replaced by #40.")
    ;;
  "api -X DELETE repos/acme/app/git/refs/heads/feat/old")
    ;;
  *)
    printf 'unexpected gh: %s\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/gh"
export PATH="$tmp:$PATH"

dry=$(bash "$root/scripts/redo-pr.sh" --repo acme/app --old 12 --branch feat/widget --title 'Redo the label')
printf '%s\n' "$dry" | grep -q 'delete branch feat/old'
if grep -q 'pr create' "$tmp/log"; then
  printf 'dry run created a pull request\n' >&2
  exit 1
fi

: >"$tmp/log"
url=$(bash "$root/scripts/redo-pr.sh" --apply --repo acme/app --old 12 --branch feat/widget --title 'Redo the label' | tail -n 1)
if [[ $url != https://github.com/acme/app/pull/40 ]]; then
  printf 'apply returned %s\n' "$url" >&2
  exit 1
fi
grep -q 'pr create' "$tmp/log"
grep -q 'pr comment 12' "$tmp/log"
grep -q 'pr close 12' "$tmp/log"
grep -q 'DELETE repos/acme/app/git/refs/heads/feat/old' "$tmp/log"

rm -rf "$tmp"
printf 'redo-pr ok\n'
