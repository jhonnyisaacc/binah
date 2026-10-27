#!/usr/bin/env bash
# One pull request, one job.
# Fails when a later pull request has been merged into a pull that is still
# open. Fails when the pull is too big for the stack limits in rules.md
# (Merging) and merge-playbook.md section 3: stack depth at most 2, and at
# most 5 open pull requests not counting the integration pull request.
# The smaller cap is 2. An empty template sentence is not a pass.
# Merges into an open refactor/run-<nn> integration pull request are the
# run's normal merges, so that pull request is not the later-merge failure.
set -euo pipefail

usage() {
  printf 'usage: check-one-pr.sh (--prs <file> | --repo <owner/name>) --number <n>\n' >&2
  exit 2
}

prs=
repo=
number=
while [[ $# -gt 0 ]]; do
  case $1 in
    --prs)
      prs=$2
      shift
      ;;
    --repo)
      repo=$2
      shift
      ;;
    --number)
      number=$2
      shift
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      usage
      ;;
  esac
  shift
done

if [[ -z $number ]]; then
  usage
fi
owned=
if [[ -z $prs ]]; then
  if [[ -z $repo ]]; then
    usage
  fi
  prs=$(mktemp)
  owned=1
  gh pr list --repo "$repo" --state all --limit 200 \
    --json number,state,createdAt,baseRefName,headRefName,isDraft >"$prs"
fi

set +e
python3 - "$prs" "$number" <<'PY'
import json
import re
import sys

# rules.md Merging: "stack depth at most 2" and "at most 5 open PRs".
# merge-playbook.md section 3 states the same numbers. Smaller cap is 2.
MAX_DEPTH = 2
MAX_OPEN = 5
INTEGRATION = re.compile(r"refactor/run-[0-9]+\Z")

path, number = sys.argv[1], int(sys.argv[2])
try:
    data = json.load(open(path))
except json.JSONDecodeError:
    print("pull request list must be a JSON array, not a template sentence", file=sys.stderr)
    sys.exit(2)
if not isinstance(data, list):
    print("pull request list must be a JSON array", file=sys.stderr)
    sys.exit(2)


def norm(pr):
    return {
        "number": int(pr["number"]),
        "state": str(pr.get("state") or "").upper(),
        "created": str(pr.get("createdAt") or ""),
        "base": str(pr.get("baseRefName") or ""),
        "head": str(pr.get("headRefName") or ""),
    }


prs = [norm(pr) for pr in data]
current = next((pr for pr in prs if pr["number"] == number), None)
if current is None:
    print(f"pull request #{number} is not in the list", file=sys.stderr)
    sys.exit(2)
if current["state"] != "OPEN":
    sys.exit(0)


def integration(name):
    return INTEGRATION.fullmatch(name) is not None


by_head = {pr["head"]: pr for pr in prs if pr["state"] == "OPEN"}
messages = []

if not integration(current["head"]):
    for other in prs:
        if other["number"] == current["number"]:
            continue
        if other["state"] != "MERGED":
            continue
        if other["base"] != current["head"]:
            continue
        if other["created"] > current["created"]:
            messages.append(
                f"pull request #{current['number']} is still open and later pull request #{other['number']} was merged into {current['head']}"
            )

seen = set()
depth = 1
base = current["base"]
while base not in seen:
    seen.add(base)
    if integration(base):
        break
    parent = by_head.get(base)
    if parent is None or integration(parent["head"]):
        break
    depth += 1
    base = parent["base"]
if depth > MAX_DEPTH:
    messages.append(
        f"pull is too big: stack depth {depth} is over the limit of {MAX_DEPTH} (rules.md: stack depth at most 2)"
    )

open_count = sum(1 for pr in prs if pr["state"] == "OPEN" and not integration(pr["head"]))
if open_count > MAX_OPEN:
    messages.append(
        f"pull is too big: {open_count} open pull requests is over the limit of {MAX_OPEN} (rules.md: at most 5 open PRs)"
    )

if messages:
    for message in messages:
        print(message, file=sys.stderr)
    sys.exit(1)
PY
status=$?
set -e
if [[ -n $owned ]]; then
  rm -f "$prs"
fi
exit "$status"
