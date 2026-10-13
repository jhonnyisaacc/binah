# Railway

- Last verified: 2026-10-13 (davar: production ← `main`, staging ← `staging`, root `/api`; PR environments were ON on #320)
- Docs to watch: https://docs.railway.com/guides/environments

## What it's for
The `api`/`worker` parts. Production deploys from `main`; staging from `staging`; a ready PR that changes the API is deployed to staging by `railway-staging.yml`.

## Prerequisites
Project and service (davar: project `davar`, service `davar`), root directory `/api`, staging vars `API_PUBLIC_URL`, `API_HOSTS`, `NODE_ENV=staging`.

## What the bot can automate
| Task | Connector |
|---|---|
| Read services, deployments, logs, metrics, variables (names) | Railway (user-Railway) |
| Turn PR environments off, set staging variables | Railway, asks first |
| `railway-staging.yml` workflow | Cursor CloudAgent |
| Production variables or deploys | never without Jhonny |

## Manual steps for Jhonny
1. Project settings → Environments → turn **PR Environments** off (see https://docs.railway.com/guides/environments#enable-pr-environments; exact toggle location *unverified*).
2. Create a project token scoped to the **staging** environment (see https://docs.railway.com/guides/public-api#project-token) → save as `RAILWAY_TOKEN` in GitHub.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `RAILWAY_TOKEN` | repo Actions secret | project token, staging only | 180 days |

## Security baseline
2FA; CI token staging-only; production variables never in GitHub.

## How to verify it works
`GET /up` on staging returns `{"status":"ok"}`; a ready API PR deploys to staging and comments which PR staging runs; no `<project>-pr-<n>` environments appear.

## Recurring checks
| Check | Cadence |
|---|---|
| Production and staging deploy health | weekly + on failure |
| No PR environments exist | weekly |
| Token expiry | 14 days before |
