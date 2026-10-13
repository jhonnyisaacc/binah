# Cursor (cloud agents, Bugbot)

- Last verified: 2026-10-13 (forum + docs; Cloud Agents add a Cursor co-author trailer with no off switch)
- Docs to watch: https://cursor.com/docs/cloud-agent/settings

## What it's for
Cloud agents write code and open PRs; Bugbot reviews on `bugbot run`.

## Prerequisites
GitHub integration installed on the repo; Bugbot set to "Run only when mentioned".

## What the bot can automate
| Task | Connector |
|---|---|
| Launch agents with a brief | Cursor CloudAgent |
| Post `bugbot run` | GitHub Action (`bugbot-trigger.yml`) |
| Commit hook + environment setup script in the repo | Cursor CloudAgent (PR) |
| Dashboard and editor settings | none, manual |

## Manual steps for Jhonny
1. https://cursor.com/dashboard/cloud-agents#my-defaults → branch prefix: one valid prefix (e.g. `feat/`); agents rename by type per brief.
2. Same dashboard → "Post artifacts to GitHub": **Link only** (*unverified* label).
3. Cloud agent **Secrets** (not User API keys): add `SSH_SIGNING_KEY_BASE64` (base64 of the dedicated agent ed25519 key, registered on GitHub as a Signing Key).
4. Each Mac: Cursor Settings → Git & Pull Requests → Commit Attribution and PR Attribution off; `~/.cursor/cli-config.json` → `{"attribution":{"attributeCommitsToAgent":false,"attributePRsToAgent":false}}`.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `SSH_SIGNING_KEY_BASE64` | Cursor cloud-agent Secrets | signing only, agent-dedicated key | yearly, or at once if leaked |

## Security baseline
Agent key separate from the personal GPG key; network allowlist; hooks deny secret reads; no production credentials in the environment.

## How to verify it works
Preflight PR: commit Verified, author jhonnyisaacc, no Co-authored-by Cursor, branch renamed to a valid prefix.

## Recurring checks
| Check | Cadence |
|---|---|
| Agent commits Verified and trailer-free (hygiene results) | weekly |
| Signing key still registered | monthly |
