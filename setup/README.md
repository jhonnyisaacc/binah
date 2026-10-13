# Setup catalog

One process for every repo and service, so a new service plugs in the same way.

## Process
1. **Declare parts.** The repo's AGENTS.md (or `setup.yml`) lists its parts: `site`, `api`, `worker`, `mobile`, `data`.
2. **Map parts to services** with the table below. Add a service only when a part needs it.
3. **Follow each service file** (fixed template `_template.md`): the bot does the "bot can automate" items through its connectors, and Jhonny does the numbered manual steps.
4. **Verify** with each file's "how to verify" section, then record the date in "last verified".
5. **Maintain** using each file's recurring checks (run by the Environment maintainer bot, `../bots/environment-maintainer.md`).

To add a new service, copy `_template.md`, fill every section (mark unknowns *unverified*), add it to the map, and add a changelog line in the binah README.

## Part → services
| Part | Services |
|---|---|
| every repo | [github](github.md), [security](security.md) |
| agent-written commits (Cursor or Grok Bot) or signed-commit rulesets | [signing](signing.md) |
| Cursor cloud agents | [cursor](cursor.md) |
| site | [cloudflare](cloudflare.md) |
| api / worker | [railway](railway.md) |
| mobile | [expo](expo.md) (pick steps with its decision table) |
| data | github (CI only); add a storage service file when one is used |

davar declares: site, api, mobile, data.
