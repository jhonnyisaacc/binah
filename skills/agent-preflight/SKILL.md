---
name: agent-preflight
description: Set Jhonny's git author, commit signing, and repo hooks before the first commit in any of his repositories. Use at the start of a cloud-agent run, before committing, and when a commit would be unsigned or attributed to Cursor.
---

# Agent preflight

Run this before the first commit in a repository that follows binah. The script is `scripts/agent-preflight.sh`. It reads `policy/author` and `policy/forbidden-trailers`, sets the author, turns signing on, and installs `.githooks`.

The author is `jhonnyisaacc <60485595+jhonnyisaacc@users.noreply.github.com>`. Branch names match `policy/branch-name.regex`. A `Co-authored-by` trailer that names Cursor is removed. Other co-authors stay.

## Before the first commit

From the repository root:

```bash
bash scripts/agent-preflight.sh
```

If that command exits non-zero, stop. Do not commit. Do not push an unsigned commit. The usual cause is a missing `SSH_SIGNING_KEY_BASE64` secret.

Run it again after a rebase or any rewrite. A rewritten commit is unsigned until it is signed again.

## Why install and start both call it

Cursor bakes `install` into the environment snapshot. An agent that boots from that snapshot does not run `install` again. `start` runs on every boot, and nothing waits for it, so a commit can land before `start` finishes. Run the script yourself before the first commit even when `environment.json` already names it.

Refa merges the call into the repo's existing `.cursor/environment.json` with `scripts/merge-cursor-environment.py`. She does not replace a dependency install. The install line keeps the repo's own command after the preflight. The start line runs the preflight first.

A generic "run this repo's policy script before push" mechanism belongs in pstack (issue 626). This skill is the policy values for Jhonny's repositories, not that mechanism.

## Cursor's own hook runs too late to trust

On a cloud agent, Cursor's commit-msg hook appends its trailer after the repository hook. `agent-preflight.sh` detects that dispatcher (a hooks directory that contains `.dispatcher`), points it at `.githooks`, and adds a later hook that strips the Cursor trailer again. Do not set `core.hooksPath` to `.githooks` on that machine. That would skip Cursor's secret scanner.

## Design files

Before editing UI, run `bash scripts/sync-design-files.sh`. It checks out `*.pen` files and `design/` from `origin/main` when this branch has not changed them. It leaves local design edits in place. Copy the `Design files:` line it prints into the pull request body.

## What Refa copies into each repository

`scripts/install-policy-kit.sh <repo>` copies the policy files, the hooks, this skill, the pull request template, and the preflight script. It then updates `.cursor/environment.json`. For a repository with an Expo app, pass `--mobile` so the Expo release check is copied too.
