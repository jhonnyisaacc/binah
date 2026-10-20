#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
# shellcheck source=../scripts/review-health.sh
source "$root/scripts/review-health.sh"

expect() {
  local want=$1
  local json=$2
  local got
  got=$(printf '%s' "$json" | classify_pr_json)
  if [[ $got != "$want" ]]; then
    printf 'classify wanted %s got %s for %s\n' "$want" "$got" "$json" >&2
    return 1
  fi
}

expect draft '{"isDraft":true,"statusCheckRollup":[],"comments":[]}'
expect ok '{"isDraft":false,"statusCheckRollup":[{"name":"Cursor Bugbot","conclusion":"SUCCESS"}],"comments":[]}'
expect ok '{"isDraft":false,"statusCheckRollup":[{"name":"Cursor Bugbot","conclusion":"NEUTRAL"}],"comments":[]}'
expect flag '{"isDraft":false,"statusCheckRollup":[{"name":"Cursor Bugbot","status":"IN_PROGRESS"}],"comments":[]}'
expect ok '{"isDraft":false,"statusCheckRollup":[],"comments":[{"body":"Review pass: checked the weekday label on a phone."}]}'
expect flag '{"isDraft":false,"statusCheckRollup":[{"name":"gate","conclusion":"SUCCESS"}],"comments":[{"body":"preview deployed"}]}'

# Wiring: one ready PR with no review is a failure. A draft is ignored.
tmp=$(mktemp -d)
export PATH=$tmp:$PATH
cat >"$tmp/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/log"
case "\$*" in
  "pr list --repo acme/app --state open --limit 200 --json number,isDraft,title")
    printf '%s\n' '[{"number":7,"isDraft":false,"title":"Weekday labels"},{"number":8,"isDraft":true,"title":"Still writing"}]'
    ;;
  "pr view 7 --repo acme/app --json isDraft,statusCheckRollup,comments")
    printf '%s\n' '{"isDraft":false,"statusCheckRollup":[],"comments":[]}'
    ;;
  *)
    printf 'unexpected gh %s\n' "\$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$tmp/gh"
set +e
out=$(bash "$root/scripts/review-health.sh" --repo acme/app 2>"$tmp/err")
code=$?
set -e
if [[ $code -ne 1 ]]; then
  printf 'expected exit 1, got %s\n%s\n' "$code" "$out" >&2
  exit 1
fi
if [[ $out != 'flag 7 Weekday labels' ]]; then
  printf 'unexpected flag line: %s\n' "$out" >&2
  exit 1
fi
if grep -q 'pr view 8' "$tmp/log"; then
  printf 'a draft was fetched\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'review health ok\n'
