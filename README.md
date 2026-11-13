# Sift

A private, ad-free search room for Android.

Sift is an independent Flutter app for searching the web, reading the results
in place, and keeping a searchable library on the phone. It does not show ads,
does not ship an analytics SDK, and does not require an account. Queries go
only to the sources you leave switched on.

The search core is written twice: a Rust engine for ranking, URL cleaning and
BM25 indexing, plus a behavioural Dart fallback so the app still works if the
native library is unavailable.

[![build](https://github.com/asomkhattak-spec/sift/actions/workflows/build.yml/badge.svg)](https://github.com/asomkhattak-spec/sift/actions/workflows/build.yml)

## What it does

**Search**

- The on-device index answers first: Sift Local results paint immediately,
  before any web source replies.
- One search field across six verticals: All, Web, Images, News, Videos and
  Discussions.
- An **On-device only** toggle (also in Settings → Search) that sends no query
  to any web source and uses only the local index plus locally computed
  answers.
- Meta-search across Bing web results, Wikipedia, Google News, Openverse,
  Dailymotion, Hacker News and Stack Exchange.
- Parallel provider calls that stream in progressively with a 6-second
  per-source cap, so the first source to answer paints the page instead of the
  slowest one holding it up.
- On-device fusion and ranking: exact-title and phrase boosts, term coverage,
  source priors, recency for news, host diversity and URL deduplication.
- A source panel that shows which providers answered, how long each took and
  why a provider failed, instead of silently pretending there is no more
  content.
- Instant answers computed locally or from small public APIs: arithmetic,
  unit and currency conversion, weather, dictionary definitions and simple
  date questions.
- Search suggestions drawn from local history, the local index and a small
  query-completion service, with a switch to turn remote suggestions off.
- Pull to refresh, paginated results, safe search, language preference and a
  10–30 result setting.

**My Search**

- A private full-text index stored on the phone that answers before the web and
  is the whole engine in **On-device only** mode.
- 64 curated reference pages across privacy, security, web architecture,
  search, typography, climate, health and learning.
- Add any page you are reading. Sift extracts the readable text, stores it in
  app-private storage and indexes it with BM25.
- Write notes that live in the same index.
- Typo tolerance, stemming, synonym expansion and highlighted excerpts.
- Export and re-import the index as JSON; delete individual documents or the
  whole custom collection.
- Honest limits: this is a local index of pages you added, not a crawl of the
  web. The UI says so.

**Browser and reading**

- Multi-tab in-app browser (up to eight tabs) on `flutter_inappwebview`.
- Tracker and analytics host filtering for subresources, with a visible count
  of what was blocked.
- Tracking parameters (`utm_*`, `fbclid`, `gclid` and friends) stripped from
  links before they open.
- Reader mode that extracts the article, keeps the images and drops the
  surrounding page.
- Find in page, desktop mode, downloads through Android's download manager,
  share sheet, external-browser handoff, saved pages and notes.
- Private tabs, third-party cookie control, DOM storage control and a clear
  cookies action.
- Optional HTTP proxy for search requests and the WebView. A common setup is
  Orbot in proxy mode; Sift does not bundle or start it.

**Library**

- Saved pages, notes and optional activity history.
- Search across the library.
- Remove one item or clear each collection.
- Open a saved page in the browser or jump to its text in My Search.

**Settings**

- Appearance: light, dark or system, plus a compact density option.
- Search: result count, safe search, language, remote suggestions, open-in-app.
- Privacy: private browsing, history, tracker filtering, parameter stripping,
  cookies, JavaScript, secure screen, proxy.
- Sources: per-provider switches with a privacy note and homepage for each.
- Data: export/import the local index, clear library, clear cookies.
- Legal: privacy, terms and open-source notices bundled with the app.

## Privacy, stated plainly

Sift is designed to collect less, not to promise magic.

- No account, no advertising identifier, no analytics SDK, no Sift server.
- Settings, history, saved pages, notes and the local index stay in the app's
  private storage.
- Private browsing is on by default; history is off by default; third-party
  cookies are off by default.
- Search requests go directly from the phone to each enabled provider. A
  provider sees the query, the language and safe-search flags, and ordinary
  network metadata such as your IP address.
- Tracker filtering is a denylist of known advertising and analytics hosts.
  It reduces common tracking; it is not a guarantee.
- The proxy is a user-supplied HTTP proxy. Without a trustworthy exit, your
  mobile network and provider can still observe traffic. Sift does not claim
  to be "fully untraceable", because that claim would be false.

Read the full threat model in [docs/PRIVACY.md](docs/PRIVACY.md).

## Architecture

```
lib/
  main.dart                 bootstrap, service graph, platform setup
  app.dart                  MaterialApp, theme, lifecycle hooks
  core/
    models/                 search and library value types
    search/                 providers, ranking, instant answers, local index
    services/               settings, library, HTTP, native bridge, Rust FFI
    theme/                  paper/ink/moss palette and type scale
    utils/                  URL cleaning, text, formatters, navigation
  screens/                  search, discover, my search, library, browser,
                            settings, reader
  widgets/                  shared UI primitives, result cards, search field
rust/
  sift_core/                cdylib + rlib: normalization, BM25, fusion, FFI
android/                    Gradle project, manifest, resources, MainActivity
tool/build_rust_android.sh  cross-compile and package jniLibs
test/                       Dart unit tests
.github/workflows/build.yml CI: Rust tests, analyze, tests, APK, release
```

The Rust boundary is a small JSON-over-C ABI. Dart sends a request object and
receives `{"ok": true, "data": ...}` or `{"ok": false, "error": ...}`. The ABI
keeps the surface stable across Flutter upgrades and lets the Dart layer fall
back gracefully. Operations: `ping`, `query/plan`, `url/clean`, `rank`,
`index/replace`, `index/search`, `index/stats`, `index/clear`.

The Dart side never treats the native library as required. If `libsift_core.so`
is missing or fails its health check, ranking and BM25 run in Dart with the
same behaviour.

## Building

The fastest path is the GitHub Actions workflow: every push to `main` runs the
Rust tests, Flutter analysis, Dart tests and an APK build, then uploads the APK
as an artifact. A `v*` tag also publishes a GitHub release with the APK
attached.

For a local build you need Flutter 3.24.5, Java 17, Rust and an Android NDK.
None of these are required for editing the Dart source.

```bash
flutter pub get
cargo test --locked --manifest-path rust/sift_core/Cargo.toml
bash tool/build_rust_android.sh          # needs ANDROID_NDK_HOME
flutter analyze
flutter test
flutter build apk --release
```

`tool/build_rust_android.sh` builds `arm64-v8a`, `armeabi-v7a` and `x86_64`
and writes them to `android/app/src/main/jniLibs`. Those files are generated
and ignored by Git.

### Signing

CI signs with a private keystore when these repository secrets exist:

| Secret | Meaning |
| --- | --- |
| `SIFT_KEYSTORE_BASE64` | Base64 of the release `.jks` |
| `SIFT_KEYSTORE_PASSWORD` | Keystore password |
| `SIFT_KEY_ALIAS` | Key alias (defaults to `sift`) |
| `SIFT_KEY_PASSWORD` | Key password (defaults to the keystore password) |

Without the secrets the release APK is signed with the debug key, which is
installable but not suitable for publishing or upgrading from a differently
signed build.

Create a keystore once, outside the repository:

```bash
keytool -genkeypair -v -keystore sift-release.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias sift
base64 -w0 sift-release.jks > sift-release.jks.b64
```

Then add the four secrets in the repository settings. Never commit the
keystore or its passwords.

## Why Sift is not a web-scale crawler

A genuinely independent web index needs crawlers, storage and machines that do
not fit on a phone, and building one would also mean operating a server that
sees every query — the opposite of the goal here. Instead Sift ships a real
search engine that fits the device: a Rust BM25 index over the curated shelf
and every page the reader chooses to keep. That engine is the default and, with
**On-device only** enabled, the only engine that runs. Web sources are opt-in
additions, not the product.

## Sources

| Source | Verticals | Notes |
| --- | --- | --- |
| Bing (RSS) | Web, News | No API key; conservative query parameters |
| Wikipedia | Web, Discussions | MediaWiki search API |
| Google News (RSS) | News | Headline and publisher only |
| Openverse | Images | CC-licensed image search |
| Dailymotion | Videos | Public video search API |
| Hacker News (Algolia) | Discussions | Stories and comments |
| Stack Exchange | Discussions | Q&A search |
| SearXNG | Web | Optional, self-hosted or user-chosen instance |

DuckDuckGo is not enabled by default: its HTML endpoint is fragile and its
Instant Answer API is not a general web search. All sources can be disabled;
with none enabled, search still works against My Search and instant answers.

## Tests

```bash
cargo test --locked --manifest-path rust/sift_core/Cargo.toml
flutter test
```

The Rust suite covers normalization, stemming, typo tolerance, URL cleaning,
BM25 statistics, fusion and the FFI envelope. The Dart suite covers URL
handling, tracking-parameter stripping, formatting, ranking and model
serialization.

## Permissions

- `INTERNET` — search and browsing.
- `ACCESS_NETWORK_STATE` — know whether the phone is online.
- `WRITE_EXTERNAL_STORAGE` — only for downloads on Android 9 and older.

Sift does not request location, contacts, camera, microphone, calendar or
`READ_PHONE_STATE`.

## Status

Version 1.0.0. The APK is built and signed in CI; no local Flutter or Android
toolchain is required for development. The repository is intentionally
self-contained: no private servers, no hidden endpoints, no ad SDKs.

## License

MIT. Bundled fonts are under the SIL Open Font License; see
`assets/fonts/*-OFL.txt`. Third-party packages retain their own licenses.
