---
name: keep-current-branch-safety
description: Exhaustively checks that scripts/keep-current.sh never deletes a branch that is protected, still used by an open pull request, or holding unlanded commits. Use when changing scripts/keep-current.sh or bots/routines/keep-current.md, when changing how merged branches get deleted, or when asked whether the keep-current sweep is safe.
compatibility: Needs python3 3.9 or later, git, jq, and bash.
---

# Keep-current branch safety

**The promise:** the daily sweep in `scripts/keep-current.sh` deletes a branch only when nothing still needs it.

**The harm if it breaks:** GitHub closes the open pull request (PR) that uses the branch, or commits that never landed disappear from the remote. No person is watching when this runs.

## Does your change touch this?

Run the check if you changed any of these:

- `scripts/keep-current.sh`: `protected_branch`, `should_delete_branch`, `read_open_branches`, or the part of `main` that reads PR lists, fetches, or deletes branches.
- The order of those steps, or the data the script reads from `gh`.
- Merge or branch rules in `merge-playbook.md` (sections 3, 4, 8) or `scripts/check-one-pr.sh`. The model assumes them.

## Run it

```bash
python3 .claude/skills/keep-current-branch-safety/check.py
```

It takes about a minute and needs `python3` (3.9 or later), `git`, `jq`, and `bash`. It installs nothing, uses no network, and never calls real GitHub.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | Results match `expected-findings.txt` | Nothing new. Known findings are still there. |
| 1, `NEW VIOLATION` | The script can now do something harmful it could not do before | Read the numbered steps. See below. |
| 1, `NOW HOLDS` | A known finding is gone | Remove that line from `expected-findings.txt`. |
| 3, `MODEL DRIFT` | The script's steps no longer match the model | Update the model. See below. |

A `STALE` line means the script changed since the sync commit, so reread the model before trusting a pass.

To prove the check can still fail, run `self_test.py` in the same folder. It takes about 9 minutes. Run it after you edit the model or the probe.

## How it works

1. `probe.py` runs the real script against real local git repos with a fake `gh`. It tries each branch name in every combination of: open PR uses it as head, open PR uses it as base, tip moved since merge. And whether the tip moves between the reread and the delete. That is 80 cases. It records whether the branch was really deleted, so the delete rule is measured and never copied into the model.
2. `model.py` plays that measured rule through every ordering of agent pushes, PR opens, squash merges, restack retargets, and keep-current steps.
3. `check.py` reports the shortest path to each violation and compares the results with `expected-findings.txt`.

The checker is a small breadth-first search in plain Python, so it needs no install. TLA+ would be the usual tool, but downloading its checker was blocked on the machine this was built on.

## The rules

Each rule is checked in two situations. `between-runs` means agents act only while the script is not running. `during-run` means they can act between any two script steps.

| Property | Rule |
| --- | --- |
| `protected-branch-kept` | `main`, `master`, and `refactor/run-*` are never deleted. |
| `open-head-kept` | The head branch of an open PR is never deleted. |
| `open-base-kept` | The base branch of an open PR is never deleted. |
| `unlanded-work-kept` | A branch holding commits that never landed is never deleted. |

## Known findings

These are real and unfixed. They are listed in `expected-findings.txt` so that a new break still stands out. Do not treat exit 0 as "the sweep is safe".

- **A child PR opened at the last moment** (`during-run open-base-kept`). The script rereads the open list right before each delete, but GitHub offers no way to make that read and the delete one step. A PR opened onto a merged branch in that gap loses its base, and GitHub can close it. Its commits stay on its own branch. The model found this ordering; it has not been replayed live.

## Real bug or modeling error?

Treat a `NEW VIOLATION` as a real bug until you show otherwise:

1. Replay the numbered steps against the script, using a local bare repo and a fake `gh`, as `probe.py` does.
2. If the branch really gets deleted, it is a bug in the script. Report it with the steps. Do not change the rule or add the line to `expected-findings.txt` unless the user accepts the finding.
3. If it does not, find which step in `model.py` allows something that cannot happen, and correct it with a pointer to the code or rule that forbids it.

## When a change is intended

- **New delete rule, same steps:** nothing to update, because the probe measures it. Remove any `NOW HOLDS` lines.
- **New input to the decision:** add it as a probe dimension and to the `key` in `model.py`, so that it is measured rather than assumed.
- **New or reordered steps, such as rereading before each delete:** change `_script_steps` in `model.py` and `_check_order` in `probe.py` to match the new order.
- **Script text changed so a self-test edit no longer applies:** update the edit in `self_test.py`.

Never lower a bound or remove a rule to get a pass.

## Coverage

Covered: `scripts/keep-current.sh` (`protected_branch`, `should_delete_branch`, `read_open_branches`, and in `main` the PR list reads, the fetch, and the delete loop).

Sync commit: `dc54a60`

Move the sync commit only after you have read the covered code and confirmed that `model.py` still describes it at the new commit. Use a commit on `main`, because branch commits disappear when pull requests squash-merge.

## Bounds and what is left out

Checked: branches `main`, `master`, `refactor/run-01`, `feat/a`, `feat/b`, over two keep-current runs. `between-runs` allows 3 new commits and 3 PRs (about 2.2M states). `during-run` allows 3 new commits and 2 PRs (about 1.1M states). A pass covers these bounds, not every possible history.

Assumed, not checked:

- GitHub and git do what the model says. The real `gh` is never called.
- Agents follow `check-one-pr.sh` when merging, and only `restack.yml` retargets PRs.
- Each step is one indivisible action.

Left out:

- Names from `policy/integration-branches`. The tests cover them in `tests/test-keep-current.sh`; the model's branch list has none.
- PRs closed without merging, and keep-current's own `close` and `merge` steps (their effect on the deletion lists is not modeled).
- PRs from forks. `headRefName` is the fork's branch name, so a merged fork PR could match an unrelated branch in this repo.
- More than 200 open or merged PRs. The script's `--limit 200` would hide the rest, including open PRs that protect a branch.
- `scripts/redo-pr.sh`, which also deletes branches, and `ci-babysit.sh`.
