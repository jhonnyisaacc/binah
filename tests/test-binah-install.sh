#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
install=$root/scripts/binah-install
tmp=$(mktemp -d)

copied='scripts/check-branch-name.sh scripts/check-pr-body.sh scripts/agent-preflight.sh scripts/check-one-pr.sh scripts/check-secrets.sh scripts/check-guardrails-alone.sh'
required='scripts/check-branch-name.sh scripts/check-pr-body.sh scripts/check-one-pr.sh scripts/check-secrets.sh scripts/check-guardrails-alone.sh'

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
  if grep -q 'agent-preflight.sh' "$wf" || grep -q 'SSH_SIGNING_KEY' "$wf"; then
    printf 'hygiene must not run the signing preflight\n' >&2
    cat "$wf" >&2
    exit 1
  fi
  if grep -w -q unlabeled "$wf" || grep -q 'issues: read' "$wf"; then
    printf 'hygiene must not use label events\n' >&2
    cat "$wf" >&2
    exit 1
  fi
  if grep -q 'fetch-depth: 0' "$wf"; then
    printf 'workflow enables fetch-depth: 0\n' >&2
    exit 1
  fi
  if grep -q 'Current tree only' "$wf" && ! grep -q 'fetch-depth: 1' "$wf"; then
    printf 'a new hygiene workflow should check out the current tree\n' >&2
    exit 1
  fi
  if ! grep -q 'RUNNER_TEMP/binah-base' "$wf"; then
    printf 'hygiene does not check the base out into a separate directory\n' >&2
    exit 1
  fi
  for script in scripts/check-branch-name.sh scripts/check-pr-body.sh scripts/check-one-pr.sh scripts/check-secrets.sh; do
    if ! grep -q "binah-base/$script" "$wf"; then
      printf 'hygiene does not run %s from the base checkout\n' "$script" >&2
      exit 1
    fi
  done
  if ! grep -q 'GITHUB_WORKSPACE' "$wf"; then
    printf 'the secret scan should read the pull tree\n' >&2
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
for script in $copied; do
  if [[ ! -f $fresh/$script ]]; then
    printf 'install did not copy %s\n' "$script" >&2
    exit 1
  fi
done
if [[ ! -f $fresh/policy/backlog-recovery ]]; then
  printf 'install did not copy policy/backlog-recovery\n' >&2
  exit 1
fi
if ! grep -q -F 'refactor/run-[0-9][0-9]' "$fresh/policy/integration-branches"; then
  printf 'install did not copy the default integration branch\n' >&2
  exit 1
fi
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
mkdir -p "$existing/policy"
printf '99\n' >"$existing/policy/backlog-recovery"
printf 'feat/davar-v2\n' >"$existing/policy/integration-branches"
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
if [[ $(cat "$existing/policy/backlog-recovery") != '99' ]]; then
  printf 'install replaced an existing policy/backlog-recovery\n' >&2
  exit 1
fi
if [[ $(cat "$existing/policy/integration-branches") != 'feat/davar-v2' ]]; then
  printf 'install replaced an existing policy/integration-branches\n' >&2
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

# fetch-depth: 0 on the hygiene checkout fails even when it sits outside the marker block.
history=$tmp/history
mkdir -p "$history/.github/workflows"
cat >"$history/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  pull_request:
jobs:
  hygiene:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      # BEGIN binah hygiene
      - name: branch name
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-branch-name.sh"
      - name: pull request body
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-pr-body.sh"
      - name: one pull request, one job
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-one-pr.sh"
      - name: secret scan
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-secrets.sh"
      - name: guardrail changes ride alone
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-guardrails-alone.sh"
      # END binah hygiene
EOF
if bash "$install" --check "$history" >/dev/null 2>"$tmp/err"; then
  printf 'fetch-depth: 0 on the hygiene checkout should fail\n' >&2
  exit 1
fi
if ! grep -q 'fetch-depth: 0' "$tmp/err"; then
  printf 'checkout history error should name fetch-depth: 0\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

# The same text in another job is not the hygiene checkout.
shallow=$tmp/shallow
mkdir -p "$shallow/.github/workflows"
cat >"$shallow/.github/workflows/ci.yml" <<'EOF'
name: CI
on:
  pull_request:
jobs:
  hygiene:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 1
      # BEGIN binah hygiene
      - name: branch name
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-branch-name.sh"
      - name: pull request body
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-pr-body.sh"
      - name: one pull request, one job
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-one-pr.sh"
      - name: secret scan
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-secrets.sh"
      - name: guardrail changes ride alone
        run: bash "$RUNNER_TEMP/binah-base/scripts/check-guardrails-alone.sh"
      # END binah hygiene
  other:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
EOF
if ! bash "$install" --check "$shallow" >/dev/null 2>"$tmp/err"; then
  printf 'fetch-depth: 0 outside the hygiene job should not fail:\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

write_checkout() {
  local dir=$1
  local step=$2
  mkdir -p "$dir/.github/workflows"
  {
    printf 'name: CI\non:\n  pull_request:\njobs:\n  hygiene:\n    runs-on: ubuntu-latest\n    steps:\n'
    printf '%s\n' "$step"
    printf '      # BEGIN binah hygiene\n'
    printf '      - name: branch name\n        run: bash "$RUNNER_TEMP/binah-base/scripts/check-branch-name.sh"\n'
    printf '      - name: pull request body\n        run: bash "$RUNNER_TEMP/binah-base/scripts/check-pr-body.sh"\n'
    printf '      - name: one pull request, one job\n        run: bash "$RUNNER_TEMP/binah-base/scripts/check-one-pr.sh"\n'
    printf '      - name: secret scan\n        run: bash "$RUNNER_TEMP/binah-base/scripts/check-secrets.sh"\n'
    printf '      - name: guardrail changes ride alone\n        run: bash "$RUNNER_TEMP/binah-base/scripts/check-guardrails-alone.sh"\n'
    printf '      # END binah hygiene\n'
  } >"$dir/.github/workflows/ci.yml"
}

case_number=0
for step in \
  $'      - uses: actions/checkout@v4\n        with:\n          fetch-depth: "0"' \
  $'      - uses: actions/checkout@v4\n        with:\n          fetch-depth: \'0\'' \
  $'      - uses: actions/checkout@v4\n        with:\n          "fetch-depth": 0' \
  $'      - uses: actions/checkout@v4\n        with: {fetch-depth: 0}' \
  $'      - uses: actions/checkout@v4\n        with: {fetch-depth: 0, ref: main}' \
  $'      - uses: actions/checkout@v4\n        with:\n          fetch-depth: 0 # all history' \
  $'      - name: check out\n        uses: "actions/checkout@v4"\n        with:\n          fetch-depth: 0'; do
  case_number=$((case_number + 1))
  dir=$tmp/depth-bad-$case_number
  write_checkout "$dir" "$step"
  if bash "$install" --check "$dir" >/dev/null 2>"$tmp/err"; then
    printf 'full history checkout should fail:\n%s\n' "$step" >&2
    exit 1
  fi
done

case_number=0
for step in \
  $'      - uses: actions/checkout@v4\n        with:\n          # fetch-depth: 0 was too slow\n          fetch-depth: 1' \
  $'      - uses: actions/checkout@v4\n        with:\n          fetch-depth: 1 # not fetch-depth: 0' \
  $'      - uses: actions/checkout@v4\n        with:\n          fetch-depth: 10' \
  $'      - name: notes about actions/checkout\n        run: echo "fetch-depth: 0"' \
  $'      # uses: actions/checkout@v3 with fetch-depth: 0\n      - uses: actions/checkout@v4'; do
  case_number=$((case_number + 1))
  dir=$tmp/depth-ok-$case_number
  write_checkout "$dir" "$step"
  if ! bash "$install" --check "$dir" >/dev/null 2>"$tmp/err"; then
    printf 'this checkout should pass:\n%s\n' "$step" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
done

write_job() {
  local dir=$1
  local body=$2
  mkdir -p "$dir/.github/workflows"
  printf 'name: CI\non:\n  pull_request:\njobs:\n  hygiene:\n%s\n' "$body" >"$dir/.github/workflows/ci.yml"
}

case_number=0
for body in \
  $'    runs-on: ubuntu-latest\n    steps: []' \
  $'    runs-on: ubuntu-latest\n    steps: *shared' \
  $'    uses: ./.github/workflows/reuse.yml'; do
  case_number=$((case_number + 1))
  dir=$tmp/shape-bad-$case_number
  write_job "$dir" "$body"
  cp "$dir/.github/workflows/ci.yml" "$tmp/before.yml"
  if bash "$install" "$dir" >/dev/null 2>"$tmp/err"; then
    printf 'install should refuse this job:\n%s\n' "$body" >&2
    exit 1
  fi
  if ! grep -q 'cannot wire the hygiene job' "$tmp/err"; then
    printf 'install should say why it refused:\n' >&2
    cat "$tmp/err" >&2
    exit 1
  fi
  if ! cmp -s "$tmp/before.yml" "$dir/.github/workflows/ci.yml"; then
    printf 'a refused install changed the workflow:\n%s\n' "$body" >&2
    exit 1
  fi
done

trailing=$tmp/shape-trailing
write_job "$trailing" $'    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n    timeout-minutes: 5'
bash "$install" "$trailing" >/dev/null
tail_line=$(tail -n 1 "$trailing/.github/workflows/ci.yml")
if [[ $tail_line != '    timeout-minutes: 5' ]]; then
  printf 'the steps must stay inside steps:, before later job keys:\n' >&2
  cat "$trailing/.github/workflows/ci.yml" >&2
  exit 1
fi

nocheckout=$tmp/shape-nocheckout
write_job "$nocheckout" $'    runs-on: ubuntu-latest\n    steps:\n      - run: echo first'
bash "$install" "$nocheckout" >/dev/null
if ! grep -q 'actions/checkout@' "$nocheckout/.github/workflows/ci.yml"; then
  printf 'a job with no checkout needs one before the gates\n' >&2
  exit 1
fi

nosteps=$tmp/shape-nosteps
write_job "$nosteps" '    runs-on: ubuntu-latest'
bash "$install" "$nosteps" >/dev/null
if ! grep -q 'actions/checkout@' "$nosteps/.github/workflows/ci.yml"; then
  printf 'a job with no steps needs a checkout before the gates\n' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'binah-install ok\n'
