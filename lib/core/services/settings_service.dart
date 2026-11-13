import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Set<String> kDefaultEnabledSources = {
  'bing',
  'wikipedia',
  'gnews',
  'openverse',
  'dailymotion',
  'hackernews',
  'stackexchange',
};

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static SettingsService load(SharedPreferences prefs) => SettingsService(prefs);

  static const _kTheme = 'sift.theme';
  static const _kSafeSearch = 'sift.safeSearch';
  static const _kResultCount = 'sift.resultCount';
  static const _kOpenInApp = 'sift.openInApp';
  static const _kSuggestions = 'sift.suggestions';
  static const _kInstantAnswers = 'sift.instantAnswers';
  static const _kPrivateBrowsing = 'sift.privateBrowsing';
  static const _kRememberActivity = 'sift.rememberActivity';
  static const _kBlockTrackers = 'sift.blockTrackers';
  static const _kThirdPartyCookies = 'sift.thirdPartyCookies';
  static const _kStripTracking = 'sift.stripTracking';
  static const _kSecureScreen = 'sift.secureScreen';
  static const _kProxyEnabled = 'sift.proxyEnabled';
  static const _kProxyHost = 'sift.proxyHost';
  static const _kProxyPort = 'sift.proxyPort';
  static const _kSerifHeadings = 'sift.serifHeadings';
  static const _kTextScale = 'sift.textScale';
  static const _kLanguage = 'sift.language';
  static const _kSources = 'sift.sources';
  static const _kSearxUrl = 'sift.searxUrl';
  static const _kStarterIndexEnabled = 'sift.starterIndex';
  static const _kLocalOnly = 'sift.localOnly';
  static const _kFirstRun = 'sift.firstRun';

  String get themeMode =>
      _prefs.getString(_kTheme) ?? 'system';
  set themeMode(String value) {
    if (themeMode == value) return;
    _prefs.setString(_kTheme, value);
    notifyListeners();
  }

  bool get safeSearch => _prefs.getBool(_kSafeSearch) ?? true;
  set safeSearch(bool value) {
    if (safeSearch == value) return;
    _prefs.setBool(_kSafeSearch, value);
    notifyListeners();
  }

  int get resultCount => _prefs.getInt(_kResultCount) ?? 10;
  set resultCount(int value) {
    final clamped = value.clamp(10, 30).toInt();
    if (resultCount == clamped) return;
    _prefs.setInt(_kResultCount, clamped);
    notifyListeners();
  }

  bool get openInApp => _prefs.getBool(_kOpenInApp) ?? true;
  set openInApp(bool value) {
    if (openInApp == value) return;
    _prefs.setBool(_kOpenInApp, value);
    notifyListeners();
  }

  bool get suggestionsEnabled => _prefs.getBool(_kSuggestions) ?? true;
  set suggestionsEnabled(bool value) {
    if (suggestionsEnabled == value) return;
    _prefs.setBool(_kSuggestions, value);
    notifyListeners();
  }

  bool get instantAnswers => _prefs.getBool(_kInstantAnswers) ?? true;
  set instantAnswers(bool value) {
    if (instantAnswers == value) return;
    _prefs.setBool(_kInstantAnswers, value);
    notifyListeners();
  }

  /// Incognito-style WebView session: no cookies, cache or local history.
  bool get privateBrowsing => _prefs.getBool(_kPrivateBrowsing) ?? true;
  set privateBrowsing(bool value) {
    if (privateBrowsing == value) return;
    _prefs.setBool(_kPrivateBrowsing, value);
    notifyListeners();
  }

  /// Keeps queries and opened links in Library → History. Local only.
  bool get rememberActivity => _prefs.getBool(_kRememberActivity) ?? false;
  set rememberActivity(bool value) {
    if (rememberActivity == value) return;
    _prefs.setBool(_kRememberActivity, value);
    notifyListeners();
  }

  bool get blockTrackers => _prefs.getBool(_kBlockTrackers) ?? true;
  set blockTrackers(bool value) {
    if (blockTrackers == value) return;
    _prefs.setBool(_kBlockTrackers, value);
    notifyListeners();
  }

  bool get thirdPartyCookies => _prefs.getBool(_kThirdPartyCookies) ?? false;
  set thirdPartyCookies(bool value) {
    if (thirdPartyCookies == value) return;
    _prefs.setBool(_kThirdPartyCookies, value);
    notifyListeners();
  }

  bool get stripTrackingParams => _prefs.getBool(_kStripTracking) ?? true;
  set stripTrackingParams(bool value) {
    if (stripTrackingParams == value) return;
    _prefs.setBool(_kStripTracking, value);
    notifyListeners();
  }

  bool get secureScreen => _prefs.getBool(_kSecureScreen) ?? false;
  set secureScreen(bool value) {
    if (secureScreen == value) return;
    _prefs.setBool(_kSecureScreen, value);
    notifyListeners();
  }

  bool get proxyEnabled => _prefs.getBool(_kProxyEnabled) ?? false;
  set proxyEnabled(bool value) {
    if (proxyEnabled == value) return;
    _prefs.setBool(_kProxyEnabled, value);
    notifyListeners();
  }

  String get proxyHost => _prefs.getString(_kProxyHost) ?? '127.0.0.1';
  set proxyHost(String value) {
    final clean = value.trim().isEmpty ? '127.0.0.1' : value.trim();
    if (proxyHost == clean) return;
    _prefs.setString(_kProxyHost, clean);
    notifyListeners();
  }

  int get proxyPort => _prefs.getInt(_kProxyPort) ?? 8118;
  set proxyPort(int value) {
    final clamped = value.clamp(1, 65535).toInt();
    if (proxyPort == clamped) return;
    _prefs.setInt(_kProxyPort, clamped);
    notifyListeners();
  }

  bool get serifHeadings => _prefs.getBool(_kSerifHeadings) ?? true;
  set serifHeadings(bool value) {
    if (serifHeadings == value) return;
    _prefs.setBool(_kSerifHeadings, value);
    notifyListeners();
  }

  double get textScale => _prefs.getDouble(_kTextScale) ?? 1.0;
  set textScale(double value) {
    final clamped = value.clamp(0.9, 1.25).toDouble();
    if (textScale == clamped) return;
    _prefs.setDouble(_kTextScale, clamped);
    notifyListeners();
  }

  String get language => _prefs.getString(_kLanguage) ?? 'en';
  set language(String value) {
    if (language == value) return;
    _prefs.setString(_kLanguage, value);
    notifyListeners();
  }

  String get searxUrl => _prefs.getString(_kSearxUrl) ?? '';
  set searxUrl(String value) {
    final clean = value.trim();
    if (searxUrl == clean) return;
    _prefs.setString(_kSearxUrl, clean);
    notifyListeners();
  }

  bool get starterIndexEnabled =>
      _prefs.getBool(_kStarterIndexEnabled) ?? true;
  set starterIndexEnabled(bool value) {
    if (starterIndexEnabled == value) return;
    _prefs.setBool(_kStarterIndexEnabled, value);
    notifyListeners();
  }

  bool get isFirstRun => _prefs.getBool(_kFirstRun) ?? true;

  /// When true, no query leaves the device: search runs only against the
  /// on-device index and locally computed instant answers.
  bool get localOnlyMode => _prefs.getBool(_kLocalOnly) ?? false;
  set localOnlyMode(bool value) {
    if (localOnlyMode == value) return;
    _prefs.setBool(_kLocalOnly, value);
    notifyListeners();
  }

  Future<void> markOpened() async {
    await _prefs.setBool(_kFirstRun, false);
  }

  Map<String, bool> get _sourceMap {
    final raw = _prefs.getString(_kSources);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value == true),
        );
      }
    } catch (_) {
      // A corrupt settings blob should behave like defaults.
    }
    return {};
  }

  bool isSourceEnabled(String id) {
    final overrides = _sourceMap;
    return overrides[id] ?? kDefaultEnabledSources.contains(id);
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    final updated = _sourceMap..[id] = enabled;
    await _prefs.setString(_kSources, jsonEncode(updated));
    notifyListeners();
  }

  /// Used by the welcome card, not for resetting saved data.
  Future<void> setDefaultsForFirstRun() async {
    await _prefs.setBool(_kFirstRun, false);
  }

  Future<void> resetAppearance() async {
    await _prefs.remove(_kTheme);
    await _prefs.remove(_kSerifHeadings);
    await _prefs.remove(_kTextScale);
    notifyListeners();
  }

  Map<String, dynamic> exportPreferences() => {
        'theme': themeMode,
        'safeSearch': safeSearch,
        'resultCount': resultCount,
        'openInApp': openInApp,
        'suggestions': suggestionsEnabled,
        'instantAnswers': instantAnswers,
        'privateBrowsing': privateBrowsing,
        'rememberActivity': rememberActivity,
        'blockTrackers': blockTrackers,
        'thirdPartyCookies': thirdPartyCookies,
        'stripTrackingParams': stripTrackingParams,
        'proxyEnabled': proxyEnabled,
        'proxyHost': proxyHost,
        'proxyPort': proxyPort,
        'serifHeadings': serifHeadings,
        'textScale': textScale,
        'localOnly': localOnlyMode,
        'sources': {
          for (final id in kDefaultEnabledSources)
            id: isSourceEnabled(id),
        },
      };
}
