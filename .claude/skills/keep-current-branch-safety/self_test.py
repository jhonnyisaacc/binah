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
BASELINE = {(DR, "open-head-kept"), (DR, "open-base-kept"), (DR, "unlanded-work-kept")}

NO_OPEN_CHECK = [('for base in $open_bases; do', 'for base in ; do')]
NO_HEAD_LIST = [("jq -r '.[].baseRefName, .[].headRefName')", "jq -r '.[].baseRefName')")]
NO_TIP_CHECK = [(
    '[[ $(git -C "$workdir" rev-parse "origin/${branch}" 2>/dev/null || true) == "$merged_oid" ]]; then',
    'true; then',
)]
NO_PROTECTION = [('if protected_branch "$branch"; then', 'if false; then')]
READ_ORDER = [(
    '''  open=$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName,baseRefName)
  merged=$(gh pr list --repo "$repo" --state merged --limit 200 --json headRefName,headRefOid)
''',
    '''  merged=$(gh pr list --repo "$repo" --state merged --limit 200 --json headRefName,headRefOid)
  open=$(gh pr list --repo "$repo" --state open --limit 200 --json number,headRefName,baseRefName)
''',
)]

VARIANTS = [
    ("real script", [], BASELINE),
    ("open-list check removed", NO_OPEN_CHECK,
     BASELINE | {(BR, "open-base-kept"), (BR, "open-head-kept")}),
    ("open heads not read", NO_HEAD_LIST, BASELINE | {(BR, "open-head-kept")}),
    ("tip check removed", NO_TIP_CHECK, BASELINE | {(BR, "unlanded-work-kept")}),
    ("branch protection removed", NO_PROTECTION,
     {(BR, "protected-branch-kept"), (DR, "protected-branch-kept"),
      (DR, "open-base-kept"), (DR, "unlanded-work-kept")}),
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
