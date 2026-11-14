import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/http_service.dart';
import '../services/settings_service.dart';
import 'sift_ota.dart';
import 'sift_ui_config.dart';

/// Loads the cached interface bundle synchronously, then refreshes it without
/// blocking startup. Network or validation failures keep the last good bundle.
class RemoteUiService extends ChangeNotifier {
  RemoteUiService({
    required SharedPreferences prefs,
    required SiftHttpBase http,
    required SettingsService settings,
    Uri? endpoint,
  })  : _prefs = prefs,
        _http = http,
        _settings = settings,
        _endpoint = endpoint ?? SiftOta.uiEndpoint {
    _config = _readCache();
    final checked = _prefs.getInt(_lastCheckedKey) ?? 0;
    _lastChecked =
        checked > 0 ? DateTime.fromMillisecondsSinceEpoch(checked) : null;
    _settings.addListener(_onSettingsChanged);
  }

  static const _cacheKey = 'sift.ota.ui.cache';
  static const _lastCheckedKey = 'sift.ota.ui.checked';

  final SharedPreferences _prefs;
  final SiftHttpBase _http;
  final SettingsService _settings;
  final Uri _endpoint;

  late SiftUiConfig _config;
  DateTime? _lastChecked;
  bool _refreshing = false;

  /// The shipped values apply when the user turns remote interface updates
  /// off, even if a valid bundle is still cached.
  SiftUiConfig get config =>
      _settings.remoteUiEnabled ? _config : SiftUiConfig.builtIn;

  DateTime? get lastChecked => _lastChecked;
  bool get refreshing => _refreshing;

  void _onSettingsChanged() => notifyListeners();

  SiftUiConfig _readCache() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty || raw.length > SiftOta.maxUiBytes) {
      return SiftUiConfig.builtIn;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SiftUiConfig.fromJson(decoded) ?? SiftUiConfig.builtIn;
      }
      if (decoded is Map) {
        return SiftUiConfig.fromJson(decoded.cast<String, dynamic>()) ??
            SiftUiConfig.builtIn;
      }
    } catch (_) {
      // A half-written or older cache is ignored, never fatal.
    }
    return SiftUiConfig.builtIn;
  }

  Future<void> refresh() async {
    if (!_settings.remoteUiEnabled || _refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final body = await _http.getString(
        _endpoint.toString(),
        headers: const {'Accept': 'application/json'},
        timeout: SiftOta.requestTimeout,
        cacheSeconds: 120,
        maxBytes: SiftOta.maxUiBytes,
      );
      if (utf8.encode(body).length > SiftOta.maxUiBytes) {
        throw const FormatException('Interface bundle is too large.');
      }
      final decoded = jsonDecode(body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
              ? decoded.cast<String, dynamic>()
              : null;
      if (map == null) throw const FormatException('Unexpected bundle shape.');
      final candidate = SiftUiConfig.fromJson(map);
      if (candidate == null || candidate.version < _config.version) return;
      if (candidate.version == _config.version &&
          _sameBundle(candidate, _config)) {
        _lastChecked = DateTime.now();
        await _prefs.setInt(_lastCheckedKey, _lastChecked!.millisecondsSinceEpoch);
        return;
      }
      _config = candidate;
      _lastChecked = DateTime.now();
      await _prefs.setString(_cacheKey, jsonEncode(candidate.toJson()));
      await _prefs.setInt(_lastCheckedKey, _lastChecked!.millisecondsSinceEpoch);
      notifyListeners();
    } catch (error) {
      // OTA is a nicety. The APK's own interface is always a complete app.
      debugPrint('Interface update skipped: $error');
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> clearCached() async {
    _config = SiftUiConfig.builtIn;
    _lastChecked = null;
    await _prefs.remove(_cacheKey);
    await _prefs.remove(_lastCheckedKey);
    notifyListeners();
  }

  bool _sameBundle(SiftUiConfig a, SiftUiConfig b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}