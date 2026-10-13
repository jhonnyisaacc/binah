# Expo / EAS mobile pipeline

- Last verified: 2026-10-13 (davar: Android-only automatic publish; iOS not set up). Free-tier limits *unverified*.
- Docs to watch: https://docs.expo.dev/eas/ , https://docs.expo.dev/build/eas-json/ , https://docs.expo.dev/eas-update/introduction/ , https://docs.expo.dev/submit/android/

## What it's for
The `mobile` part: builds (EAS Build), over-the-air JS updates (EAS Update), store uploads (EAS Submit).

## What do you want to do?
| Goal | Steps below |
|---|---|
| Just dev builds | 1, 6 |
| Internal testers | 1, 4, 6, 7 (preview), plus 3 for Play internal track |
| OTA updates | 1, 2, 6, 7 |
| Store release | 1–7 (5 if iOS) |

## Steps
1. **Build profiles** in `eas.json`: `development` (dev client, internal distribution), `preview` (internal APK/IPA for testers), `production` (store build). https://docs.expo.dev/build/eas-json/
2. **Updates**: channels map to profiles (`preview`, `production`); set `runtimeVersion` (e.g. `"policy": "appVersion"`) so an update only reaches compatible builds. JS-only changes on `main` → `eas update --channel production`; native changes need a new build. https://docs.expo.dev/eas-update/runtime-versions/
3. **Submit to Google Play**: a Play Console service account JSON with release permissions → secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`, written to a file only during submit. The first upload of a new app must be manual in Play Console. Tracks: `internal` → `closed` → `production` (`submit.production.android.track`). https://docs.expo.dev/submit/android/
4. **Android signing**: let EAS manage the upload keystore (default) or upload your own; enrol in Play App Signing so Google holds the app signing key. https://docs.expo.dev/app-signing/managed-credentials/
5. **iOS (optional)**: paid Apple Developer account; App Store Connect API key for EAS. https://docs.expo.dev/submit/ios/
6. **EXPO_TOKEN**: access token at https://expo.dev/settings/access-tokens → GitHub secret. https://docs.expo.dev/accounts/programmatic-access/
7. **GitHub Actions**: preview build on PR `ready_for_review`; production build + submit on a tag or GitHub release; `eas update` on `main` for JS-only changes. Never build on drafts.

```yaml
on:
  pull_request: { types: [ready_for_review] }
  release: { types: [published] }
jobs:
  eas:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
      - uses: expo/expo-github-action@v8
        with: { eas-version: latest, token: "${{ secrets.EXPO_TOKEN }}" }
      - run: bun install --frozen-lockfile
        working-directory: mobile
      - run: eas build --profile ${{ github.event_name == 'release' && 'production' || 'preview' }} --platform android --non-interactive
        working-directory: mobile
```

## Costs and limits
EAS has a free tier with a monthly build allowance and queue priority for paid plans; exact numbers *unverified*, see https://expo.dev/pricing. Google Play has a one-time developer fee; Apple Developer is a yearly fee.

## What the bot can automate
| Task | Connector |
|---|---|
| eas.json and workflow changes | Cursor CloudAgent (PR) |
| Read workflow results | GitHub |
| Expo, Play Console, App Store Connect | none, manual |

## Manual steps for Jhonny
Follow the linked docs for steps 3–6; UI clicks are not reproduced here.

## Secrets and tokens
| Name | Where stored | Scope | Rotation |
|---|---|---|---|
| `EXPO_TOKEN` | repo Actions secret | Expo access token | 180 days |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | repo Actions secret | Play release management only | yearly |
| App Store Connect API key | EAS credentials | App Manager role | yearly |

## Security baseline
Robot/access tokens, never passwords; Play service account limited to release; service-account file deleted after submit.

## How to verify it works
`eas build --profile preview` produces an installable build; a JS-only change on `main` shows the update on a production build; a release lands on the Play internal track.

## Recurring checks
| Check | Cadence |
|---|---|
| Last build/update/submit succeeded | on failure |
| Token expiry | 14 days before |
| Build minutes used vs plan | monthly |
