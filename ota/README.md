# Sift OTA service

This directory is the whole server side of Sift's update path. It is a static
page plus two tiny Node functions on Vercel. There is no database, no account,
and no package dependency.

## Endpoints

| Route         | Purpose                                                                 |
| ------------- | ----------------------------------------------------------------------- |
| `/`           | A human-readable status page. No analytics.                             |
| `/api/ui`     | Returns the current interface bundle from `ui.json`.                     |
| `/api/update` | Returns the manifest attached to the latest GitHub release, or `available: false`. |

Both API routes return JSON, allow cross-origin reads, cap their own response
sizes, and fall back to the committed copies if GitHub is unavailable.

## Deploy

The GitHub Actions workflow deploys this directory on every push to `main`,
using three repository secrets:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

To deploy by hand:

```bash
cd ota
vercel link          # project root is this directory
vercel deploy --prod
```

The production URL is expected to be `https://sift-ota.vercel.app`. The app can
be pointed elsewhere at build time with
`--dart-define=SIFT_OTA_BASE=https://your-host`.

No build step is required. `npm run check` only parses the JavaScript.

## Interface bundles

`ui.json` is validated twice: by `/api/ui` before it leaves the server, and by
`SiftUiConfig.tryParse` inside the app. It can change the accent colour,
tagline, home-screen starters, shortcut visibility, privacy-card visibility,
and home density. It cannot introduce code, URLs, search providers, or device
permissions.

Bump `version` when changing the bundle. The app only applies a bundle whose
version is higher than the cached one, or equal with different content. Turning
off **Interface updates** in Sift restores the compiled-in interface.

The service prefers the copy fetched from `main` when its version is newer than
the copy bundled into the deployment, so a stale GitHub raw cache cannot roll
the interface backwards.

## App releases

`/api/update` reads the `update.json` asset from the latest non-draft,
non-prerelease GitHub release. A manifest must pass strict validation:
semantic-looking version name, bounded integer version code, HTTPS APK URL on
this repository's GitHub release path (or `*.githubusercontent.com`), lowercase
SHA-256, and a plausible APK size.

If the latest release has no `update.json`, the endpoint returns the committed
`latest.json`. It is currently:

```json
{ "available": false }
```

Releases are produced only by pushing a `v*` tag. The workflow checks that the
tag matches `pubspec.yaml`, builds the APK, computes its SHA-256 and size, and
attaches `update.json` next to the APK. Pushing a tag is the deliberate
publication step; a normal `main` build never publishes an update.

To withdraw a manifest, delete the `update.json` asset from the release (or
publish a newer release without one) and redeploy. The app keeps its
last-known-good state when a check fails.

## Limits

- Interface JSON: 16 KiB, version 1–1,000,000.
- Release manifest: 8 KiB, version code 1–2,000,000,000, APK 500 KiB–350 MiB,
  notes 3,000 characters.
- GitHub fetches time out after 3.5 seconds.
- Responses are cached by the CDN for five minutes.

## Privacy

The status page makes two same-origin requests and stores nothing. Vercel and
GitHub process ordinary request metadata to serve the responses; this project
adds no analytics, cookies, or third-party scripts. The Android app never sends
a query, device identifier, or browsing history to this service.