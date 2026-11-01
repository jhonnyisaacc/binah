#!/usr/bin/env bash
# One pull request, one job.
# Fails when a later pull request has been merged into a pull that is still
# open. A bottom pull request labeled backlog-recovery is the backlog
# recovery fold (children merged into that pull). That fold passes only
# when the label event shows the owner in policy/author applied it, the
# same way the Tier A approval label waits on Jhonny. An agent applying
# the label still fails. A fold without the label still fails.
# Keep-current and restack are not pull requests and do not trip this.
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
events=
if [[ -z $prs ]]; then
  if [[ -z $repo ]]; then
    usage
  fi
  prs=$(mktemp)
  owned=1
  gh pr list --repo "$repo" --state all --limit 200 \
    --json number,state,createdAt,baseRefName,headRefName,isDraft,labels >"$prs"
  events=$(mktemp)
  if ! gh api --paginate "repos/${repo}/issues/${number}/events" \
    --jq '.[] | {event,actor:(.actor.login // ""),label:(.label.name // ""),createdAt:(.created_at // "")}' >"$events"; then
    : >"$events"
  fi
fi

owner=
author_file=$(cd "$(dirname "$0")/.." && pwd)/policy/author
if [[ -f $author_file ]]; then
  owner=$(sed -n 's/^name=//p' "$author_file")
fi

set +e
python3 - "$prs" "$number" "$owner" "${events:-}" <<'PY'
import json
import re
import sys

# rules.md Merging: "stack depth at most 2" and "at most 5 open PRs".
# merge-playbook.md section 3 states the same numbers. Smaller cap is 2.
# Open no new pull request: the oldest MAX_OPEN stay allowed.
# backlog-recovery counts only when policy/author applied the current label.
MAX_DEPTH = 2
MAX_OPEN = 5
RECOVERY = "backlog-recovery"
INTEGRATION = re.compile(r"refactor/run-[0-9]+\Z")

path, number, owner = sys.argv[1], int(sys.argv[2]), sys.argv[3]
events_path = sys.argv[4] if len(sys.argv) > 4 else ""
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


def one_event(raw):
    if not isinstance(raw, dict):
        return None
    label = raw.get("label")
    if isinstance(label, dict):
        label = label.get("name")
    actor = raw.get("actor")
    if isinstance(actor, dict):
        actor = actor.get("login")
    created = raw.get("createdAt") or raw.get("created_at") or ""
    return {
        "event": str(raw.get("event") or ""),
        "actor": str(actor or ""),
        "label": str(label or ""),
        "created": str(created),
    }


def parse_events(text):
    text = text.strip()
    if not text:
        return []
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        data = []
        for line in text.splitlines():
            line = line.strip()
            if line:
                data.append(json.loads(line))
    if isinstance(data, dict):
        data = [data]
    return [event for event in (one_event(item) for item in data) if event]


def file_events(events_path):
    if not events_path:
        return []
    try:
        handle = open(events_path)
    except OSError:
        return []
    with handle:
        return parse_events(handle.read())


def norm(pr):
    events = []
    if pr.get("labelEvents") is not None:
        events = [event for event in (one_event(item) for item in pr.get("labelEvents") or []) if event]
    return {
        "number": int(pr["number"]),
        "state": str(pr.get("state") or "").upper(),
        "created": str(pr.get("createdAt") or ""),
        "base": str(pr.get("baseRefName") or ""),
        "head": str(pr.get("headRefName") or ""),
        "labels": label_names(pr),
        "events": events,
    }


prs = [norm(pr) for pr in data]
current = next((pr for pr in prs if pr["number"] == number), None)
if current is None:
    print(f"pull request #{number} is not in the list", file=sys.stderr)
    sys.exit(2)
if not current["events"]:
    current["events"] = file_events(events_path)
if current["state"] != "OPEN":
    sys.exit(0)


def applied_by_owner(events, login):
    last = None
    for event in sorted(events, key=lambda item: item["created"]):
        if event["label"] != RECOVERY:
            continue
        if event["event"] == "unlabeled":
            last = None
        elif event["event"] == "labeled":
            last = event["actor"]
    if not login or not last:
        return False
    return last.casefold() == login.casefold()


def integration(name):
    return INTEGRATION.fullmatch(name) is not None


by_head = {pr["head"]: pr for pr in prs if pr["state"] == "OPEN"}
messages = []

recovery_ok = RECOVERY in current["labels"] and applied_by_owner(current["events"], owner)
if not integration(current["head"]) and not recovery_ok:
    for other in prs:
        if other["number"] == current["number"]:
            continue
        if other["state"] != "MERGED":
            continue
        if other["base"] != current["head"]:
            continue
        if other["created"] > current["created"]:
            note = ""
            if RECOVERY in current["labels"]:
                note = f" ({RECOVERY} counts only when {owner or 'the owner'} applied it)"
            messages.append(
                f"pull request #{current['number']} is still open and later pull request #{other['number']} was merged into {current['head']}{note}"
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
if [[ -n ${events:-} ]]; then
  rm -f "$events"
fi
exit "$status"
