#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
install=$root/scripts/binah-install
tmp=$(mktemp -d)
gates=$tmp/runner/binah-base
mkdir -p "$tmp/runner"

step_run() {
  python3 - "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
start = next(i for i, line in enumerate(lines) if line.strip() == f"- name: {sys.argv[2]}")
indent = len(lines[start]) - len(lines[start].lstrip())
end = start + 1
while end < len(lines) and (len(lines[end]) - len(lines[end].lstrip()) > indent):
    end += 1
step = lines[start + 1 : end]
at = next(i for i, line in enumerate(step) if line.strip().startswith("run:"))
head = step[at].strip()[len("run:"):].strip()
if head == "|":
    body = step[at + 1 :]
    width = len(body[0]) - len(body[0].lstrip())
    print("\n".join(line[width:] for line in body))
else:
    print(head.strip("'"))
PY
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m "$2"
}

new_repo() {
  local name=$1
  git init -q --bare -b main "$tmp/$name.git"
  git init -q -b main "$tmp/$name"
  git -C "$tmp/$name" remote add origin "$tmp/$name.git"
}

run_step() {
  local repo=$1 name=$2 script
  script=$(step_run "$repo/.github/workflows/hygiene.yml" "$name")
  (cd "$repo" && RUNNER_TEMP=$tmp/runner GITHUB_WORKSPACE=$repo GITHUB_EVENT_NAME=pull_request \
    GITHUB_REPOSITORY=acme/app DEFAULT_BRANCH=main bash -e -c "$script")
}

new_repo hostile
bash "$install" "$tmp/hostile" >/dev/null
commit_all "$tmp/hostile" kit
git -C "$tmp/hostile" push -q origin main
git -C "$tmp/hostile" switch -q -c feat/weak
printf '.*\n' >"$tmp/hostile/policy/branch-name.regex"
for script in check-branch-name check-one-pr check-secrets check-pr-body; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/hostile/scripts/$script.sh"
done
printf 'leak.txt\n' >>"$tmp/hostile/policy/secret-allowlist"
printf 'token %s%s\n' 'ghp_' 'abcdefghijklmnopqrstuvwxyz0123456789' >"$tmp/hostile/leak.txt"
printf 'import os\nopen(os.environ["MARK"], "w").close()\nraise SystemExit(0)\n' >"$tmp/hostile/re.py"
commit_all "$tmp/hostile" 'weaken the gates'

workflow=$tmp/hostile/.github/workflows/hygiene.yml
if python3 - "$workflow" <<'PY'
import re, sys
for line in open(sys.argv[1]):
    if "${{" in line and not re.match(r"\s*(\w+:\s*'\$\{\{[^}]*\}\}'|group:.*)\s*$", line):
        print(line, file=sys.stderr)
        raise SystemExit(0)
raise SystemExit(1)
PY
then
  printf 'a run step must read github context through env, not ${{ }}\n' >&2
  exit 1
fi

export MARK=$tmp/mark
run_step "$tmp/hostile" 'check out gates' 2>"$tmp/out"
if grep -q '::warning' "$tmp/out"; then
  printf 'a repo with the kit on its default branch should not warn:\n' >&2
  cat "$tmp/out" >&2
  exit 1
fi
if [[ $(cat "$gates/policy/branch-name.regex") == '.*' ]]; then
  printf 'the gates came from the pull\n' >&2
  exit 1
fi

export PWNED=$tmp/pwned
export HEAD_REF='bad"; touch "$PWNED"; #'
if run_step "$tmp/hostile" 'branch name' >/dev/null 2>&1; then
  printf 'a weak regex on the pull must not pass the branch name\n' >&2
  exit 1
fi
if [[ -e $PWNED ]]; then
  printf 'the branch name ran as a shell command\n' >&2
  exit 1
fi
HEAD_REF=feat/good run_step "$tmp/hostile" 'branch name' >/dev/null

if run_step "$tmp/hostile" 'secret scan' >/dev/null 2>"$tmp/err"; then
  printf 'the pull allowlisted its own secret\n' >&2
  exit 1
fi
if ! grep -q 'leak.txt' "$tmp/err"; then
  printf 'the secret scan should name leak.txt:\n' >&2
  cat "$tmp/err" >&2
  exit 1
fi

cat >"$tmp/prs.json" <<'EOF'
[{"number":1,"state":"OPEN","createdAt":"2026-10-01T00:00:00Z","baseRefName":"main","headRefName":"feat/one"},
 {"number":2,"state":"MERGED","createdAt":"2026-10-02T00:00:00Z","baseRefName":"feat/one","headRefName":"feat/two"}]
EOF
if (cd "$tmp/hostile" && bash "$gates/scripts/check-one-pr.sh" --prs "$tmp/prs.json" --number 1) >/dev/null 2>&1; then
  printf 'the base one-pull gate should fail this pull\n' >&2
  exit 1
fi
if [[ -e $MARK ]]; then
  printf 'a re.py in the pull ran inside the gate\n' >&2
  exit 1
fi

new_repo first
printf 'app\n' >"$tmp/first/README.md"
commit_all "$tmp/first" app
git -C "$tmp/first" push -q origin main
git -C "$tmp/first" switch -q -c feat/install-kit
bash "$install" "$tmp/first" >/dev/null
commit_all "$tmp/first" 'install the kit'
rm -rf "$gates"
run_step "$tmp/first" 'check out gates' 2>"$tmp/out" >>"$tmp/out"
if ! grep -q '::warning::scripts/check-one-pr.sh' "$tmp/out"; then
  printf 'the first install should warn that the pull grades itself:\n' >&2
  cat "$tmp/out" >&2
  exit 1
fi
HEAD_REF=feat/install-kit run_step "$tmp/first" 'branch name' >/dev/null
if HEAD_REF=cursor/bad run_step "$tmp/first" 'branch name' >/dev/null 2>&1; then
  printf 'the first install should still check the branch name\n' >&2
  exit 1
fi

if grep -q 'base_ref' "$workflow"; then
  printf 'the gates must not come from a base the pull chose\n' >&2
  exit 1
fi

downgraded=$tmp/downgraded
mkdir -p "$downgraded/.github/workflows"
sed 's#"$RUNNER_TEMP/binah-base/scripts/check-one-pr.sh"#scripts/check-one-pr.sh#' "$workflow" >"$downgraded/.github/workflows/hygiene.yml"
if bash "$install" --check "$downgraded" >/dev/null 2>"$tmp/err"; then
  printf '%s\n' '--check must fail a gate that runs from the pull' >&2
  exit 1
fi
commented=$tmp/commented
mkdir -p "$commented/.github/workflows"
sed 's#^\( *\)bash "$RUNNER_TEMP/binah-base/scripts/check-secrets.sh".*#\1\# bash "$RUNNER_TEMP/binah-base/scripts/check-secrets.sh"#' "$workflow" >"$commented/.github/workflows/hygiene.yml"
if bash "$install" --check "$commented" >/dev/null 2>"$tmp/err"; then
  printf '%s\n' '--check must not accept a gate named only in a comment' >&2
  exit 1
fi

rm -rf "$tmp"
printf 'hygiene gates ok\n'
