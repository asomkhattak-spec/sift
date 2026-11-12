import 'dart:async';
import 'dart:convert';
import 'dart:io';

class SiftHttpException implements Exception {
  const SiftHttpException(this.message, {this.statusCode, this.uri});

  final String message;
  final int? statusCode;
  final String? uri;

  @override
  String toString() {
    if (statusCode != null) {
      return 'HTTP $statusCode${uri == null ? '' : ' · $uri'}';
    }
    return message;
  }
}

abstract class SiftHttpBase {
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
  });

  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
  });

  /// Routes requests through an HTTP proxy, or clears the override.
  ///
  /// The WebView uses its own proxy controller; setting the same endpoint here
  /// keeps feed requests on the same route as the pages they open.
  void setProxy({
    required bool enabled,
    String host = '127.0.0.1',
    int port = 8118,
  });

  void clearCache();
}

class SiftHttp implements SiftHttpBase {
  SiftHttp({HttpClient? client})
      : _client = client ?? (HttpClient()..autoUncompress = true) {
    _client.connectionTimeout = const Duration(seconds: 8);
    _client.idleTimeout = const Duration(seconds: 12);
    _client.userAgent = _userAgent;
  }

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 Sift/1.0';

  final HttpClient _client;
  final Map<String, _CachedBody> _cache = {};
  bool _proxyEnabled = false;
  String _proxyHost = '127.0.0.1';
  int _proxyPort = 8118;
  static const int _maxCacheEntries = 72;

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
  }) async {
    final cacheKey = _cacheKey(url, headers);
    if (cacheSeconds > 0) {
      final cached = _cache[cacheKey];
      if (cached != null && cached.isFresh) return cached.body;
    }

    var attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final body = await _fetch(url, headers: headers, timeout: timeout);
        if (cacheSeconds > 0) {
          _cache[cacheKey] = _CachedBody(
            body,
            DateTime.now().add(Duration(seconds: cacheSeconds)),
          );
          _trimCache();
        }
        return body;
      } on SiftHttpException catch (error) {
        final retryable = error.statusCode == null ||
            error.statusCode == 429 ||
            error.statusCode == 500 ||
            error.statusCode == 502 ||
            error.statusCode == 503 ||
            error.statusCode == 504;
        if (!retryable || attempt >= 2) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
  }) async {
    final body = await getString(
      url,
      headers: {
        HttpHeaders.acceptHeader: 'application/json, text/plain, */*',
        ...?headers,
      },
      timeout: timeout,
      cacheSeconds: cacheSeconds,
    );
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw const SiftHttpException('Unexpected JSON shape.');
    } on FormatException {
      throw const SiftHttpException('The source returned unreadable JSON.');
    }
  }

  Future<String> _fetch(
    String url, {
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      throw SiftHttpException('Invalid URL.', uri: url);
    }

    try {
      final request = await _client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.8');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      headers?.forEach(request.headers.set);

      final response =
          await request.close().timeout(timeout, onTimeout: () {
        request.abort();
        throw SiftHttpException('The source took too long to answer.', uri: url);
      });

      final chunks = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        chunks.addAll(chunk);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SiftHttpException(
          'The source rejected the request.',
          statusCode: response.statusCode,
          uri: uri.host,
        );
      }
      if (chunks.isEmpty) {
        throw SiftHttpException('The source returned an empty response.',
            uri: uri.host);
      }

      final charset = response.headers.contentType?.charset?.toLowerCase();
      final encoding = charset == 'iso-8859-1'
          ? latin1
          : const Utf8Decoder(allowMalformed: true);
      return encoding.decode(chunks);
    } on SiftHttpException {
      rethrow;
    } on SocketException catch (error) {
      throw SiftHttpException(
        error.osError?.message ?? 'No connection to this source.',
        uri: uri.host,
      );
    } on HandshakeException {
      throw SiftHttpException('The secure connection failed.', uri: uri.host);
    } on TimeoutException {
      throw SiftHttpException('The source took too long to answer.', uri: uri.host);
    } on HttpException catch (error) {
      throw SiftHttpException(error.message, uri: uri.host);
    } catch (error) {
      throw SiftHttpException('Request failed.', uri: uri.host);
    }
  }

  String _cacheKey(String url, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return url;
    final sorted = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '$url|${sorted.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  void _trimCache() {
    if (_cache.length <= _maxCacheEntries) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.expiresAt.compareTo(b.value.expiresAt));
    final remove = _cache.length - _maxCacheEntries;
    for (var i = 0; i < remove; i++) {
      _cache.remove(entries[i].key);
    }
  }

  @override
  void setProxy({
    required bool enabled,
    String host = '127.0.0.1',
    int port = 8118,
  }) {
    final cleanHost = host.trim().isEmpty ? '127.0.0.1' : host.trim();
    final cleanPort = port.clamp(1, 65535).toInt();
    if (_proxyEnabled == enabled &&
        _proxyHost == cleanHost &&
        _proxyPort == cleanPort) {
      return;
    }
    _proxyEnabled = enabled;
    _proxyHost = cleanHost;
    _proxyPort = cleanPort;
    _client.findProxy = (uri) {
      if (!enabled) return 'DIRECT';
      // Loopback endpoints (for example Orbot) should never recurse through
      // themselves when the proxy host is on this device.
      if (uri.host == '127.0.0.1' || uri.host == 'localhost') return 'DIRECT';
      return 'PROXY $cleanHost:$cleanPort';
    };
    clearCache();
  }

  @override
  void clearCache() => _cache.clear();
}

class _CachedBody {
  const _CachedBody(this.body, this.expiresAt);
  final String body;
  final DateTime expiresAt;
  bool get isFresh => DateTime.now().isBefore(expiresAt);
}
