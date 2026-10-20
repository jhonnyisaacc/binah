# CI babysit

How the environment maintainer starts one fix agent for a failing pull request or a failing `main` build.

## When

When a workflow run on an open pull request or on `main` finishes with a failure.

## What to run

From a checkout of binah:

```bash
bash scripts/ci-babysit.sh --repo <owner>/<name> --list
```

Each line is one task. Two failed jobs on the same pull request and the same commit are one task. A failure on `main` is one task per commit. A failure on a branch with no open pull request is ignored.

Claim the task before launching the agent. A second run then skips it.

```bash
bash scripts/ci-babysit.sh --repo <owner>/<name> --claim pr/<number>/<sha>
bash scripts/ci-babysit.sh --repo <owner>/<name> --claim main/<sha>
```

The claim is a pull request comment, or an issue for `main`, whose body contains `<!-- ci-babysit: <id> -->`.

## The agent

Launch one Cursor cloud agent per claimed task. Give it the run URLs from the task, the failed-step log excerpt, and these limits.

- Fix that failure. Do not start unrelated work.
- Run `scripts/agent-preflight.sh` before the first commit.
- Push signed commits on the pull request branch. For a `main` failure, open a new draft pull request from a branch that matches `policy/branch-name.regex`.
- Do not launch a second agent for the same id.

If the launch fails, delete the claim comment or issue so the next run can try again.
