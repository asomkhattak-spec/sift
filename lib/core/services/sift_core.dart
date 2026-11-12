import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../models/search_models.dart';

/// Bridge to the Rust search core.
///
/// The native library is optional by design: every call returns `null` when it
/// is absent or refuses a request, and the Dart ranking/index code takes over.
/// That keeps the app runnable on the host during widget tests while the
/// Android artifact uses the compiled Rust implementation.
class SiftCore {
  SiftCore._();

  static final SiftCore instance = SiftCore._();

  bool _attempted = false;
  DynamicLibrary? _library;
  Pointer<Void>? _handle;
  _EngineNew? _engineNew;
  _EngineFree? _engineFree;
  _CoreCall? _callNative;
  _FreeString? _freeString;
  _Version? _versionNative;
  String? _version;
  String? _lastError;
  Map<String, dynamic>? _lastStats;

  bool get isAvailable => _handle != null && _handle!.address != 0;
  bool get isInitialized => _attempted;
  String get version => _version ?? 'unavailable';
  String? get lastError => _lastError;
  Map<String, dynamic>? get lastIndexStats => _lastStats;

  Future<void> initialize() async {
    if (_attempted) return;
    _attempted = true;
    try {
      _library = _openLibrary();
      if (_library == null) return;
      _engineNew = _library!
          .lookupFunction<_EngineNewNative, _EngineNew>('sift_engine_new');
      _engineFree = _library!
          .lookupFunction<_EngineFreeNative, _EngineFree>('sift_engine_free');
      _callNative = _library!.lookupFunction<_CoreCallNative, _CoreCall>(
        'sift_core_call',
      );
      _freeString = _library!
          .lookupFunction<_FreeStringNative, _FreeString>(
        'sift_core_free_string',
      );
      _versionNative = _library!.lookupFunction<_VersionNative, _Version>(
        'sift_core_version',
      );
      final versionPointer = _versionNative!();
      if (versionPointer.address != 0) {
        final text = versionPointer.toDartString();
        _freeString!(versionPointer);
        final envelope = _decodeEnvelope(text);
        final data = envelope?['data'];
        if (data is Map && data['version'] != null) {
          _version = data['version'].toString();
        }
      }
      _handle = _engineNew!();
      if (_handle == null || _handle!.address == 0) {
        _lastError = 'The native engine could not allocate its index.';
        return;
      }
      final pong = call({'op': 'ping'});
      if (pong is! Map || pong['pong'] != true) {
        _lastError = 'The native engine did not pass its health check.';
        _disposeHandle();
      }
    } catch (error) {
      _lastError = error.toString();
      _disposeHandle();
    }
  }

  DynamicLibrary? _openLibrary() {
    final candidates = <String>[
      if (Platform.environment['SIFT_CORE_LIB'] != null)
        Platform.environment['SIFT_CORE_LIB']!,
      if (Platform.isAndroid) 'libsift_core.so',
      if (Platform.isLinux) 'libsift_core.so',
      if (Platform.isWindows) 'sift_core.dll',
      if (Platform.isMacOS) 'libsift_core.dylib',
    ];
    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (_) {
        // Try the next platform name.
      }
    }
    return null;
  }

  /// Runs one operation and returns its `data` member, or `null` on failure.
  Object? call(Map<String, dynamic> request) {
    if (!isAvailable || _callNative == null || _freeString == null) return null;
    Pointer<Utf8>? requestPointer;
    Pointer<Utf8>? responsePointer;
    try {
      requestPointer = jsonEncode(request).toNativeUtf8();
      responsePointer = _callNative!(_handle!, requestPointer);
      if (responsePointer.address == 0) {
        _lastError = 'The native engine returned no response.';
        return null;
      }
      final text = responsePointer.toDartString();
      final envelope = _decodeEnvelope(text);
      if (envelope == null) {
        _lastError = 'The native response was not JSON.';
        return null;
      }
      if (envelope['ok'] != true) {
        _lastError = envelope['error']?.toString() ?? 'Native call failed.';
        return null;
      }
      return envelope['data'];
    } catch (error) {
      _lastError = error.toString();
      return null;
    } finally {
      if (requestPointer != null) malloc.free(requestPointer);
      if (responsePointer != null && responsePointer.address != 0) {
        _freeString!(responsePointer);
      }
    }
  }

  Map<String, dynamic>? _decodeEnvelope(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      // Handled by the caller.
    }
    return null;
  }

  Map<String, dynamic>? planQuery(String query) {
    final data = call({'op': 'query/plan', 'query': query});
    return data is Map ? data.cast<String, dynamic>() : null;
  }

  String? cleanUrl(String url) {
    final data = call({'op': 'url/clean', 'url': url});
    if (data is Map) return data['url']?.toString();
    return null;
  }

  /// Returns fused results, or `null` when the native core is unavailable.
  List<SearchResult>? rank(
    String query,
    List<SearchResult> results, {
    required int limit,
    bool diversify = true,
    int maxPerHost = 2,
  }) {
    if (results.isEmpty) return const <SearchResult>[];
    final data = call({
      'op': 'rank',
      'query': query,
      'results': results.map((result) => result.toJson()).toList(),
      'limit': limit,
      'diversify': diversify,
      'maxPerHost': maxPerHost,
    });
    if (data is! List) return null;
    final output = <SearchResult>[];
    for (final item in data) {
      if (item is! Map) continue;
      try {
        output.add(SearchResult.fromJson(item.cast<String, dynamic>()));
      } catch (_) {
        // Skip malformed individual results rather than losing the batch.
      }
    }
    return output;
  }

  /// Replaces the native BM25 snapshot. Returns `true` when it was accepted.
  bool replaceIndex(List<Map<String, dynamic>> documents) {
    if (!isAvailable) return false;
    final data = call({'op': 'index/replace', 'documents': documents});
    if (data is Map) {
      _lastStats = data.cast<String, dynamic>();
      return true;
    }
    return false;
  }

  Map<String, dynamic>? searchIndex(
    String query, {
    int limit = 24,
    bool includeStarter = true,
  }) {
    if (!isAvailable) return null;
    final data = call({
      'op': 'index/search',
      'query': query,
      'limit': limit,
      'includeStarter': includeStarter,
    });
    return data is Map ? data.cast<String, dynamic>() : null;
  }

  Map<String, dynamic>? indexStats() {
    if (!isAvailable) return null;
    final data = call({'op': 'index/stats'});
    if (data is Map) {
      _lastStats = data.cast<String, dynamic>();
      return _lastStats;
    }
    return null;
  }

  void clearIndex() {
    call({'op': 'index/clear'});
  }

  void _disposeHandle() {
    final handle = _handle;
    if (handle != null && handle.address != 0) {
      _engineFree?.call(handle);
    }
    _handle = null;
  }

  void dispose() {
    _disposeHandle();
    _library = null;
  }
}

typedef _EngineNewNative = Pointer<Void> Function();
typedef _EngineNew = Pointer<Void> Function();
typedef _EngineFreeNative = Void Function(Pointer<Void>);
typedef _EngineFree = void Function(Pointer<Void>);
typedef _CoreCallNative = Pointer<Utf8> Function(
  Pointer<Void>,
  Pointer<Utf8>,
);
typedef _CoreCall = Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>);
typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeString = void Function(Pointer<Utf8>);
typedef _VersionNative = Pointer<Utf8> Function();
typedef _Version = Pointer<Utf8> Function();
