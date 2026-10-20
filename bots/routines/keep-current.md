# Keep current

How the environment maintainer updates open pull requests once a day.

## When

Daily. Also after a merge to `main` when several pull requests are open.

## What to run

Clone the repository, or use a clean checkout that is not an agent's working tree.

```bash
git clone https://github.com/<owner>/<name> /tmp/<name>
bash scripts/keep-current.sh --repo <owner>/<name> --workdir /tmp/<name> --apply
```

The script merges each open pull request's base into its head. It does not rebase. A rebase drops signatures, and GitHub then refuses the branch.

For each open pull request it does one of three things.

- The head commit is already in the base, or the two trees match. Close it with `Already on <base>. Closing.`
- The merge applies. Push the merge commit.
- The merge conflicts. Abort the merge and comment with the conflicted paths. Leave the branch as it was.

Then it deletes merged head branches. It keeps `main`, `master`, `refactor/run-*`, and any branch an open pull request still uses as its base.

Run it once without `--apply` to print the plan.

## What to report

Send Jhonny the `conflict` lines. Say nothing when every line is `merge`, `close`, `delete`, or `keep`.
