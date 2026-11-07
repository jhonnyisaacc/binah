#!/usr/bin/env python3
"""Run the branch-safety check. Exit 0: matches expected-findings.txt. 1: results differ. 3: model drift."""
import argparse
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model
import probe


def repo_root():
    return subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=HERE,
                          check=True, capture_output=True, text=True).stdout.strip()


def expected_findings():
    with open(os.path.join(HERE, "expected-findings.txt")) as f:
        lines = (line.split("#")[0].strip() for line in f)
        return {tuple(line.split()) for line in lines if line}


def evaluate(script_path):
    """Return ({(mode, property): shortest path}, {mode: states explored})."""
    decision = probe.measure(script_path)
    broken, states = {}, {}
    for mode in model.MODES:
        found, states[mode] = model.explore(decision, mode)
        for name, path in found.items():
            broken[(mode, name)] = path
    return broken, states


def sync_warning(root):
    with open(os.path.join(HERE, "SKILL.md")) as f:
        match = re.search(r"Sync commit: `([0-9a-f]+)`", f.read())
    if not match:
        return "SKILL.md has no sync commit."
    sha = match.group(1)
    covered = "scripts/keep-current.sh"
    log = subprocess.run(["git", "log", "--oneline", f"{sha}..HEAD", "--", covered],
                         cwd=root, capture_output=True, text=True)
    dirty = subprocess.run(["git", "status", "--porcelain", "--", covered],
                           cwd=root, capture_output=True, text=True).stdout.strip()
    if log.returncode != 0:
        return f"sync commit {sha} is not in this history. Reconfirm the model and move it."
    if log.stdout.strip() or dirty:
        return (f"{covered} changed since sync commit {sha}. Reread the model against it "
                "before trusting a pass.")
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--script", help="check this copy of keep-current.sh instead of the repo's")
    args = parser.parse_args()
    root = repo_root()
    script = args.script or os.path.join(root, "scripts", "keep-current.sh")

    warning = None if args.script else sync_warning(root)
    if warning:
        print(f"STALE: {warning}\n")
    try:
        broken, states = evaluate(script)
    except probe.ModelDrift as drift:
        print(f"MODEL DRIFT: {drift}")
        return 3

    expected = expected_findings()
    differs = False
    print(f"Branches: {', '.join(model.BRANCHES)}. Keep-current runs: {model.MAX_RUNS}.")
    for mode in model.MODES:
        commits, prs = model.BOUNDS[mode]
        print(f"\n{mode}: {commits - 1} new commits, {prs} PRs, {states[mode]} states")
        for name, rule in model.PROPERTIES.items():
            key = (mode, name)
            if key in broken:
                known = key in expected
                differs = differs or not known
                print(f"  {'KNOWN FINDING' if known else 'NEW VIOLATION'}  {name}: {rule}")
                for i, event in enumerate(broken[key], 1):
                    print(f"      {i}. {event}")
            elif key in expected:
                differs = True
                print(f"  NOW HOLDS  {name}: remove `{mode} {name}` from expected-findings.txt")
            else:
                print(f"  holds  {name}")
    print("\nRESULT: " + ("differs from expected-findings.txt" if differs
                          else "matches expected-findings.txt"))
    return 1 if differs else 0


if __name__ == "__main__":
    sys.exit(main())
