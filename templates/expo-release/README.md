# Expo release checks

Copy this directory into a repository that ships an Expo app. Run the check from the repository root.

```bash
python3 templates/expo-release/check_expo_release.py --app <eas-project-root> --repo .
```

`--app` is the directory EAS uploads. That is the directory that contains `app.json`, `eas.json`, and `.easignore`. Exit 0 means the four checks passed. Exit 1 prints one line per failure.

## API URL

If the app config reads `EXPO_PUBLIC_API_URL` or `apiUrl`, a release build needs a fallback URL that is not `localhost`, `127.0.0.1`, `0.0.0.0`, or `10.0.2.2`. A missing variable must not leave the release build pointed at the dev machine.

## .easignore

A path that source imports must not be excluded by `.easignore`. The check reads relative imports and imports that start at a directory inside the app. `data/` in `.easignore` fails when a file imports `data/something`.

## Auto-publish platform

An `eas build` or `eas submit` line in a workflow that runs on `push`, `workflow_dispatch`, or `release` must include `--platform android` on that same line. `--platform all`, `--platform ios`, and a missing `--platform` fail. `eas update` is not a native build. A workflow that only runs on `pull_request` is not auto-publish.

## Versions

`expo.version` in `app.json` is manual. A person sets it to `x.y.z` for a store release.

`android.versionCode` and `ios.buildNumber` are not manual. `eas.json` `build.production.autoIncrement` must be `true`, and EAS increments them.

`runtimeVersion` with policy `appVersion` follows the manual `expo.version`. A native change still needs a new build. A JavaScript-only change can be an EAS Update.
