#!/usr/bin/env bash
# One pull request, one job.
# Fails when a later pull request has been merged into a pull that is still
# open, unless policy/backlog-recovery on the default branch lists this pull.
# The check reads origin/<default>:policy/backlog-recovery, never the pull's
# head or a base the pull chose. A missing file or a failed read counts as not
# listed.
# Adding a number is Tier A. The label approach was dropped because agents
# hold Jhonny's credentials. Keep-current and restack are not pull requests
# and do not trip this.
# Fails when stack depth is over 2, or this pull is the 6th or later open
# pull request, not counting the integration pull request.
# Merges into an open refactor/run-<nn> integration pull request are the
# run's normal merges, so that pull request is not the later-merge failure.
set -euo pipefail

usage() {
  printf 'usage: check-one-pr.sh (--prs <file> | --repo <owner/name>) --number <n> [--default-branch <name>]\n' >&2
  exit 2
}

prs=
repo=
number=
default_branch=
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
    --default-branch)
      default_branch=$2
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
live=0
if [[ -z $prs ]]; then
  if [[ -z $repo ]]; then
    usage
  fi
  prs=$(mktemp)
  owned=1
  live=1
  view=$(mktemp)
  open=$(mktemp)
  merged=$(mktemp)
  gh pr view "$number" --repo "$repo" \
    --json number,state,createdAt,baseRefName,headRefName,isDraft >"$view"
  head_ref=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefName"])' "$view")
  gh api --paginate --slurp "repos/${repo}/pulls?state=open&per_page=100" >"$open"
  gh pr list --repo "$repo" --state merged --base "$head_ref" --limit 1000 \
    --json number,state,createdAt,baseRefName,headRefName,isDraft >"$merged"
  python3 - "$view" "$open" "$merged" >"$prs" <<'PY'
import json
import sys


def flatten(data):
    if isinstance(data, dict):
        return [data]
    rows = []
    for item in data:
        if isinstance(item, list):
            rows.extend(item)
        elif isinstance(item, dict):
            rows.append(item)
    return rows


def row(item):
    if "headRefName" in item or "baseRefName" in item:
        base = item.get("baseRefName") or ""
        head = item.get("headRefName") or ""
        created = item.get("createdAt") or ""
        draft = item.get("isDraft")
    else:
        base = (item.get("base") or {}).get("ref") or ""
        head = (item.get("head") or {}).get("ref") or ""
        created = item.get("created_at") or ""
        draft = item.get("draft")
    return {
        "number": int(item["number"]),
        "state": str(item.get("state") or "").upper(),
        "createdAt": created,
        "baseRefName": base,
        "headRefName": head,
        "isDraft": bool(draft),
    }


seen = {}
for path in sys.argv[1:]:
    for item in flatten(json.load(open(path))):
        if "number" not in item:
            continue
        pulled = row(item)
        seen[pulled["number"]] = pulled
json.dump(list(seen.values()), sys.stdout)
PY
  rm -f "$view" "$open" "$merged"
  if [[ -z $default_branch ]]; then
    default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
  fi
fi

set +e
python3 - "$prs" "$number" "$live" "${default_branch:-main}" <<'PY'
import json
import re
import subprocess
import sys

# rules.md Merging: stack depth at most 2, at most 5 open PRs.
# Open no new pull request: the oldest MAX_OPEN stay allowed.
MAX_DEPTH = 2
MAX_OPEN = 5
INTEGRATION = re.compile(r"refactor/run-[0-9]+\Z")
BASE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]*\Z")
FOLD_NEXT = (
    "Redo per merge-playbook.md section 10, or ask Jhonny to list the pull in policy/backlog-recovery."
)

path, number, live, default_branch = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "1", sys.argv[4]
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


def ordinal(n):
    if 10 <= n % 100 <= 20:
        suffix = "th"
    else:
        suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
    return f"{n}{suffix}"


def show_recovery(base):
    if not base or ".." in base or not BASE_NAME.fullmatch(base):
        return None
    spec = f"origin/{base}:policy/backlog-recovery"

    def show():
        return subprocess.run(
            ["git", "show", spec],
            capture_output=True,
            text=True,
        )

    proc = show()
    if proc.returncode != 0 and live:
        shallow = subprocess.run(
            ["git", "rev-parse", "--is-shallow-repository"],
            capture_output=True,
            text=True,
        ).stdout.strip()
        depth = ["--depth", "1"] if shallow == "true" else []
        subprocess.run(
            ["git", "fetch", *depth, "origin", base],
            capture_output=True,
            text=True,
        )
        proc = show()
    if proc.returncode != 0:
        return None
    return proc.stdout


def listed(text, pull):
    if text is None:
        return False
    for line in text.splitlines():
        body = line.split("#", 1)[0].strip()
        if body.isdigit() and int(body) == pull:
            return True
    return False


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

recovery_ok = listed(show_recovery(default_branch), current["number"])
if not integration(current["head"]) and not recovery_ok:
    for other in prs:
        if other["number"] == current["number"]:
            continue
        if other["state"] != "MERGED":
            continue
        if other["base"] != current["head"]:
            continue
        if other["created"] > current["created"]:
            messages.append(
                f"pull request #{current['number']} is still open and later pull request #{other['number']} was merged into {current['head']}. {FOLD_NEXT}"
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
    messages.append(f"stack depth {depth} is over the limit of {MAX_DEPTH}")

open_prs = sorted(
    (pr for pr in prs if pr["state"] == "OPEN" and not integration(pr["head"])),
    key=lambda pr: (pr["created"], pr["number"]),
)
if len(open_prs) > MAX_OPEN:
    for rank, pr in enumerate(open_prs):
        if pr["number"] != current["number"] or rank < MAX_OPEN:
            continue
        place = ordinal(rank + 1)
        messages.append(
            f"pull #{current['number']} is the {place} open pull; the limit is {MAX_OPEN}"
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
