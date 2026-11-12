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

class NativeBridge {
  NativeBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('io.github.asomkhattak.sift/native');

  final MethodChannel _channel;
  final StreamController<IncomingIntent> _intents =
      StreamController<IncomingIntent>.broadcast();

  Stream<IncomingIntent> get intents => _intents.stream;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  void initialize() {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchIntent') {
        final args = call.arguments;
        if (args is Map) {
          final intent = IncomingIntent.fromMap(args);
          if (intent.hasAction) _intents.add(intent);
        }
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

  void dispose() {
    _channel.setMethodCallHandler(null);
    _intents.close();
  }
}
