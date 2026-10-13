# Cloudflare Pages

- Last verified: 2026-10-13 (davar: integration builds production from `main`, `web-preview.yml` deploys PR previews)
- Docs to watch: https://developers.cloudflare.com/pages/configuration/branch-build-controls/

## What it's for
The `site` part: production from `main` via the Pages Git integration; PR previews via the GitHub `web-preview` workflow (wrangler) on ready, pointing at the Railway staging API.

## Prerequisites
Pages project (davar: `davar`), GitHub secrets below, `STAGING_API_URL`.

## What the bot can automate
| Task | Connector |
|---|---|
| Read projects, deployments, build logs; set preview branch control | Cloudflare (user-Cloudflare) |
| Preview workflow changes | Cursor CloudAgent |
| Production settings, domains, DNS | never without Jhonny |

## Manual steps for Jhonny
1. Pages project → Settings → Builds & deployments → Branch control: production branch `main`, preview branches **None** (per docs above; the integration stays, it is production).
2. Set `PUBLIC_API_URL` in the Pages **production** environment variables to the Railway production API.
3. API token: https://dash.cloudflare.com/profile/api-tokens → Create token → permission Account › Cloudflare Pages › Edit, this account only → set an expiry → save as `CLOUDFLARE_API_TOKEN`.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `CLOUDFLARE_API_TOKEN` | repo Actions secret | Pages Edit, one account | 180 days |
| `CLOUDFLARE_ACCOUNT_ID` | repo Actions secret | identifier | none |

## Security baseline
2FA on Cloudflare; token limited to Pages; no DNS/Zone permissions in CI tokens.

## How to verify it works
Mark a PR ready → `web-preview` succeeds and the preview calls the staging API; no `Cloudflare Pages` preview check appears on PRs; a merge to `main` updates production.

## Recurring checks
| Check | Cadence |
|---|---|
| Latest production deploy succeeded | weekly + on failure |
| Preview branches still None | weekly |
| Token expiry | 14 days before |
