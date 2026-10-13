# GitHub

- Last verified: 2026-10-13 (davar review; rulesets read from API)
- Docs to watch: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets

## What it's for
Code, PRs, CI (Actions), rulesets, repo secrets.

## Prerequisites
Repo under `jhonnyisaacc`; 2FA on the account.

## What the bot can automate
| Task | Connector |
|---|---|
| Read rulesets, workflows, runs, PRs; create repos; commit docs | GitHub (user-GitHub-xai, cursor-github) |
| Create/update rulesets (Tier A, asks first) | GitHub (`create_repository_ruleset`) |
| CI files and `gate` workflow | Cursor CloudAgent (PR, never merged without Jhonny) |
| List which secret names exist | *unverified* via connector; otherwise Jhonny runs `gh secret list -R <repo>` |

## Manual steps for Jhonny
1. Ruleset on `main` only: https://github.com/<owner>/<repo>/settings/rules → require status check `gate`, require signed commits, block force pushes and deletion, squash only. No ruleset on `staging`. (Ruleset UI per docs above.)
2. Merge settings: https://github.com/<owner>/<repo>/settings → allow squash only; default squash message "PR title and description" (see https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/configuring-commit-squashing-for-pull-requests).
3. Turn Copilot code review off: see https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/configure-automatic-review (exact path *unverified*).
4. Add repo secrets: https://github.com/<owner>/<repo>/settings/secrets/actions → New repository secret (names in the table).
5. Fine-grained token for Bugbot: https://github.com/settings/personal-access-tokens/new → only this repo → Pull requests: Read and write, Issues: Read and write → expiry 90 days → save as `BUGBOT_TRIGGER_PAT`.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `BUGBOT_TRIGGER_PAT` | repo Actions secret | fine-grained, one repo, Pull requests + Issues write | 90 days |
| `STAGING_API_URL` | repo Actions secret | config value, not a credential | on URL change |
| (Cloudflare, Railway, Expo) | repo Actions secrets | see their files | see their files |

## Security baseline
2FA; secret scanning + push protection on; Dependabot alerts on; rulesets on `main`; fine-grained tokens only, one repo, expiring.

## How to verify it works
A test PR: `gate` reports, branch-name and signature checks pass, Bugbot trigger comments `bugbot run` on ready, merge blocked until `gate` is green.

## Recurring checks
| Check | Cadence |
|---|---|
| Ruleset on main = gate + signed commits | weekly |
| Required secret names present (`.github/required-secrets.txt`) | weekly |
| PAT expiry | 14 days before |
