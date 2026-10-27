#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
install=$root/scripts/binah-install
tmp=$(mktemp -d)

required='scripts/check-branch-name.sh scripts/check-pr-body.sh scripts/agent-preflight.sh scripts/check-one-pr.sh scripts/check-secrets.sh'

assert_wired() {
  local dest=$1
  local wf
  wf=$(find "$dest/.github/workflows" -type f \( -name '*.yml' -o -name '*.yaml' \) -print)
  for script in $required; do
    if ! grep -q "$script" "$wf"; then
      printf 'workflow does not run %s\n' "$script" >&2
      cat "$wf" >&2
      exit 1
    fi
  done
  if grep -q 'fetch-depth: 0' "$wf"; then
    printf 'workflow enables fetch-depth: 0\n' >&2
    exit 1
  fi
  if grep -q 'Current tree only' "$wf" && ! grep -q 'fetch-depth: 1' "$wf"; then
    printf 'a new hygiene workflow should check out the current tree\n' >&2
    exit 1
  fi
  if ! bash "$install" --check "$dest"; then
    printf 'binah-install --check should pass\n' >&2
    exit 1
  fi
}

fresh=$tmp/fresh
mkdir -p "$fresh"
bash "$install" "$fresh" >/dev/null
for script in $required; do
  if [[ ! -f $fresh/$script ]]; then
    printf 'install did not copy %s\n' "$script" >&2
    exit 1
  fi
done
assert_wired "$fresh"
if [[ $(grep -c '^  hygiene:' "$fresh/.github/workflows/hygiene.yml") -ne 1 ]]; then
  printf 'a new repo should get one hygiene job\n' >&2
  exit 1
fi

# Copying the files without the workflow calls is not enough.
sentence=$tmp/sentence
mkdir -p "$sentence/.github/workflows"
cat >"$sentence/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  pull_request:
jobs:
  hygiene:
    runs-on: ubuntu-latest
    steps:
      - name: template
        run: echo "Why, What changed, and How to test. One pull request, one job."
EOF
if bash "$install" --check "$sentence" >/dev/null 2>"$tmp/err"; then
  printf 'a template sentence in the workflow should fail\n' >&2
  exit 1
fi
if ! grep -q 'check-pr-body.sh' "$tmp/err"; then
  printf 'missing-script error should name check-pr-body.sh\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

existing=$tmp/existing
mkdir -p "$existing/.github/workflows"
git init -q "$existing"
cat >"$existing/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  pull_request:
jobs:
  hygiene:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: lint
        run: bun test
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo other
EOF
cat >"$existing/rules.md" <<'EOF'
Enforcement: `scripts/check-pr-body.sh`. Calling it from each repo's `hygiene` job is (planned) until Refa wires it.
Fast tier: pull request body (planned), secret scan.
A required `stack-limits` step in `hygiene` fails a PR that breaks either limit (planned until built).
A generic gate that refuses to mark a pull request ready belongs in pstack and is (planned) here.
EOF
bash "$install" "$existing" >/dev/null
assert_wired "$existing"
if [[ $(grep -c '^  hygiene:' "$existing/.github/workflows/ci.yml") -ne 1 ]]; then
  printf 'install should edit the existing hygiene job\n' >&2
  exit 1
fi
if ! grep -q 'bun test' "$existing/.github/workflows/ci.yml"; then
  printf 'install dropped the existing lint step\n' >&2
  exit 1
fi
if ! grep -q 'echo other' "$existing/.github/workflows/ci.yml"; then
  printf 'install changed the other job\n' >&2
  exit 1
fi
if grep -F -q 'pull request body (planned)' "$existing/rules.md"; then
  printf 'body check is still planned\n' >&2
  exit 1
fi
if grep -F -q 'planned until built' "$existing/rules.md"; then
  printf 'stack limit is still planned\n' >&2
  exit 1
fi
if ! grep -F -q '(planned) here' "$existing/rules.md"; then
  printf 'unrelated planned mark was removed\n' >&2
  exit 1
fi

before=$(find "$existing" -type f -exec sha256sum {} \; | sort)
bash "$install" "$existing" >/dev/null
after=$(find "$existing" -type f -exec sha256sum {} \; | sort)
if [[ $before != "$after" ]]; then
  printf 'second install changed files\n' >&2
  diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
  exit 1
fi

named=$tmp/named
mkdir -p "$named/.github/workflows"
cat >"$named/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  pull_request:
jobs:
  lint:
    name: hygiene
    runs-on: ubuntu-latest
    steps:
      - run: echo keep
EOF
bash "$install" "$named" >/dev/null
if ! grep -q 'echo keep' "$named/.github/workflows/ci.yml"; then
  printf 'named hygiene job lost its step\n' >&2
  exit 1
fi
if [[ -f $named/.github/workflows/hygiene.yml ]]; then
  printf 'named hygiene job should be edited, not duplicated\n' >&2
  exit 1
fi
assert_wired "$named"

# The old name calls binah-install.
if ! grep -q 'binah-install' "$root/scripts/install-policy-kit.sh"; then
  printf 'install-policy-kit.sh should call binah-install\n' >&2
  exit 1
fi
caller=$tmp/caller
mkdir -p "$caller"
bash "$root/scripts/install-policy-kit.sh" "$caller" >/dev/null
assert_wired "$caller"

rm -rf "$tmp"
printf 'binah-install ok\n'
