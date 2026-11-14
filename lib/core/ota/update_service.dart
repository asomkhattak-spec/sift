import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/http_service.dart';
import '../services/native_bridge.dart';
import 'sift_ota.dart';

enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  downloaded,
  installing,
  upToDate,
  failed,
}

/// A release manifest. Everything here is untrusted input until the SHA-256
/// check passes against the downloaded file.
@immutable
class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.tag,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.notes,
    this.publishedAt,
  });

  final int versionCode;
  final String versionName;
  final String tag;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;
  final DateTime? publishedAt;

  String get sizeLabel =>
      '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final code = _positiveInt(json['version_code'], 2_000_000_000);
    final name = _versionName(json['version_name']);
    final url = json['apk_url'];
    final digest = json['sha256'];
    final size = _positiveInt(json['size_bytes'], 350 * 1024 * 1024);
    if (code == null) throw const FormatException('Missing version code.');
    if (name == null) throw const FormatException('Missing version name.');
    if (url is! String ||
        url.length > 600 ||
        !SiftOta.isTrustedApkUrl(url)) {
      throw const FormatException('Untrusted APK address.');
    }
    if (digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Missing checksum.');
    }
    if (size == null || size < 500 * 1024) {
      throw const FormatException('Missing APK size.');
    }
    final tag = _safeText(json['tag'], 64) ?? 'v$name';
    final notes = _notes(json['notes']);
    final published = json['published_at'] is String
        ? DateTime.tryParse(json['published_at'] as String)
        : null;

    return UpdateManifest(
      versionCode: code,
      versionName: name,
      tag: tag,
      apkUrl: url,
      sha256: digest,
      sizeBytes: size,
      notes: notes,
      publishedAt: published,
    );
  }

  static int? _positiveInt(Object? raw, int max) {
    if (raw is int) return raw > 0 && raw <= max ? raw : null;
    if (raw is num && raw == raw.roundToDouble()) {
      final value = raw.toInt();
      return value > 0 && value <= max ? value : null;
    }
    return null;
  }

  static String? _versionName(Object? raw) {
    if (raw is! String) return null;
    final clean = raw.trim();
    if (!RegExp(r'^[0-9]{1,3}(\.[0-9]{1,5}){1,3}([-+][A-Za-z0-9._-]{1,24})?$')
        .hasMatch(clean)) {
      return null;
    }
    return clean;
  }

  static String? _safeText(Object? raw, int max) {
    if (raw is! String) return null;
    final clean = raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    return clean.length <= max ? clean : clean.substring(0, max);
  }

  static String _notes(Object? raw) {
    if (raw is! String) return '';
    final clean = raw
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
        .trim();
    return clean.length <= 3000 ? clean : clean.substring(0, 3000);
  }
}

/// Checks the release channel once per launch, then follows the user's
/// explicit choice: dismiss, snooze for three days, or download and install.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required SharedPreferences prefs,
    required NativeBridge native,
    required SiftHttpBase http,
    Uri? endpoint,
  })  : _prefs = prefs,
        _native = native,
        _http = http,
        _endpoint = endpoint ?? SiftOta.updateEndpoint {
    final checked = _prefs.getInt(_lastCheckedKey) ?? 0;
    _lastChecked =
        checked > 0 ? DateTime.fromMillisecondsSinceEpoch(checked) : null;
    _progressSubscription = _native.updateProgress.listen(_onProgress);
  }

  static const _dismissedKey = 'sift.ota.dismissed';
  static const _snoozeKey = 'sift.ota.snoozeUntil';
  static const _lastCheckedKey = 'sift.ota.checked';
  static const Duration snoozeFor = Duration(hours: 72);

  final SharedPreferences _prefs;
  final NativeBridge _native;
  final SiftHttpBase _http;
  final Uri _endpoint;

  StreamSubscription<UpdateDownloadProgress>? _progressSubscription;
  UpdateManifest? _manifest;
  UpdatePhase _phase = UpdatePhase.idle;
  double _progress = 0;
  String? _error;
  String _installedName = '1.1.0';
  int _installedCode = 2;
  bool _checking = false;
  bool _forced = false;
  String? _downloadedPath;
  String? _downloadId;
  DateTime? _lastChecked;
  bool _needsPermission = false;

  UpdateManifest? get manifest => _manifest;
  UpdatePhase get phase => _phase;
  double get progress => _progress;
  String? get error => _error;
  bool get hasDownloaded => _downloadedPath != null;
  bool get needsPermission => _needsPermission;
  String get installedName => _installedName;
  int get installedCode => _installedCode;
  DateTime? get lastChecked => _lastChecked;
  bool get supported => _native.isSupported;
  bool get checking => _checking || _phase == UpdatePhase.checking;
  bool get busy =>
      _phase == UpdatePhase.downloading || _phase == UpdatePhase.installing;

  /// Snoozing and dismissing are respected for background checks, while a
  /// manual check deliberately brings the update back into view.
  bool get cardVisible {
    final update = _manifest;
    if (update == null || !_native.isSupported) return false;
    if (_forced) return true;
    if (_phase == UpdatePhase.upToDate ||
        _phase == UpdatePhase.idle ||
        _phase == UpdatePhase.checking) {
      return false;
    }
    final dismissed = _prefs.getInt(_dismissedKey) ?? 0;
    if (dismissed >= update.versionCode) return false;
    final snooze = _prefs.getInt(_snoozeKey) ?? 0;
    return snooze <= DateTime.now().millisecondsSinceEpoch;
  }

  /// Called once after the first frame. A short delay keeps the opening draw
  /// and a cold search from competing with a network request.
  Future<void> checkInBackground() async {
    if (!_native.isSupported) return;
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    await check();
  }

  Future<void> check({bool manual = false}) async {
    if (!_native.isSupported) {
      if (manual) {
        _phase = UpdatePhase.failed;
        _error = 'Updates install from the Android app.';
        notifyListeners();
      }
      return;
    }
    if (_checking || busy) return;
    _checking = true;
    if (manual) {
      _forced = true;
      _phase = UpdatePhase.checking;
      _error = null;
    }
    notifyListeners();
    try {
      await _loadInstalledVersion();
      final json = await _http.getJson(
        _endpoint.toString(),
        headers: const {'Accept': 'application/json'},
        timeout: SiftOta.requestTimeout,
        maxBytes: SiftOta.maxUpdateBytes,
      );
      if (json['available'] == false || !json.containsKey('version_code')) {
        _manifest = null;
        _downloadedPath = null;
        _needsPermission = false;
        _phase = UpdatePhase.upToDate;
        _error = null;
      } else {
        final update = UpdateManifest.fromJson(json);
        if (update.versionCode <= _installedCode) {
          _manifest = null;
          _downloadedPath = null;
          _needsPermission = false;
          _phase = UpdatePhase.upToDate;
          _error = null;
        } else {
          _manifest = update;
          _phase = UpdatePhase.available;
          _error = null;
          _downloadedPath = null;
          _needsPermission = false;
        }
      }
      _lastChecked = DateTime.now();
      await _prefs.setInt(
        _lastCheckedKey,
        _lastChecked!.millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('Update check skipped: $error');
      if (manual) {
        _phase = _manifest == null ? UpdatePhase.failed : UpdatePhase.available;
        _error = error is SiftHttpException
            ? 'Could not reach the update service. Try again in a moment.'
            : 'The update service sent something Sift could not verify.';
      }
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  Future<void> _loadInstalledVersion() async {
    final value = await _native.getAppVersion();
    if (value == null) return;
    _installedName = value.name;
    _installedCode = value.code;
  }

  void _onProgress(UpdateDownloadProgress event) {
    if (event.id != _downloadId) return;
    final total = event.total > 0 ? event.total : (_manifest?.sizeBytes ?? 0);
    final next = total > 0
        ? (event.received / total).clamp(0.0, 1.0).toDouble()
        : _progress;
    if ((next - _progress).abs() < 0.005 && next < 1) return;
    _progress = next;
    notifyListeners();
  }

  Future<void> downloadAndInstall() async {
    final update = _manifest;
    if (update == null) return;
    if (!_native.isSupported) {
      _phase = UpdatePhase.failed;
      _error = 'Updates install from the Android app.';
      notifyListeners();
      return;
    }
    if (_downloadedPath != null) {
      await installDownloaded();
      return;
    }
    if (busy) return;
    _phase = UpdatePhase.downloading;
    _progress = 0;
    _error = null;
    _needsPermission = false;
    final id = 'sift-${DateTime.now().millisecondsSinceEpoch}';
    _downloadId = id;
    notifyListeners();
    try {
      final result = await _native.downloadUpdate(
        id: id,
        url: update.apkUrl,
        fileName: 'Sift-${update.versionName}.apk',
        sha256: update.sha256,
        expectedBytes: update.sizeBytes,
        allowedHost: SiftOta.serviceHost,
      );
      // A cancel clears the active id. If the native side still completed the
      // file, do not install it behind the user's back.
      if (_downloadId != id) return;
      if (result == null) {
        throw StateError('The installer bridge is unavailable.');
      }
      if (result['cancelled'] == true) {
        _phase = UpdatePhase.available;
        _progress = 0;
        return;
      }
      if (result['ok'] != true) {
        _phase = UpdatePhase.failed;
        _error = result['error'] is String
            ? result['error'] as String
            : 'The update did not download. Check your connection and try again.';
        return;
      }
      final path = result['path'];
      if (path is! String || path.isEmpty) {
        throw StateError('The downloaded file is missing.');
      }
      _downloadedPath = path;
      _phase = UpdatePhase.downloaded;
      _progress = 1;
      notifyListeners();
      await installDownloaded();
    } catch (error) {
      debugPrint('Update download failed: $error');
      _phase = UpdatePhase.failed;
      _error = 'The update did not download. Check your connection and try again.';
    } finally {
      _downloadId = null;
      notifyListeners();
    }
  }

  Future<void> installDownloaded() async {
    final path = _downloadedPath;
    if (path == null) return;
    _phase = UpdatePhase.installing;
    _error = null;
    _needsPermission = false;
    notifyListeners();
    try {
      final result = await _native.installUpdate(path);
      if (result == null) {
        throw StateError('The installer bridge is unavailable.');
      }
      _phase = UpdatePhase.downloaded;
      if (result['ok'] != true) {
        _needsPermission = result['needsPermission'] == true;
        _error = _needsPermission
            ? 'Allow Sift to install updates, then try again.'
            : result['error'] is String
                ? result['error'] as String
                : 'Android did not open the installer.';
      }
    } catch (error) {
      debugPrint('Update install failed: $error');
      _phase = UpdatePhase.downloaded;
      _error = 'Android did not open the installer.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> openInstallPermission() => _native.openUnknownSourcesSettings();

  Future<void> cancelDownload() async {
    final id = _downloadId;
    if (id == null) return;
    await _native.cancelUpdate(id);
    _phase = UpdatePhase.available;
    _progress = 0;
    _error = null;
    _downloadId = null;
    notifyListeners();
  }

  Future<void> dismiss() async {
    final update = _manifest;
    if (update == null) return;
    _forced = false;
    await _prefs.setInt(_dismissedKey, update.versionCode);
    notifyListeners();
  }

  Future<void> later() async {
    _forced = false;
    await _prefs.setInt(
      _snoozeKey,
      DateTime.now().add(snoozeFor).millisecondsSinceEpoch,
    );
    notifyListeners();
  }

  /// Android may have installed the APK while Sift was in the background.
  Future<void> reconcileInstalledVersion() async {
    if (!_native.isSupported) return;
    await _loadInstalledVersion();
    final update = _manifest;
    if (update != null && _installedCode >= update.versionCode) {
      _manifest = null;
      _downloadedPath = null;
      _phase = UpdatePhase.upToDate;
      _error = null;
      _forced = false;
      notifyListeners();
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }
}