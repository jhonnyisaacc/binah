# Merge playbook

Version: 4.7 (matches rules.md).

PR state follows rules.md. Open a PR as a draft while it is in development, so preview and deploy workflows do not run on every push. Mark it ready when it is ready for manual testing. pstack says to open every PR ready. In a repo governed by rules.md, rules.md wins. Until a repo has the auto-merge setup, the agent that owns a PR merges it itself (`gh pr merge <n> --squash`) once it is ready, CI is green, `guard-paths` passes, and every Bugbot thread has a decision (a fix commit or a won't-fix reason) and is resolved. While the pull request is still a draft, and before it is marked ready, the agent arranges a `bugbot run` comment. Bugbot ignores agent accounts, so `bugbot-trigger.yml` or Refa posts it as Jhonny. If no finished Bugbot check appears within 15 minutes, the agent writes one pstack review pass as a comment that starts a line with `Review pass:`, then marks the pull request ready. Tier A PRs wait for Jhonny's approval label. Where this file says "auto-merge", read "the owning agent merges" until the setup exists.

How a refactor run gets its PRs merged. The rules' Merging section is the summary; this file is the procedure. Commands use the gh CLI. While Cursor cloud agents treat gh as read-only, the gh write steps (turning on auto-merge, retargeting a child) run in the repo workflows named below, and agents run the git steps.

Placeholders: `<base>` is the project base the brief names, `<run>` is the run's integration branch (`refactor/run-<nn>`), `<n>` is a PR number.

## 0. Before the run (Tier A, once per repo)
- Repo settings: Allow auto-merge on, squash as the only merge method, automatic head-branch deletion off.
  ```
  gh repo edit --enable-auto-merge --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false --delete-branch-on-merge=false
  ```
- Ruleset on `<base>` (the production branch) only: one required check, `gate` (which covers CI, branch name, signed and no-AI-co-author commits, ratchets and stack limits; anything not built yet is marked planned in rules.md), squash only, linear history, signed commits, no force-push or deletion. Integration branches (`refactor/run-*`) carry no rulesets and no required checks; CI still runs on every PR into them.
- Workflows: `automerge.yml` (turns on auto-merge when a PR is marked ready), `restack.yml` (retargets children after a merge), and `scripts/check-one-pr.sh` in `hygiene` (section 3).
- Verify before the first PR: open a throwaway PR, mark it ready, and confirm it squash-merges by itself and shows Verified.
  ```
  gh pr view <n> --json state,autoMergeRequest,mergeCommit,mergedBy
  gh api repos/{owner}/{repo}/commits/$(gh pr view <n> --json mergeCommit -q .mergeCommit.oid) -q .commit.verification.verified
  ```
  If anything here is missing, the run doesn't start.

## 1. Start the run
```
git fetch origin
git switch -c refactor/run-01 origin/<base>
git push -u origin refactor/run-01
gh pr create --draft --base <base> --head refactor/run-01 --title "Refactor run 01" --body-file docs/runs/YYYY-MM-DD-<repo>-run-01.md
```
The integration PR stays a draft until the run ends. Every other PR in the run uses `--base refactor/run-01`.

## 2. One PR, start to merge
```
git fetch origin
git switch -c refactor/<name> origin/<run>
gh pr create --draft --base <run> --title "<title>" --body-file <body>
```
- Work on the draft. Commit signed and push. A push to a draft does not run preview or deploy workflows.
- Mark the PR ready when the change is ready for manual testing. Before that, the local check command passes, every commit shows Verified, and a review has already run.
  ```
  git log --format='%h %G? %s' origin/<run>..HEAD
  ```
  Every line shows `G`.
- While the pull request is still a draft, comment `bugbot run` (posted as Jhonny). Wait up to 15 minutes for a finished Bugbot check (`SUCCESS`, `FAILURE`, or `NEUTRAL`). If none appears, write a comment that starts a line with `Review pass:` after one pstack review pass. Then mark the pull request ready.
- Marking ready starts the preview used for that test. `automerge.yml` then runs `gh pr merge <n> --auto --squash`, which is the merge step in rules.md. Do not mark the PR ready while it is still in development. The review already happened in the previous step.
  ```
  gh pr ready <n>
  gh pr merge <n> --auto --squash
  ```
- Watch it. Fix red checks and go through Bugbot findings one by one: fix commit or won't-fix reason, then resolve the thread. Pushing fixes doesn't need auto-merge turned on again unless GitHub turned it off.
  ```
  gh pr checks <n> --required --watch
  gh pr view <n> --json state,mergeStateStatus,reviewDecision,autoMergeRequest
  ```
- Tier A PRs: label `tier-a`, say what Jhonny is deciding in the first line of the body, and keep working on something else. `guard-paths` holds the merge until Jhonny applies the approval label; auto-merge then finishes it.
- Dependent work starts only after `gh pr view <n> --json state -q .state` prints `MERGED`. Branch it from the fresh `origin/<run>`, not from the merged branch.

## 3. Limits
- Stack depth: the number of unmerged PRs between a PR and `<run>`, itself included. At most 2.
- Open PRs in the run, drafts included, not counting the integration PR: at most 5.
- At a limit, no new PR. The agent works on merging: red CI, Bugbot triage, a restack, a stuck Tier A label request.
- The numbers are a proposal and get tuned from the run metrics in section 9.
- Map the run's PRs and their depth:
  ```
  gh pr list --state open --limit 200 --json number,headRefName,baseRefName,isDraft \
  | jq -r --arg int <run> 'INDEX(.headRefName) as $by
    | def chain($b): if $b == $int or ($by[$b] | not) then [$b] else chain($by[$b].baseRefName) + ["#\($by[$b].number)"] end;
    [.[].baseRefName] as $bases
    | .[] | select(.headRefName != $int) | select(.headRefName as $h | $bases | index($h) | not)
    | chain(.headRefName) | "\(length - 1)\t\(join(" <- "))"' \
  | sort -rn
  ```
  Each line is one chain, deepest first: depth, then the chain from the integration branch up to its tip.
- `scripts/check-one-pr.sh` runs on every pull request. It fails when this PR's depth is over 2, the run has more than 5 open PRs, or a later pull request has been merged into this pull while it is still open. Merges into an open `refactor/run-*` integration pull request are the run's normal merges, and the check allows them. The smaller cap is 2.

## 4. After a parent merges: retarget and restack
Daily keep-current is a different operation. `scripts/keep-current.sh` merges the pull request's base into its head and never rebases, so signatures stay. This section replays only the child's own commits after a parent squash, then signs them again.

GitHub doesn't reliably retarget children when a merged branch is deleted through the API, and a child whose base branch is deleted can get closed. So branches aren't deleted during the run, and children are retargeted explicitly.
- restack.yml, on a merged PR, retargets each child and comments the parent's last head commit on it:
  ```
  gh pr list --state open --base <parent-branch> --json number -q '.[].number'
  gh pr edit <child> --base <run>
  gh pr view <parent> --json headRefOid -q .headRefOid
  ```
- The child's agent replays only its own commits onto the fresh integration branch. The squash commit already contains the parent's changes, so the parent's original commits are dropped:
  ```
  git fetch origin
  git rebase --onto origin/<run> <old-parent-tip> refactor/<child>
  git log --format='%h %G? %s' origin/<run>..refactor/<child>
  git push --force-with-lease origin refactor/<child>
  ```
  The rebase signs the rewritten commits only when `commit.gpgsign` is on, which the signing setup script sets; the log must show `G` on every line before the push. Run the check command after the rebase and before the push.
- `--force-with-lease` is allowed only on the agent's own `refactor/<name>` branch, never on `<run>`, `<base>` or main, and never on another agent's branch.
- If the child was already ready, auto-merge carries on after the push. If GitHub turned it off, turn it on again with `gh pr merge <child> --auto --squash`.

## 5. Conflicts
- Mechanical conflicts (both sides moved or renamed code, import lists, lockfiles regenerated by the package manager) are Tier C: resolve, run the check command, push.
- Stop that PR and report when the resolution would change a pin assertion, a public contract, a Tier A path, or would pick between two behaviors. Keep working on other PRs.
- A PR that conflicts again after two restacks is closed and redone from the fresh integration branch instead of patched a third time.

## 6. When to escalate
- To Jhonny: any Tier A item (section 2), a required check that can only pass by loosening it or raising a baseline, a `legacy-names` match, auto-merge not firing on a green PR (a setup problem), or a red integration branch that a revert didn't fix.
- To Refa: a Bugbot finding the agent disputes twice, a conflict from section 5, a limit hit with nothing mergeable (everything waiting on Tier A), or a PR still red after three fix attempts.
- An escalation is one short comment on the PR plus a line in the run report: what's blocked, the options, the agent's pick.

## 7. Broken integration branch: revert first
If CI on `<run>` goes red after a merge, the first action is a revert PR. Nothing else merges until `<run>` is green again, and the cause gets fixed in a new PR afterwards.
```
gh run list --branch <run> --limit 5
git fetch origin
git switch -c refactor/revert-<n> origin/<run>
git revert --no-edit $(gh pr view <n> --json mergeCommit -q .mergeCommit.oid)
git push -u origin refactor/revert-<n>
gh pr create --base <run> --title "Revert #<n>" --body "Reverts #<n>: <run> red at <check>."
gh pr merge --auto --squash
```
The revert PR opens ready. It is a one-step fix, not a development loop, so it does not stay a draft while someone is still writing the change. A later push to that ready PR does deploy a preview. Green checks are the proof.

## 8. Backlog recovery
For a run that ended with many open, stacked PRs. Nothing new starts on the repo until this is done.
1. Freeze. No new PRs. Turn off any running agents for the repo.
2. Map. Run the chain map from section 3 against the branch the PRs actually target. Also list PRs not in any chain:
   ```
   gh pr list --state open --limit 200 --json number,title,headRefName,baseRefName,isDraft,mergeable,statusCheckRollup
   ```
3. Triage every PR into keep, redo or drop, one line each with the reason, in the run report.
   - keep: still correct, follows the current rules, checks green or nearly.
   - redo: the outcome is wanted but the way it's built breaks a rule (for example it ports an old-stack mechanism). Close it and open a fresh PR from the integration branch later.
   - drop: no longer wanted, superseded, or a probe. Close with a reason.
   ```
   gh pr close <n> --comment "Dropped in backlog recovery: <reason>."
   ```
   Closing a PR leaves its branch in place, so its children stay open. Each child of a dropped or redo PR is retargeted (`gh pr edit <child> --base <run>`) and replayed without the closed PR's commits (`git rebase --onto origin/<run> <closed-pr-tip> refactor/<child>`), or gets triaged as redo too. Never delete a branch an open PR uses as its base; GitHub can close that PR.
4. Merge standalone roots first: PRs based directly on the integration branch with no children, smallest first. Mark ready and auto-merge each.
5. Then each chain bottom-up: merge the root, restack the next PR (section 4), wait for green, repeat. Work on at most 5 PRs at a time.
6. Don't collapse a chain into one merge by retargeting its tip; it loses the one-change-per-commit history that makes reverts cheap.
7. Redo PRs go into the next run as normal PRs, one at a time, under the limits.
8. Delete merged head branches in one sweep, only after no open PR uses them as a base:
   ```
   gh pr list --state merged --limit 200 --json headRefName -q '.[].headRefName'
   gh pr list --state open --limit 200 --json baseRefName -q '.[].baseRefName'
   git push origin --delete <branch>
   ```

## 9. End of the run
- When the run's PRs are all merged, closed or parked as Tier A: mark the integration PR ready. It squash-merges into `<base>` like any PR, or waits for Jhonny if `<base>` deploys to production. Its body lists every PR in the run. The integration branch is kept so each PR's squash commit stays findable, and `git revert <sha>` of any of them still applies on `<base>`.
- Delete the run's merged head branches (section 8, step 8).
- Add the merge metrics to the run report:
  ```
  gh pr list --state all --limit 300 --json number,headRefName,baseRefName,state,createdAt,mergedAt,closedAt \
  | jq --arg since <run-start-iso> '[.[] | select(.createdAt >= $since and (.headRefName | startswith("refactor/")))]
    | {opened: length,
       merged: map(select(.state == "MERGED")) | length,
       closed: map(select(.state == "CLOSED")) | length,
       open: map(select(.state == "OPEN")) | length,
       first_pr: (map(.createdAt) | min),
       last_merge: (map(.mergedAt // empty) | max)}'
  ```
  | Metric | Value |
  |---|---|
  | Wall-clock time (first PR opened to last merge or stop), converted from the UTC timestamps to ART | |
  | PRs opened / merged / closed / still open | |
  | Max stack depth reached (from the stack-limits log) | |
  | Median time from ready to merged | |
  | Tier A items blocked, each with its PR | |
  | Rule violations found (limit breaches, unverified commits, wrong branch names, `legacy-names` matches, PRs merged out of order) | |
  | Proposed rule changes (suggestions only; Jhonny approves) | |

## 10. Redo a pull request
Use this when the outcome is still wanted and the open pull request cannot be kept. A wrong base, unsigned history, or a branch name that cannot be renamed cleanly are the usual cases. The replacement branch already exists and its commits are signed. Its name matches `policy/branch-name.regex`.

`scripts/redo-pr.sh` checks the branch name before any GitHub call. Without `--apply` it prints the plan. With `--apply` it does the four steps.

1. Open a replacement draft from that branch. The body links the old pull request.
2. Comment on the old pull request with `Replaced by #N.`
3. Close the old pull request.
4. Delete the old branch unless an open pull request uses it as a base.

```
bash scripts/redo-pr.sh --repo <owner>/<name> --old <n> --branch <prefix>/<name> --title "<title>" --base <base>
bash scripts/redo-pr.sh --repo <owner>/<name> --old <n> --branch <prefix>/<name> --title "<title>" --base <base> --apply
```
