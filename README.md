# binah

The foundation of Jhonny's agent-friendly refactor and delivery stack.

- `rules.md`: the refactor rules (versioned, with a changelog). Every rule names what enforces it.
- `merge-playbook.md`: how agent PRs are merged, restacked and recovered.

Rule changes need Jhonny's approval and a changelog line.
- `setup/`: the setup catalog. One process (declare parts → map to services → follow each service file) and one file per service: [github](setup/github.md), [cloudflare](setup/cloudflare.md), [railway](setup/railway.md), [cursor](setup/cursor.md), [signing](setup/signing.md), [expo](setup/expo.md), [security](setup/security.md); template [setup/_template.md](setup/_template.md), process [setup/README.md](setup/README.md).
- `bots/`: [Environment maintainer](bots/environment-maintainer.md), the Grok Bot teammate that applies and maintains the catalog. Routines live in `bots/routines/`.
- `policy/`: author, branch-name regex, and forbidden trailers. The scripts read these files.
- `scripts/`: agent preflight, the policy-kit install, pull request checks, and the bot scripts (`keep-current.sh`, `ci-babysit.sh`, `review-health.sh`, `redo-pr.sh`).
- `templates/`: the pull request template and the Expo release-check template.
- `skills/agent-preflight/`: the skill an agent runs before the first commit.
- `.githooks/`: branch-name check on push, and the commit-msg hook that drops a Cursor co-author trailer.

## Changelog
- 2026-10-20: rules and merge playbook v4.6. Agent preflight, the branch pattern, pull request body sections, review before ready, keep-current, CI babysit, redo, and the Expo release-check template.
- 2026-10-13: added setup/signing.md (per-actor keys; connector commits are unsigned); expanded cursor.md (cloud environments) and expo.md (EAS pipeline with decision table); security.md key separation and token scopes.
- 2026-10-13: added the setup catalog (process, template, six service files) and the Environment maintainer bot.
- 2026-10-13: initial rules v4.1 and merge playbook.
