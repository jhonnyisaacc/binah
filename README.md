# binah

The foundation of Jhonny's agent-friendly refactor and delivery stack.

- `rules.md`: the refactor rules (versioned, with a changelog). Every rule names what enforces it.
- `merge-playbook.md`: how agent PRs are merged, restacked and recovered.

Rule changes need Jhonny's approval and a changelog line.
- `setup/`: the setup catalog. One process (declare parts → map to services → follow each service file) and one file per service: [github](setup/github.md), [cloudflare](setup/cloudflare.md), [railway](setup/railway.md), [cursor](setup/cursor.md), [signing](setup/signing.md), [expo](setup/expo.md), [security](setup/security.md); template [setup/_template.md](setup/_template.md), process [setup/README.md](setup/README.md).
- `bots/`: [Environment maintainer](bots/environment-maintainer.md), the Grok Bot teammate that applies and maintains the catalog.

## Changelog
- 2026-10-13: added setup/signing.md (per-actor keys; connector commits are unsigned); expanded cursor.md (cloud environments) and expo.md (EAS pipeline with decision table); security.md key separation and token scopes.
- 2026-10-13: added the setup catalog (process, template, six service files) and the Environment maintainer bot.
- 2026-10-13: initial rules v4.1 and merge playbook.
