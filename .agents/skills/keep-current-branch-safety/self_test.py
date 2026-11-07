#!/usr/bin/env python3
"""Prove the check can fail: break or fix a scratch copy of keep-current.sh and assert the verdict."""
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import check
import probe

BR, DR = "between-runs", "during-run"
BASELINE = {(DR, "open-base-kept")}

NO_OPEN_CHECK = [('for base in $open_bases; do', 'for base in ; do')]
NO_HEAD_LIST = [("jq -r '.[].baseRefName, .[].headRefName'", "jq -r '.[].baseRefName'")]
LEASE = '--force-with-lease="refs/heads/${branch}:${merged_oid}" '
NO_LEASE = [(LEASE, "")]
NO_TIP_NO_LEASE = [(LEASE, ""), ('[[ $tip != "$merged_oid" ]] || protected_branch', 'protected_branch')]
NO_REREAD = [('! open_now=$(read_open_branches "$repo") || ', 'open_now=$(printf "%s" "$open" | jq -r ".[].baseRefName, .[].headRefName"); ')]
NO_PROTECTION = [
    ('if protected_branch "$branch"; then', 'if false; then'),
    ('[[ $tip != "$merged_oid" ]] || protected_branch "$branch"', '[[ $tip != "$merged_oid" ]]'),
]
READ_ORDER = [(
    '''  open=$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName,baseRefName)
  merged=$(gh pr list --repo "$repo" --state merged --limit 200 --json headRefName,headRefOid)
''',
    '''  merged=$(gh pr list --repo "$repo" --state merged --limit 200 --json headRefName,headRefOid)
  open=$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName,baseRefName)
''',
)]

OPEN_HEAD = (DR, "open-head-kept")
VARIANTS = [
    ("real script", [], BASELINE),
    ("open-list check removed", NO_OPEN_CHECK,
     BASELINE | {OPEN_HEAD, (BR, "open-base-kept"), (BR, "open-head-kept")}),
    ("open heads not read", NO_HEAD_LIST, BASELINE | {OPEN_HEAD, (BR, "open-head-kept")}),
    ("delete lease removed", NO_LEASE, BASELINE | {OPEN_HEAD, (DR, "unlanded-work-kept")}),
    ("tip check and lease removed", NO_TIP_NO_LEASE,
     BASELINE | {OPEN_HEAD, (BR, "unlanded-work-kept"), (DR, "unlanded-work-kept")}),
    ("branch protection removed", NO_PROTECTION,
     {(BR, "protected-branch-kept"), (DR, "protected-branch-kept"), (DR, "open-base-kept")}),
    ("no reread before delete", NO_REREAD, None),
    ("merged list read first", READ_ORDER, None),
]


def apply_edits(text, edits):
    for old, new in edits:
        if text.count(old) != 1:
            raise SystemExit(f"self-test edit no longer applies, update self_test.py: {old!r}")
        text = text.replace(old, new)
    return text


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE, check=True,
                          capture_output=True, text=True).stdout.strip()
    with open(os.path.join(root, "scripts", "keep-current.sh")) as f:
        source = f.read()
    failed = False
    for name, edits, want in VARIANTS:
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
            f.write(apply_edits(source, edits))
        try:
            got = set(check.evaluate(f.name)[0])
        except probe.ModelDrift:
            got = None
        finally:
            os.unlink(f.name)
        ok = got == want
        failed = failed or not ok
        print(f"{'ok  ' if ok else 'FAIL'}  {name}")
        if not ok:
            print(f"      want {want}\n      got  {got}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
