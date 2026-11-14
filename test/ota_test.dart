import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sift/core/ota/remote_ui_service.dart';
import 'package:sift/core/ota/sift_ota.dart';
import 'package:sift/core/ota/sift_ui_config.dart';
import 'package:sift/core/ota/update_service.dart';
import 'package:sift/core/services/http_service.dart';
import 'package:sift/core/services/native_bridge.dart';
import 'package:sift/core/services/settings_service.dart';

class _FakeHttp extends SiftHttpBase {
  Map<String, dynamic> jsonResponse = const <String, dynamic>{};
  String stringResponse = '{}';
  bool failJson = false;

  String? lastUrl;
  int? lastMaxBytes;
  int? lastCacheSeconds;

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
    int maxBytes = 0,
  }) async {
    lastUrl = url;
    lastMaxBytes = maxBytes;
    lastCacheSeconds = cacheSeconds;
    if (failJson) throw const SiftHttpException('offline');
    return stringResponse;
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
    int maxBytes = 0,
  }) async {
    lastUrl = url;
    lastMaxBytes = maxBytes;
    lastCacheSeconds = cacheSeconds;
    if (failJson) throw const SiftHttpException('offline');
    return jsonResponse;
  }

  @override
  void setProxy({
    required bool enabled,
    String host = '127.0.0.1',
    int port = 8118,
  }) {}

  @override
  void clearCache() {}
}

class _FakeNative extends NativeBridge {
  bool supported = true;
  AppVersion version = const AppVersion(name: '1.0.0', code: 1);
  Map<String, Object?>? downloadResult = <String, Object?>{
    'ok': true,
    'path': '/tmp/Sift-1.1.0.apk',
  };
  Map<String, Object?>? installResult = <String, Object?>{'ok': true};
  bool openedInstallSettings = false;

  @override
  bool get isSupported => supported;

  @override
  Future<AppVersion?> getAppVersion() async => version;

  @override
  Future<Map<String, Object?>?> downloadUpdate({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int expectedBytes,
    required String allowedHost,
  }) async {
    return downloadResult;
  }

  @override
  Future<Map<String, Object?>?> installUpdate(String path) async {
    return installResult;
  }

  @override
  Future<void> cancelUpdate(String id) async {}

  @override
  Future<void> openUnknownSourcesSettings() async {
    openedInstallSettings = true;
  }
}

Map<String, dynamic> get _manifest => <String, dynamic>{
      'version_code': 2,
      'version_name': '1.1.0',
      'tag': 'v1.1.0',
      'apk_url':
          'https://github.com/asomkhattak-spec/sift/releases/download/v1.1.0/Sift-1.1.0.apk',
      'sha256': 'a' * 64,
      'size_bytes': 12 * 1024 * 1024,
      'notes': 'Image and video results, plus a faster local index.',
      'published_at': '2026-11-14T10:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SiftUiConfig', () {
    test('rejects a bundle without a positive version', () {
      expect(SiftUiConfig.fromJson(<String, dynamic>{}), isNull);
      expect(SiftUiConfig.fromJson(<String, dynamic>{'version': 0}), isNull);
      expect(SiftUiConfig.fromJson(<String, dynamic>{'version': 1000001}), isNull);
      expect(
        SiftUiConfig.fromJson(<String, dynamic>{'version': '1'}),
        isNull,
      );
    });

    test('keeps valid fields and falls back one at a time', () {
      final config = SiftUiConfig.fromJson(<String, dynamic>{
        'version': 3,
        'accent': '#1a73e8',
        'tagline': '  Private   by   default.  ',
        'starters': <Object?>['  Maps  ', 'Maps', '', 42, 'Pumps'],
        'show_shortcuts': false,
        'show_privacy_card': 'yes',
        'compact_home': true,
      });

      expect(config, isNotNull);
      expect(config!.version, 3);
      expect(config.tagline, 'Private by default.');
      expect(config.starters, <String>['Maps', 'Pumps']);
      expect(config.showShortcuts, isFalse);
      expect(config.showPrivacyCard, isTrue);
      expect(config.compactHome, isTrue);
      expect(config.accent, isNotNull);
    });

    test('an explicit empty starter list hides the row', () {
      final config = SiftUiConfig.fromJson(<String, dynamic>{
        'version': 2,
        'starters': <Object?>[],
      });
      expect(config!.starters, isEmpty);
    });

    test('a malformed starter list keeps the shipped suggestions', () {
      final config = SiftUiConfig.fromJson(<String, dynamic>{
        'version': 2,
        'starters': 'not a list',
      });
      expect(config!.starters, SiftUiConfig.defaultStarters);
    });

    test('darkens an accent until it is readable on white', () {
      final config = SiftUiConfig.fromJson(<String, dynamic>{
        'version': 1,
        'accent': '#ffffff',
      });
      final contrast = 1.05 / (config!.accent!.computeLuminance() + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5));
    });

    test('round-trips through toJson', () {
      final config = SiftUiConfig.fromJson(<String, dynamic>{
        'version': 7,
        'accent': '#188038',
        'tagline': 'A quieter search.',
        'starters': <Object?>['Flutter layout', 'Rust ownership'],
        'show_shortcuts': false,
        'show_privacy_card': false,
        'compact_home': true,
      })!;
      final again = SiftUiConfig.fromJson(config.toJson())!;
      expect(again.toJson(), config.toJson());
    });
  });

  group('UpdateManifest', () {
    test('accepts a complete, trusted manifest', () {
      final manifest = UpdateManifest.fromJson(_manifest);
      expect(manifest.versionCode, 2);
      expect(manifest.versionName, '1.1.0');
      expect(manifest.sizeLabel, '12.0 MB');
      expect(manifest.publishedAt, isNotNull);
      expect(manifest.sha256, 'a' * 64);
    });

    test('rejects untrusted download addresses', () {
      final insecure = Map<String, dynamic>.from(_manifest)
        ..['apk_url'] =
            'http://github.com/asomkhattak-spec/sift/releases/download/v1.1.0/Sift.apk';
      expect(() => UpdateManifest.fromJson(insecure), throwsFormatException);

      final foreign = Map<String, dynamic>.from(_manifest)
        ..['apk_url'] = 'https://example.com/Sift.apk';
      expect(() => UpdateManifest.fromJson(foreign), throwsFormatException);
    });

    test('rejects malformed versions, checksums and sizes', () {
      for (final patch in <Map<String, Object?>>[
        <String, Object?>{'version_code': 0},
        <String, Object?>{'version_name': 'one point one'},
        <String, Object?>{'sha256': 'A' * 64},
        <String, Object?>{'size_bytes': 100},
        <String, Object?>{'size_bytes': 400 * 1024 * 1024},
      ]) {
        final bad = Map<String, dynamic>.from(_manifest)..addAll(patch);
        expect(
          () => UpdateManifest.fromJson(bad),
          throwsFormatException,
          reason: patch.toString(),
        );
      }
    });

    test('a service update URL is also trusted', () {
      final manifest = UpdateManifest.fromJson(
        Map<String, dynamic>.from(_manifest)
          ..['apk_url'] = 'https://${SiftOta.serviceHost}/Sift.apk',
      );
      expect(manifest.apkUrl, contains(SiftOta.serviceHost));
    });
  });

  group('UpdateService', () {
    late SharedPreferences prefs;
    late _FakeHttp http;
    late _FakeNative native;
    late UpdateService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      http = _FakeHttp()..jsonResponse = _manifest;
      native = _FakeNative();
      service = UpdateService(
        prefs: prefs,
        native: native,
        http: http,
        endpoint: Uri.parse('https://example.test/api/update'),
      );
    });

    tearDown(() => service.dispose());

    test('shows a newer release, then honors snooze and dismiss', () async {
      await service.check(manual: true);

      expect(service.phase, UpdatePhase.available);
      expect(service.manifest?.versionName, '1.1.0');
      expect(service.cardVisible, isTrue);
      expect(service.lastChecked, isNotNull);
      expect(http.lastMaxBytes, SiftOta.maxUpdateBytes);

      await service.later();
      expect(service.cardVisible, isFalse);
      expect(
        prefs.getInt('sift.ota.snoozeUntil'),
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );

      await service.check(manual: true);
      expect(service.cardVisible, isTrue);

      await service.dismiss();
      expect(service.cardVisible, isFalse);
      expect(prefs.getInt('sift.ota.dismissed'), 2);
    });

    test('treats the published version and absent manifests as up to date',
        () async {
      http.jsonResponse = <String, dynamic>{'available': false};
      await service.check(manual: true);
      expect(service.phase, UpdatePhase.upToDate);
      expect(service.manifest, isNull);
      expect(service.cardVisible, isFalse);

      http.jsonResponse = _manifest;

      native.version = const AppVersion(name: '1.1.0', code: 2);
      await service.check(manual: true);
      expect(service.phase, UpdatePhase.upToDate);
      expect(service.manifest, isNull);
    });

    test('downloads, keeps the APK, and reports the install permission',
        () async {
      await service.check(manual: true);
      native.installResult = <String, Object?>{
        'ok': false,
        'needsPermission': true,
      };

      await service.downloadAndInstall();

      expect(service.phase, UpdatePhase.downloaded);
      expect(service.manifest?.versionName, '1.1.0');
      expect(service.hasDownloaded, isTrue);
      expect(service.needsPermission, isTrue);
      expect(service.error, 'Allow Sift to install updates, then try again.');
      expect(service.progress, 1);

      await service.openInstallPermission();
      expect(native.openedInstallSettings, isTrue);

      native.installResult = <String, Object?>{'ok': true};
      await service.installDownloaded();
      expect(service.phase, UpdatePhase.downloaded);
      expect(service.needsPermission, isFalse);
      expect(service.error, isNull);
    });

    test('surfaces a failed download without losing the available release',
        () async {
      await service.check(manual: true);
      native.downloadResult = <String, Object?>{
        'ok': false,
        'error': 'The update file size did not match the release.',
      };

      await service.downloadAndInstall();

      expect(service.phase, UpdatePhase.failed);
      expect(service.hasDownloaded, isFalse);
      expect(
        service.error,
        'The update file size did not match the release.',
      );
      expect(service.cardVisible, isTrue);
    });

    test('background checks do not show a snoozed card', () async {
      await service.check(manual: true);
      await service.later();
      await service.check();

      expect(service.phase, UpdatePhase.available);
      expect(service.cardVisible, isFalse);
    });

    test('unsupported hosts leave the app usable', () async {
      native.supported = false;
      await service.check(manual: true);

      expect(service.phase, UpdatePhase.failed);
      expect(service.error, 'Updates install from the Android app.');
      expect(service.cardVisible, isFalse);
    });
  });

  group('RemoteUiService', () {
    late SharedPreferences prefs;
    late SettingsService settings;
    late _FakeHttp http;
    late RemoteUiService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
      http = _FakeHttp()
        ..stringResponse = jsonEncode(<String, dynamic>{
          'version': 4,
          'accent': '#188038',
          'tagline': 'Search without a profile.',
          'starters': <String>['Flutter layout', 'Rust ownership'],
          'show_shortcuts': false,
          'show_privacy_card': true,
          'compact_home': true,
        });
      service = RemoteUiService(
        prefs: prefs,
        http: http,
        settings: settings,
        endpoint: Uri.parse('https://example.test/api/ui'),
      );
    });

    tearDown(() {
      service.dispose();
      settings.dispose();
    });

    test('loads a bundle, caches it, and applies it', () async {
      expect(service.config.version, 0);
      await service.refresh();

      expect(service.config.version, 4);
      expect(service.config.tagline, 'Search without a profile.');
      expect(service.config.starters, <String>['Flutter layout', 'Rust ownership']);
      expect(service.config.showShortcuts, isFalse);
      expect(service.config.compactHome, isTrue);
      expect(service.lastChecked, isNotNull);
      expect(http.lastMaxBytes, SiftOta.maxUiBytes);
      expect(http.lastCacheSeconds, 120);
      expect(prefs.getString('sift.ota.ui.cache'), isNotNull);
    });

    test('never downgrades a cached bundle', () async {
      await service.refresh();
      http.stringResponse = jsonEncode(<String, dynamic>{'version': 2});

      await service.refresh();

      expect(service.config.version, 4);
    });

    test('the interface switch restores built-in values but keeps the cache',
        () async {
      await service.refresh();
      expect(service.config.version, 4);

      settings.remoteUiEnabled = false;
      expect(service.config.version, 0);

      settings.remoteUiEnabled = true;
      expect(service.config.version, 4);
      expect(prefs.getString('sift.ota.ui.cache'), isNotNull);
    });

    test('turning the switch off prevents a refresh', () async {
      settings.remoteUiEnabled = false;
      await service.refresh();

      expect(http.lastUrl, isNull);
      expect(service.config.version, 0);
    });

    test('clearing the cache restores the shipped interface', () async {
      await service.refresh();
      await service.clearCached();

      expect(service.config.version, 0);
      expect(service.lastChecked, isNull);
      expect(prefs.getString('sift.ota.ui.cache'), isNull);
    });
  });
}