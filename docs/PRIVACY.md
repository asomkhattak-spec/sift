# Privacy and threat model

Sift is a client. It has no backend, no account system and no telemetry. That
removes a whole class of data collection, but it does not make network traffic
anonymous. This document says what Sift does, what it cannot do, and which
choices change the outcome.

## Data at rest

Sift stores the following in the app's private storage using
`SharedPreferences` and the app sandbox:

- appearance and density;
- search defaults: result count, safe search, language, remote suggestions,
  open-in-app;
- privacy defaults: private browsing, history, tracker filtering, parameter
  stripping, third-party cookies, JavaScript, secure screen, proxy host/port;
- enabled sources;
- saved pages, notes and (if enabled) activity history;
- the My Search index: the 64 curated documents, plus any pages or notes the
  user adds, capped at 160 custom documents and 14,000 characters of body text
  per document;
- a short-lived in-memory search cache, cleared when the app process dies or
  when proxy settings change.

Android auto-backup is disabled in the manifest, so this data is not copied to
Google Drive by the platform. Uninstalling Sift or clearing its storage removes
the data. There is no sync and no export unless the user explicitly exports the
index as JSON.

Private browsing is the default. When it is on, page visits and searches are not
written to history. Saved pages and notes are explicit actions and are kept
until deleted.

## Data in transit

A search request is sent directly from the phone to each enabled provider. The
provider receives:

- the query text;
- language and safe-search parameters where the provider supports them;
- ordinary HTTP metadata: IP address, User-Agent, TLS fingerprint, timing.

Sift does not add a name, email address, account identifier or advertising ID.
It does not proxy requests through a Sift-operated server because there is no
such server.

Providers have their own retention and logging policies. A provider can
correlate requests by IP address and timing even when no cookie is sent.
Disabling a source removes its requests; it does not erase what that provider
already received.

### Built-in providers

| Source | Endpoint | What is sent |
| --- | --- | --- |
| Bing | `bing.com/search` RSS | query, count, language, safe search |
| Wikipedia | `*.wikipedia.org/w/api.php` | query, language, limit |
| Google News | `news.google.com/rss/search` | query, language, safe search |
| Openverse | `api.openverse.org/v1/images` | query, page size |
| Dailymotion | `api.dailymotion.com` | query, limit, safe search |
| Hacker News | `hn.algolia.com/api/v1/search` | query, tags, page |
| Stack Exchange | `api.stackexchange.com/2.3/search` | query, site, page size |
| SearXNG (optional) | user-supplied instance | query and selected engines |

Instant answers use Open-Meteo (weather), Frankfurter (currency),
dictionaryapi.dev (definitions) and a query-completion endpoint only when the
user types in the search field and has not disabled remote suggestions.
Arithmetic and unit conversion are computed on-device.

## Browser protections

- **Tracker filtering.** Subresource requests to a bundled denylist of known
  advertising, analytics and session-replay hosts are blocked. The in-app
  browser exposes a count of blocked requests. This is deliberately described
  as a reduction, not as protection from all tracking. First-party cookies,
  fingerprinting, CNAME cloaking and server-side tracking are outside the
  denylist's reach.
- **Parameter stripping.** A conservative set of campaign parameters is removed
  before a link opens. Parameters that may be functionally required (such as
  search query strings) are left alone.
- **Cookies.** Third-party cookies are off by default. First-party cookies can
  be cleared from Settings. Private tabs clear their cookies when closed.
- **JavaScript.** Enabled by default because most of the modern web requires
  it. It can be turned off for a text-first browsing mode; many sites will
  break.
- **Secure screen.** Optional. Sets `FLAG_SECURE`, which prevents screenshots
  and hides the app in the recent-apps thumbnail. It is off by default because
  it also blocks the user's own screenshots.
- **Proxy.** Sift can route search requests and WebView traffic through an
  HTTP proxy. Android applies the WebView proxy process-wide, so the same proxy
  is used by every tab, including private tabs. A local Orbot HTTP proxy is a
  common configuration and must be installed and started by the user. Sift does
  not verify that the proxy is reachable or trustworthy.

## What Sift does not protect against

- **Network observers.** Without a trusted VPN or proxy exit, the mobile
  carrier, Wi-Fi operator and upstream networks can see the destination and
  often the plaintext hostname. DNS queries are made by the system resolver
  unless the user configures a private DNS service in Android settings.
- **Provider logging.** Each source can log the query and the requesting IP.
- **Browser fingerprinting.** A WebView exposes screen size, fonts, canvas and
  other signals. Blocking tracker hosts does not prevent fingerprinting by the
  site being visited.
- **Compromised device.** Root access, a malicious keyboard, accessibility
  abuse or a compromised OS can read anything the app can read.
- **Screenshots and shoulder surfing.** Secure screen is optional and off by
  default.
- **Search result quality.** Results are third-party content. Sift does not
  fact-check them.

For those reasons the app avoids the phrase "fully untraceable". A truthful
summary is: fewer third parties than a conventional search app, no ads, no
account, local-first storage and user-controlled routing — not anonymity by
default.

## Recommended setups

**Ordinary use.** Keep private browsing on, keep tracker filtering and
parameter stripping on, leave history off, disable sources you do not use.

**Higher privacy.** Enable a trusted VPN or a local Tor proxy, disable remote
suggestions, turn off JavaScript for reading, clear cookies regularly, and use
a DNS resolver you trust at the OS level.

**Research and archival.** Use My Search for pages you want to keep. Export the
index as JSON if you need a backup, and store the export somewhere you control.
The export contains the text you indexed; treat it as sensitive.
