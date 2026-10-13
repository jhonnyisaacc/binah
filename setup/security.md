# Security baseline (all repos and services)

- Last verified: 2026-10-13
- Docs to watch: https://docs.github.com/en/code-security

## What it's for
The minimum every repo and service meets.

## Prerequisites
None.

## What the bot can automate
| Task | Connector |
|---|---|
| Read Dependabot and secret-scanning alerts, collaborators | GitHub |
| Remind before token expiry | Grok Bot routine |
| Fix PRs for alerts | Cursor CloudAgent |

## Manual steps for Jhonny
1. 2FA on GitHub, Cloudflare, Railway, Expo, Cursor.
2. Repo → Settings → Code security: secret scanning + push protection, Dependabot alerts on (https://github.com/<owner>/<repo>/settings/security_analysis).

## Secrets and tokens
Key separation: one signing key per actor (personal GPG on the Mac only; `cursor` and `grokbot` SSH signing keys), never shared, never used for auth; see [signing.md](signing.md). GitHub API/connector commits are unsigned, so never use them on repos requiring signed commits.
Rules: least privilege, one repo or environment per token (fine-grained GitHub tokens with only the permission needed, e.g. Contents write for pushing, Pull requests + Issues write for Bugbot), always an expiry (90 days for GitHub tokens, 180 for service tokens, yearly for signing keys), stored only in GitHub secrets or Cursor Secrets, never in the repo or chat. Inventory lives in each service file.

## Security baseline
2FA everywhere; secret scanning + push protection; Dependabot alerts; ruleset on `main` (gate + signed commits); fine-grained, expiring tokens; agents never hold production credentials.

## How to verify it works
No open critical alerts; every token in the inventory has an expiry; collaborators list is expected.

## Recurring checks
| Check | Cadence |
|---|---|
| Alerts, stale tokens, collaborator access | monthly |
