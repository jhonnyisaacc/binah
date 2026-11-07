#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
check=$root/scripts/check-guardrails-alone.sh
err=$(mktemp)
trap 'rm -f "$err"' EXIT

pass() {
  if ! "$check" "$@" >/dev/null 2>"$err"; then
    printf 'expected pass:' >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    cat "$err" >&2
    exit 1
  fi
}

fail() {
  local needle=$1
  shift
  local err
  err=$(mktemp)
  if "$check" "$@" >/dev/null 2>"$err"; then
    printf 'expected fail:' >&2
    printf ' %s' "$@" >&2
    printf '\n' >&2
    rm -f "$err"
    exit 1
  fi
  if ! grep -q "$needle" "$err"; then
    printf 'failure did not mention %s:\n' "$needle" >&2
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  if ! grep -q 'guardrail changes ride alone' "$err"; then
    printf 'failure should say guardrail changes ride alone\n' >&2
    cat "$err" >&2
    rm -f "$err"
    exit 1
  fi
  rm -f "$err"
}

pass
pass src/app.ts README.md tests/test-guardrails-alone.sh
pass .github/workflows/hygiene.yml
pass .github/workflows/nested/ci.yml
pass scripts/check-secrets.sh
pass scripts/check-guardrails-alone.sh policy/secret-allowlist .github/workflows/hygiene.yml
pass policy/dir/name

fail src/app.ts .github/workflows/hygiene.yml src/app.ts
fail README.md policy/secret-allowlist README.md
fail tests/test-one-pr.sh scripts/check-one-pr.sh tests/test-one-pr.sh

# scripts/binah-install and scripts/lib are not guardrail paths.
pass scripts/binah-install scripts/lib/wire-hygiene.py

if "$check" scripts/check-secrets.sh scripts/lib/wire-hygiene.py >/dev/null 2>"$err"; then
  printf 'a check script plus another script should fail\n' >&2
  exit 1
fi
if ! grep -q 'scripts/lib/wire-hygiene.py' "$err"; then
  printf 'mixed failure should name the other path\n' >&2
  cat "$err" >&2
  exit 1
fi

fail src/app.ts scripts/lib/common.sh src/app.ts

kit=$(mktemp -d)
bash "$root/scripts/binah-install" "$kit" >/dev/null
installed=()
while IFS= read -r path; do
  installed+=("$path")
done < <(cd "$kit" && find . -type f | sed 's#^\./##')
rm -rf "$kit"
pass "${installed[@]}" rules.md templates/expo-release/README.md

pass .github/workflows/hygiene.yml scripts/check-agent-layout.sh \
  .agents/skills/agent-preflight/SKILL.md .claude/skills \
  .cursor/skills/agent-preflight/SKILL.md scripts/handoff-check.sh
fail .agents/skills/verify/SKILL.md scripts/check-agent-layout.sh .agents/skills/verify/SKILL.md
fail .claude/skills/verify/SKILL.md policy/author .claude/skills/verify/SKILL.md

bin=$(mktemp -d)
cat >"$bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "api repos/acme/app/pulls/7 --jq .changed_files") printf '%s\n' "$CHANGED" ;;
  "api --paginate repos/acme/app/pulls/7/files?per_page=100 "*) printf '%b' "$ROWS" ;;
  *) printf 'unexpected gh: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
chmod +x "$bin/gh"
live() {
  CHANGED=$1 ROWS=$2 PATH="$bin:$PATH" "$check" --repo acme/app --number 7 >/dev/null 2>"$err"
}
if ! live 2 'src/a.ts\t\nsrc/b.ts\t\n'; then
  printf 'a feature pull should pass:\n' >&2
  cat "$err" >&2
  exit 1
fi
if live 2 'src/a.ts\t\npolicy/author\t\n'; then
  printf 'a live mixed pull should fail\n' >&2
  exit 1
fi
if live 1 'src/renamed.ts\tpolicy/author\n'; then
  printf 'moving a guardrail out to another path should fail\n' >&2
  exit 1
fi
if live 3001 'src/a.ts\t\n'; then
  printf 'an incomplete file list must fail, not pass\n' >&2
  exit 1
fi
if ! grep -q 'lists 1 of 3001' "$err"; then
  printf 'the failure should say the list is incomplete:\n' >&2
  cat "$err" >&2
  exit 1
fi
rm -rf "$bin"

printf 'guardrails alone ok\n'
