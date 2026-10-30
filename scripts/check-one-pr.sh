#!/usr/bin/env bash
# One pull request, one job.
# Fails when a later pull request has been merged into a pull that is still
# open. A bottom pull request labeled backlog-recovery is the backlog
# recovery fold (children merged into that pull). That fold passes. A fold
# without the label still fails. Keep-current and restack are not pull
# requests and do not trip this.
# Fails when the pull is too big for the stack limits in rules.md
# (Merging) and merge-playbook.md section 3: stack depth at most 2, and at
# most 5 open pull requests not counting the integration pull request.
# Open no new pull request: ordered by createdAt ascending, the oldest 5
# stay allowed and the 6th and later fail.
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
    --json number,state,createdAt,baseRefName,headRefName,isDraft,labels >"$prs"
fi

set +e
python3 - "$prs" "$number" <<'PY'
import json
import re
import sys

# rules.md Merging: "stack depth at most 2" and "at most 5 open PRs".
# merge-playbook.md section 3 states the same numbers. Smaller cap is 2.
# Open no new pull request: the oldest MAX_OPEN stay allowed.
# backlog-recovery on the still-open bottom pull is the recovery fold.
MAX_DEPTH = 2
MAX_OPEN = 5
RECOVERY = "backlog-recovery"
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


def label_names(pr):
    names = []
    for label in pr.get("labels") or []:
        if isinstance(label, str):
            names.append(label)
        elif isinstance(label, dict):
            names.append(str(label.get("name") or ""))
    return names


def norm(pr):
    return {
        "number": int(pr["number"]),
        "state": str(pr.get("state") or "").upper(),
        "created": str(pr.get("createdAt") or ""),
        "base": str(pr.get("baseRefName") or ""),
        "head": str(pr.get("headRefName") or ""),
        "labels": label_names(pr),
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

if not integration(current["head"]) and RECOVERY not in current["labels"]:
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

open_prs = sorted(
    (pr for pr in prs if pr["state"] == "OPEN" and not integration(pr["head"])),
    key=lambda pr: (pr["created"], pr["number"]),
)
if len(open_prs) > MAX_OPEN:
    for rank, pr in enumerate(open_prs):
        if pr["number"] != current["number"] or rank < MAX_OPEN:
            continue
        messages.append(
            f"pull is too big: open pull request #{current['number']} is past the oldest {MAX_OPEN} and over the limit of {MAX_OPEN} (rules.md: at most 5 open PRs; open no new PR)"
        )
        break

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
