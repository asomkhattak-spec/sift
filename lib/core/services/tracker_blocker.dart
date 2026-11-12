import 'package:flutter/foundation.dart';

/// A conservative, local-only host list for known advertising and analytics
/// endpoints. It is intentionally not a general-purpose blocklist: blocking
/// too aggressively breaks sign-in, payments and embedded media.
class TrackerBlocker {
  TrackerBlocker();

  final ValueNotifier<int> blockedCount = ValueNotifier<int>(0);

  static const Set<String> _hosts = {
    'doubleclick.net',
    'googleadservices.com',
    'googlesyndication.com',
    'google-analytics.com',
    'googletagmanager.com',
    'googletagservices.com',
    'adservice.google.com',
    'pagead2.googlesyndication.com',
    'amazon-adsystem.com',
    'scorecardresearch.com',
    'quantserve.com',
    'adnxs.com',
    'adsrvr.org',
    'bidswitch.net',
    'casalemedia.com',
    'criteo.com',
    'criteo.net',
    'demdex.net',
    'everesttech.net',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
    'smartadserver.com',
    'spotxchange.com',
    'springserve.com',
    'teads.tv',
    '33across.com',
    'sharethrough.com',
    'yieldmo.com',
    'moatads.com',
    'adsafeprotected.com',
    'doubleverify.com',
    'serving-sys.com',
    'flashtalking.com',
    'mathtag.com',
    'turn.com',
    'rlcdn.com',
    'krxd.net',
    'bluekai.com',
    'agkn.com',
    'liadm.com',
    'id5-sync.com',
    'tapad.com',
    'zeotap.com',
    'hotjar.com',
    'fullstory.com',
    'mixpanel.com',
    'segment.io',
    'segment.com',
    'amplitude.com',
    'heapanalytics.com',
    'branch.io',
    'appsflyer.com',
    'adjust.com',
    'kochava.com',
    'taboola.com',
    'outbrain.com',
    'revcontent.com',
    'mgid.com',
    'zedo.com',
    'popads.net',
    'propellerads.com',
    'newrelic.com',
    'bugsnag.com',
    'nr-data.net',
  };

  bool isTrackerHost(String host) {
    final clean = host.toLowerCase();
    for (final domain in _hosts) {
      if (clean == domain || clean.endsWith('.$domain')) return true;
    }
    return false;
  }

  /// Main-frame navigations are never blocked; a person who tapped a link
  /// should reach it, even when the destination uses a tracker domain.
  bool shouldBlock(Uri uri, {required bool isMainFrame}) {
    if (isMainFrame) return false;
    if (uri.host.isEmpty) return false;
    return isTrackerHost(uri.host);
  }

  void recordBlocked() {
    blockedCount.value += 1;
  }

  void reset() {
    blockedCount.value = 0;
  }

  static List<(String, String)> get disclosedCategories => const [
        ('Advertising', 'DoubleClick, Google Ads, Amazon Ads, Criteo'),
        ('Analytics', 'Google Analytics, Mixpanel, Amplitude, Hotjar'),
        ('Attribution', 'AppsFlyer, Adjust, Branch'),
        ('Data brokers', 'Oracle, LiveRamp, Tapad, Zeotap'),
        ('Native ads', 'Taboola, Outbrain, RevContent, MGID'),
      ];
}
