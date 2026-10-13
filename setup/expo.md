# Expo (EAS)

- Last verified: 2026-10-13 (davar: Android-only automatic publish; iOS credentials not set up)
- Docs to watch: https://docs.expo.dev/eas/

## What it's for
The `mobile` part: `eas update` for JS-only changes on `main`; `eas build` + `eas submit` for native changes.

## Prerequisites
Expo project; `eas.json`; Play service account JSON for Android submit; Apple credentials for iOS (*not set up on davar*).

## What the bot can automate
| Task | Connector |
|---|---|
| Workflow changes | Cursor CloudAgent |
| Read workflow results | GitHub |
| Expo dashboard, store credentials | none, manual |

## Manual steps for Jhonny
1. Create an access token: https://expo.dev/settings/access-tokens (per https://docs.expo.dev/accounts/programmatic-access/) → save as `EXPO_TOKEN`.
2. Play service account JSON → GitHub secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (name per davar #311; *unverified* on main).
3. iOS: set up credentials per https://docs.expo.dev/app-signing/app-credentials/ before enabling `--platform ios`.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `EXPO_TOKEN` | repo Actions secret | account access token | 180 days |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | repo Actions secret | Play publishing only | yearly |

## Security baseline
Robot/access token, not a password; Play account limited to release management.

## How to verify it works
A JS-only change on `main` publishes an update; a native change builds and submits Android.

## Recurring checks
| Check | Cadence |
|---|---|
| Last publish run succeeded | on failure |
| Token expiry | 14 days before |
