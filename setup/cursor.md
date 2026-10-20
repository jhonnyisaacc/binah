# Cursor cloud environments (agents, Bugbot)

- Last verified: 2026-10-20 for the environment install and start commands. Dashboard steps last checked 2026-10-13. Cloud agents still add a Cursor co-author trailer with no off switch.
- Docs to watch: https://cursor.com/docs/cloud-agent and https://cursor.com/docs/cloud-agent/settings

## What it's for
Cloud agents write code and open PRs in an **environment**: the repo, an install/setup script (e.g. `.cursor/environment.json`), the secrets injected into it, and a snapshot of the prepared machine reused by later runs. Bugbot reviews on `bugbot run`.

## Prerequisites
Cursor GitHub integration on the repo; Bugbot set to "Run only when mentioned"; the `cursor` signing key (signing.md).

## Which environment
| Need | Use |
|---|---|
| One-off read or tiny edit | default VM |
| Any repo agents work in regularly (deps, signing, hooks) | saved environment with setup script + snapshot |
| iOS simulators, Xcode, macOS-only tools | self-hosted Mac pool (*unverified* availability on Pro+; see docs) |

## Template setup script
Refa does not replace a repository's dependency install. She merges the preflight into the existing `.cursor/environment.json` with `scripts/merge-cursor-environment.py`. `scripts/install-policy-kit.sh` copies the policy files and then runs that merge.

The install command becomes `bash scripts/agent-preflight.sh && <existing install>`. The start command runs `bash scripts/agent-preflight.sh` and then the existing start command.

Cursor bakes `install` into the environment snapshot. An agent that boots from that snapshot does not run `install` again. `start` runs on every boot, and nothing waits for it, so a commit can land before `start` finishes. The agent still runs `bash scripts/agent-preflight.sh` before the first commit. See `skills/agent-preflight/SKILL.md`.

The script sets the author from `policy/author`, turns on SSH commit signing from `SSH_SIGNING_KEY_BASE64`, and installs `.githooks`. On a cloud agent it leaves Cursor's hook dispatcher in place and adds a later hook that strips a Cursor `Co-authored-by` trailer. It does not point `core.hooksPath` at `.githooks` when that dispatcher is present.

## What the bot can automate
| Task | Connector |
|---|---|
| Launch agents with a brief | Cursor CloudAgent |
| Add setup script and hooks to the repo | Cursor CloudAgent (PR) |
| Post `bugbot run` | GitHub Action (`bugbot-trigger.yml`) |
| Dashboard, secrets, editor settings | none, manual |

## Manual steps for Jhonny
1. https://cursor.com/dashboard/cloud-agents#my-defaults → branch prefix: one valid prefix (e.g. `feat/`); agents rename by type per brief. "Post artifacts to GitHub": **Link only** (label *unverified*).
2. Cloud-agent **Secrets** (not User API keys): add `SSH_SIGNING_KEY_BASE64`. Personal secrets apply to your runs; team secrets apply to every member's runs (team plans only); Jhonny is on Pro+, so personal. Exact UI path *unverified*: see the settings doc above.
3. Create or save the environment for the repo from a cloud-agent run, per the docs (*unverified* UI path).
4. Each Mac: Cursor Settings → Git & Pull Requests → Commit Attribution and PR Attribution off; `~/.cursor/cli-config.json` → `{"attribution":{"attributeCommitsToAgent":false,"attributePRsToAgent":false}}`.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `SSH_SIGNING_KEY_BASE64` | Cursor cloud-agent Secrets | signing only (GitHub key `cursor`) | yearly or on leak |

## Security baseline
Agent key separate from personal GPG; network allowlist; hooks deny secret reads; no production credentials in the environment.

## How to verify it works
Preflight run: setup script exits 0, commit shows Verified, author jhonnyisaacc, no Cursor trailer, branch renamed to a valid prefix.

## Recurring checks
| Check | Cadence |
|---|---|
| Agent commits Verified and trailer-free (`hygiene`) | weekly |
| Snapshot still builds (deps changed) | monthly |
| `cursor` key still registered | monthly |
