"""Measure what scripts/keep-current.sh really decides, on real git, with a fake gh."""
import concurrent.futures
import itertools
import json
import os
import shutil
import stat
import subprocess
import tempfile

from model import BRANCHES

FAKE_GH = """#!/usr/bin/env python3
import json, os, subprocess, sys
args = sys.argv[1:]
d = os.environ["PROBE_DIR"]
def value(flag):
    return args[args.index(flag) + 1]
with open(os.path.join(d, "log"), "a") as log:
    log.write("gh " + " ".join(args) + "\\n")
if args[:2] == ["pr", "list"] and "--state" in args and "--json" in args:
    reads = os.path.join(d, "open-reads")
    branch = os.environ.get("PROBE_MOVE_ON_REREAD")
    if value("--state") == "open" and branch:
        if os.path.exists(reads):
            git = ["git", "--git-dir", os.path.join(d, "bare")]
            def out(*rest):
                return subprocess.run(git + list(rest), check=True, capture_output=True,
                                      text=True).stdout.strip()
            tree = out("rev-parse", f"refs/heads/{branch}^{{tree}}")
            new = out("commit-tree", tree, "-p", f"refs/heads/{branch}", "-m", "pushed during the run")
            out("update-ref", f"refs/heads/{branch}", new)
        open(reads, "a").close()
    with open(os.path.join(d, value("--state") + ".json")) as f:
        rows = json.load(f)
    fields = value("--json").split(",")
    print(json.dumps([{k: r[k] for k in fields} for r in rows]))
elif args[:2] in (["pr", "close"], ["pr", "comment"]):
    pass
else:
    sys.stderr.write("fake gh does not know: " + " ".join(args) + "\\n")
    sys.exit(64)
"""

FAKE_GIT = """#!/usr/bin/env bash
printf 'git %s\\n' "$*" >>"$PROBE_DIR/log"
exec {real} "$@"
"""


class ModelDrift(Exception):
    """The script no longer behaves in the shape the model assumes."""


def _write_exec(path, text):
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)


def _env(d):
    env = dict(os.environ)
    env.update(
        PATH=os.path.join(d, "bin") + os.pathsep + os.environ["PATH"],
        PROBE_DIR=d,
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_AUTHOR_NAME="probe",
        GIT_AUTHOR_EMAIL="probe@example.com",
        GIT_COMMITTER_NAME="probe",
        GIT_COMMITTER_EMAIL="probe@example.com",
    )
    return env


def _setup(d, branch, open_base, tip_moved):
    script = """
set -euo pipefail
d=$1 branch=$2 open_base=$3 tip_moved=$4
git init -q --bare "$d/bare"
git init -q -b trunk "$d/work"
g() { git -C "$d/work" "$@"; }
commit() { echo "$1" >"$d/work/$2"; g add "$2"; g commit -q -m "$1"; }
g remote add origin "$d/bare"
commit base base.txt
g push -q -u origin trunk
g switch -q -c "$branch"
commit landed landed.txt
g push -q -u origin "$branch"
g rev-parse HEAD >"$d/merged-oid"
if [[ $tip_moved == yes ]]; then
  commit later later.txt
  g push -q origin "$branch"
fi
if [[ $open_base == yes ]]; then
  g switch -q -c probe-child
  commit child child.txt
  g push -q -u origin probe-child
fi
g switch -q trunk
"""
    subprocess.run(
        ["bash", "-c", script, "setup", d, branch,
         "yes" if open_base else "no", "yes" if tip_moved else "no"],
        check=True, env=_env(d), capture_output=True,
    )


def _pr(number, head, base, oid):
    return {"number": number, "headRefName": head, "baseRefName": base,
            "headRefOid": oid, "isCrossRepository": False}


def _check_order(log_lines, case):
    seen = []
    for line in log_lines:
        if line.startswith("gh pr list") and "--state open" in line:
            seen.append("open")
        elif line.startswith("gh pr list") and "--state merged" in line:
            seen.append("merged")
        elif line.startswith("gh pr list") or line.startswith("gh api"):
            seen.append("other-read")
        elif line.startswith("git ") and " fetch" in line:
            seen.append("fetch")
        elif line.startswith("git ") and " --delete " in line:
            seen.append("delete")
    deletes_reread = all(seen[i - 1] == "open" for i, step in enumerate(seen) if step == "delete")
    if seen[:3] != ["open", "merged", "fetch"] or "other-read" in seen or not deletes_reread:
        raise ModelDrift(
            "model assumes: read open PRs, read merged PRs, fetch, then reread open PRs "
            f"right before each delete. Script did {seen} for {case}. Update model.py to this order."
        )


def measure_case(script_path, case):
    branch, open_head, open_base, tip_moved, moved_during = case
    d = tempfile.mkdtemp(prefix="keep-current-probe.")
    try:
        os.mkdir(os.path.join(d, "bin"))
        _write_exec(os.path.join(d, "bin", "gh"), FAKE_GH)
        _setup(d, branch, open_base, tip_moved)
        _write_exec(os.path.join(d, "bin", "git"), FAKE_GIT.format(real=shutil.which("git")))
        with open(os.path.join(d, "merged-oid")) as f:
            oid = f.read().strip()
        open_prs = []
        if open_head:
            open_prs.append(_pr(2, branch, "trunk", oid))
        if open_base:
            open_prs.append(_pr(3, "probe-child", branch, oid))
        with open(os.path.join(d, "open.json"), "w") as f:
            json.dump(open_prs, f)
        with open(os.path.join(d, "merged.json"), "w") as f:
            json.dump([_pr(1, branch, "trunk", oid)], f)
        run = subprocess.run(
            ["bash", script_path, "--repo", "acme/app",
             "--workdir", os.path.join(d, "work"), "--apply"],
            env=dict(_env(d), PROBE_MOVE_ON_REREAD=branch if moved_during else ""),
            capture_output=True, text=True,
        )
        if run.returncode != 0:
            raise ModelDrift(
                f"script exited {run.returncode} for {case}: {run.stderr.strip()}"
            )
        with open(os.path.join(d, "log")) as f:
            _check_order(f.read().splitlines(), case)
        kept = subprocess.run(
            ["git", "--git-dir", os.path.join(d, "bare"), "show-ref", "--verify",
             "--quiet", "refs/heads/" + branch],
            env=_env(d),
        ).returncode == 0
        return case, not kept
    finally:
        shutil.rmtree(d, ignore_errors=True)


def measure(script_path):
    """Return {(branch, open_head, open_base, tip_moved, moved_during): script_deletes_it}."""
    cases = list(itertools.product(BRANCHES, (False, True), (False, True), (False, True), (False, True)))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        return dict(pool.map(lambda c: measure_case(script_path, c), cases))
