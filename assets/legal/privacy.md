# Privacy at Sift

Sift is a search room, not an account. There is no sign-in, no advertising
identifier, and no analytics SDK inside the app.

## What stays on the phone

- Appearance and search preferences
- Saved pages, notes, and optional activity history
- The "My Search" index, including pages you choose to add
- A small cache of search responses used to avoid duplicate requests

These are stored in the app's private storage. Clearing the app's data or
uninstalling Sift removes them. Private browsing is on by default; local
activity recording is off by default.

## What leaves the phone

When you run a search, the words you typed are sent to the sources that are
switched on in **Settings → Sources**. Sift shows each source and its privacy
note in that panel. Depending on the source, the request may include a language
preference, a safe-search preference, and standard network information such as
your IP address.

Sift does not attach a name, email address, account, or advertising ID. It
does not operate a server that receives your queries.

Sift's own search engine runs on the phone: the curated shelf and any pages you
add are indexed locally and answer first. An **On-device only** setting makes
that engine the only one used, so no query leaves the device at all.

## Network anonymity

Sift filters a conservative list of known advertising and analytics hosts in
its browser, and it strips common campaign parameters from links. Those are
privacy reductions, not anonymity. Your mobile network, your internet provider,
and the services you query can still observe connections unless you route
traffic through a trusted VPN or proxy.

The optional proxy setting can point Sift's search requests and its in-app
browser at a local HTTP proxy. A typical use is Orbot, which must be installed
separately and started in proxy mode. Sift does not bundle, start, or verify
that proxy. "Fully untraceable" is not a claim this app can honestly make
without a network you control.

## Cookies and the browser

Private browsing is applied to new browser tabs. Third-party cookies are off by
default. Tracker blocking is applied at the request level in the in-app browser.
Websites can still set first-party cookies, use browser storage, fingerprint
the browser, or ask you to sign in. Sift does not bypass those mechanisms.

## Children

Sift is a general-purpose search client and is not directed at children. Safe
search is on by default where a source supports it, but no filter is perfect.

## Contact

This is a self-hosted open-source project. Report privacy issues through the
repository's issue tracker rather than by including personal data in a public
issue.
