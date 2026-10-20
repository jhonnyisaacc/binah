# Review health

How the environment maintainer checks that a ready pull request was actually reviewed.

## When

Daily, and again when a pull request is marked ready.

## What to run

From a checkout of binah:

```bash
bash scripts/review-health.sh --repo <owner>/<name>
```

Exit 0 means every ready pull request has a finished Bugbot check (`SUCCESS`, `FAILURE`, or `NEUTRAL`) or a comment that starts a line with `Review pass:`. Drafts are ignored. Exit 1 prints one `flag <number> <title>` line per pull request that has neither.

## What the owning agent does before ready

The pull request stays a draft until it is ready for manual testing. Before `gh pr ready`:

1. Comment `bugbot run`. Bugbot ignores comments from agent accounts, so `bugbot-trigger.yml` posts that comment as Jhonny. Until the workflow exists, Refa posts it.
2. Wait up to 15 minutes for a Bugbot check.
3. If no Bugbot result appears, run one pstack review pass and comment `Review pass:` plus what was checked.
4. Then mark the pull request ready.

A generic "review before ready" gate belongs in pstack. This routine is the check that the review happened, for any of Jhonny's repositories.

## What to report

Send Jhonny the flag lines and the pull request URLs. Say nothing when the command exits 0.
