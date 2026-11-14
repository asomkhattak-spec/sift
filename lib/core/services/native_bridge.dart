import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IncomingIntent {
  const IncomingIntent({this.url, this.query, this.sharedText});

  final String? url;
  final String? query;
  final String? sharedText;

  bool get hasAction =>
      (url != null && url!.isNotEmpty) ||
      (query != null && query!.isNotEmpty) ||
      (sharedText != null && sharedText!.isNotEmpty);

  factory IncomingIntent.fromMap(Map<dynamic, dynamic> map) {
    return IncomingIntent(
      url: map['url']?.toString(),
      query: map['query']?.toString(),
      sharedText: map['text']?.toString(),
    );
  }
}

class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;
  final int code;
}

class UpdateDownloadProgress {
  const UpdateDownloadProgress({
    required this.id,
    required this.received,
    required this.total,
  });

  final String id;
  final int received;
  final int total;
}

class NativeBridge {
  NativeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('io.github.asomkhattak.sift/native');

  final MethodChannel _channel;
  final StreamController<IncomingIntent> _intents =
      StreamController<IncomingIntent>.broadcast();
  final StreamController<UpdateDownloadProgress> _updateProgress =
      StreamController<UpdateDownloadProgress>.broadcast();

  Stream<IncomingIntent> get intents => _intents.stream;
  Stream<UpdateDownloadProgress> get updateProgress => _updateProgress.stream;

  bool get _supported => !kIsWeb && Platform.isAndroid;
  bool get isSupported => _supported;

  void initialize() {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onLaunchIntent':
          {
            final args = call.arguments;
            if (args is Map) {
              final intent = IncomingIntent.fromMap(args);
              if (intent.hasAction) _intents.add(intent);
            }
          }
          break;
        case 'updateProgress':
          {
            final args = call.arguments;
            if (args is Map) {
              final id = args['id']?.toString();
              final received = args['received'];
              final total = args['total'];
              if (id != null &&
                  id.isNotEmpty &&
                  received is num &&
                  total is num) {
                _updateProgress.add(
                  UpdateDownloadProgress(
                    id: id,
                    received: received.toInt(),
                    total: total.toInt(),
                  ),
                );
              }
            }
          }
          break;
      }
      return null;
    });
  }

  Future<IncomingIntent?> initialIntent() async {
    if (!_supported) return null;
    try {
      final value = await _channel.invokeMethod<dynamic>('getLaunchIntent');
      if (value is Map) {
        final intent = IncomingIntent.fromMap(value);
        return intent.hasAction ? intent : null;
      }
    } catch (_) {
      // A missing host implementation must never block app start.
    }
    return null;
  }

  Future<bool> openExternal(String url) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openExternal',
            {'url': url},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> shareText({
    required String text,
    String? title,
    String? url,
  }) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'shareText',
            {
              'text': text,
              if (title != null) 'title': title,
              if (url != null) 'url': url,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> download({
    required String url,
    required String filename,
    String mime = 'application/octet-stream',
    String? cookie,
    String? userAgent,
  }) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'download',
            {
              'url': url,
              'filename': filename,
              'mime': mime,
              if (cookie != null && cookie.isNotEmpty) 'cookie': cookie,
              if (userAgent != null && userAgent.isNotEmpty) 'userAgent': userAgent,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setSecureScreen(bool enabled) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>(
        'setSecureScreen',
        {'enabled': enabled},
      );
    } catch (_) {
      // Best effort; screenshot protection depends on the OS.
    }
  }

  Future<void> openAppSettings() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {}
  }

  Future<AppVersion?> getAppVersion() async {
    if (!_supported) return null;
    try {
      final value = await _channel.invokeMethod<dynamic>('getAppVersion');
      if (value is Map) {
        final name = value['name'];
        final code = value['code'];
        if (name is String && name.isNotEmpty && code is num) {
          return AppVersion(name: name, code: code.toInt());
        }
      }
    } catch (_) {
      // Falling back to the compiled version keeps the About screen usable.
    }
    return null;
  }

  Future<Map<String, Object?>?> downloadUpdate({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int expectedBytes,
    required String allowedHost,
  }) async {
    if (!_supported) return null;
    try {
      final value = await _channel.invokeMethod<dynamic>('downloadUpdate', {
        'id': id,
        'url': url,
        'fileName': fileName,
        'sha256': sha256,
        'sizeBytes': expectedBytes,
        'allowedHost': allowedHost,
      });
      if (value is Map) {
        return value.map(
          (key, item) => MapEntry(key.toString(), item),
        );
      }
    } catch (_) {
      return <String, Object?>{
        'ok': false,
        'error': 'The update could not be downloaded. Try again.',
      };
    }
    return <String, Object?>{
      'ok': false,
      'error': 'The update could not be downloaded. Try again.',
    };
  }

  Future<Map<String, Object?>?> installUpdate(String path) async {
    if (!_supported) return null;
    try {
      final value = await _channel.invokeMethod<dynamic>('installUpdate', {
        'path': path,
      });
      if (value is Map) {
        return value.map(
          (key, item) => MapEntry(key.toString(), item),
        );
      }
    } catch (_) {
      return <String, Object?>{
        'ok': false,
        'error': 'Android did not open the installer.',
      };
    }
    return <String, Object?>{
      'ok': false,
      'error': 'Android did not open the installer.',
    };
  }

  Future<void> cancelUpdate(String id) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('cancelUpdate', {'id': id});
    } catch (_) {}
  }

  Future<void> openUnknownSourcesSettings() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {}
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _intents.close();
    _updateProgress.close();
  }
}
