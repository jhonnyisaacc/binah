# Commit signing (every actor, separate identities)

- Last verified: 2026-10-13 (connector commits on binah showed unsigned; history re-signed with the grokbot key)
- Docs to watch: https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification

## What it's for
Every commit on a repo that requires signed commits shows **Verified** on GitHub. Each actor has its own key, so revoking one never breaks the others.

## Prerequisites
GitHub account `jhonnyisaacc` with 2FA. Author identity for every actor: `jhonnyisaacc <60485595+jhonnyisaacc@users.noreply.github.com>`.

## Actors and keys
| Actor | Key | GitHub key title | Where the private half lives |
|---|---|---|---|
| Jhonny's Mac | personal GPG `BC26E313EBDF2FD0` | GPG key | Jhonny's Mac only, never copied |
| Cursor cloud agents | SSH ed25519 | `cursor` (Signing Key) | Cursor cloud-agent Secrets: `SSH_SIGNING_KEY_BASE64` |
| Grok Bot (Refa) | SSH ed25519 | `grokbot` (Signing Key) | box secret; push with a fine-grained per-repo **Contents: write** token |

**Never use GitHub API or connector commits (Contents API, `push_files`) on a repo that requires signed commits: they come out unsigned.** That was today's lesson on binah.

Optional key map (`setup/signing-keys.md` in a repo, or this table): key title → fingerprint → actor, so `git log --show-signature` or the API's `verification` tells who signed.

## What the bot can automate
| Task | Connector |
|---|---|
| Check `verification.verified` on commits | GitHub API (curl with a read token) |
| Add the setup script and hooks to a repo | Cursor CloudAgent (PR) |
| Commit signed from the box | plain git with the grokbot key |
| Create keys or register them on GitHub | none, manual |

## Manual steps for Jhonny (create an agent key on a Mac)
1. `ssh-keygen -t ed25519 -C "<actor> signing" -f ~/agent-signing -N ""`
2. https://github.com/settings/ssh/new → Key type **Signing Key** → title `<actor>` (`cursor` or `grokbot`) → paste `~/agent-signing.pub` → Add.
3. `base64 -i ~/agent-signing | pbcopy` and paste it into the actor's secret store (Cursor: `SSH_SIGNING_KEY_BASE64`; box: the box secret). Never in chat or a repo.
4. `rm ~/agent-signing ~/agent-signing.pub`
5. The agent runs `bash scripts/agent-preflight.sh` before the first commit (see cursor.md and `skills/agent-preflight/SKILL.md`). That script decodes `SSH_SIGNING_KEY_BASE64`, sets `gpg.format ssh`, `user.signingkey`, and `commit.gpgsign true`, and installs the hooks. `.githooks/commit-msg` strips a `Co-authored-by` line that names Cursor. Other co-author lines stay.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `SSH_SIGNING_KEY_BASE64` | Cursor cloud-agent Secrets | signing only | yearly or on leak |
| grokbot signing key | box secret | signing only | yearly or on leak |
| grokbot push token | box env (e.g. `BINAH_GITHUB_TOKEN`) | fine-grained, one repo, Contents write | 90 days |

## Security baseline
One key per actor; signing keys never double as auth keys; the personal GPG key never leaves the Mac; revoke a key by deleting it at https://github.com/settings/keys (old commits then show Unverified, so rotate deliberately).

## How to verify it works
`curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/repos/<owner>/<repo>/commits/<sha> | jq .commit.verification` → `verified: true`, `reason: valid`. CI's `hygiene` job checks the same for each PR commit.

## Recurring checks
| Check | Cadence |
|---|---|
| Recent commits on main all Verified | weekly |
| Keys at github.com/settings/keys match the actor table | monthly |
| Push token expiry | 14 days before |
