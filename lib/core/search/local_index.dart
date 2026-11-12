import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_models.dart';
import '../services/http_service.dart';
import '../services/sift_core.dart';
import '../utils/text_utils.dart';
import 'ranking.dart';

/// A document in the on-device index. Starter documents ship with the app;
/// indexed pages are supplied by the reader and stored locally.
@immutable
class LocalDocument {
  const LocalDocument({
    required this.id,
    required this.title,
    required this.url,
    required this.snippet,
    required this.body,
    required this.section,
    this.tags = const [],
    this.addedAt,
    this.isCustom = false,
  });

  final String id;
  final String title;
  final String url;
  final String snippet;
  final String body;
  final String section;
  final List<String> tags;
  final DateTime? addedAt;
  final bool isCustom;

  factory LocalDocument.fromJson(Map<String, dynamic> json, {bool isCustom = false}) {
    final tags = json['tags'];
    return LocalDocument(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      snippet: json['snippet']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      section: json['section']?.toString() ?? 'Reference',
      tags: tags is List
          ? tags.map((tag) => tag.toString()).where((tag) => tag.isNotEmpty).toList()
          : const [],
      addedAt: DateTime.tryParse(json['addedAt']?.toString() ?? ''),
      isCustom: isCustom || json['isCustom'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'snippet': snippet,
        'body': body,
        'section': section,
        'tags': tags,
        if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
        if (isCustom) 'isCustom': true,
      };
}

class LocalIndexException implements Exception {
  const LocalIndexException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// BM25 over a small, local corpus. It is not a web index and does not pretend
/// to be one: it ranks the bundled reference shelf plus pages the reader has
/// explicitly indexed.
class LocalIndex extends ChangeNotifier {
  LocalIndex(
    this._prefs,
    this._http, {
    AssetBundle? bundle,
    SiftCore? core,
  })  : _bundle = bundle ?? rootBundle,
        _core = core,
        _custom = _readStoredDocuments(_prefs);

  final SharedPreferences _prefs;
  final SiftHttpBase _http;
  final AssetBundle _bundle;
  final SiftCore? _core;
  bool _nativeReady = false;

  static const _kDocuments = 'sift.mysearch.documents.v1';
  static const int _maxCustomDocuments = 160;
  static const int _maxBodyChars = 14000;

  List<LocalDocument> _starter = const [];
  List<LocalDocument> _custom;
  List<_IndexedDocument> _indexed = const [];
  Map<String, int> _documentFrequency = const {};
  Set<String> _vocabulary = const {};
  double _averageLength = 1;
  bool _loaded = false;
  bool _loading = false;

  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  bool get usesNativeCore => _nativeReady;
  Map<String, dynamic>? get nativeStats => _core?.lastIndexStats;
  int get starterCount => _starter.length;
  int get customCount => _custom.length;
  List<LocalDocument> get starterDocuments => List.unmodifiable(_starter);
  List<LocalDocument> get customDocuments => List.unmodifiable(_custom);
  List<LocalDocument> get allDocuments =>
      List.unmodifiable([..._starter, ..._custom]);

  static List<LocalDocument> _readStoredDocuments(SharedPreferences prefs) {
    final raw = prefs.getString(_kDocuments);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((json) => LocalDocument.fromJson(
                json.cast<String, dynamic>(),
                isCustom: true,
              ))
          .where((document) => document.url.isNotEmpty && document.title.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> load() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final raw = await _bundle.loadString('assets/data/starter_index.json');
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _starter = decoded
            .whereType<Map>()
            .map((json) => LocalDocument.fromJson(json.cast<String, dynamic>()))
            .where((document) => document.title.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      // A missing starter shelf should never prevent the app from opening.
      _starter = const [];
    }
    _rebuild();
    _loaded = true;
    _loading = false;
    notifyListeners();
  }

  void _rebuild() {
    final documents = allDocuments;
    if (_core != null && _core.isAvailable) {
      _nativeReady = _core.replaceIndex(
        documents.map((document) => document.toJson()).toList(growable: false),
      );
    } else {
      _nativeReady = false;
    }

    final indexed = <_IndexedDocument>[];
    for (final document in documents) {
      indexed.add(_IndexedDocument(document));
    }
    _indexed = indexed;
    final documentFrequency = <String, int>{};
    var totalLength = 0;
    for (final item in indexed) {
      totalLength += item.length;
      for (final term in item.uniqueTerms) {
        documentFrequency[term] = (documentFrequency[term] ?? 0) + 1;
      }
    }
    _documentFrequency = documentFrequency;
    _vocabulary = documentFrequency.keys.toSet();
    _averageLength = indexed.isEmpty ? 1 : totalLength / indexed.length;
  }

  Future<List<SearchResult>> search(
    String query, {
    int limit = 24,
    bool includeStarter = true,
  }) async {
    if (!_loaded && !_loading) await load();
    final cleanQuery = normalizeQuery(query);
    final mustTerms = queryTerms(cleanQuery);
    if (mustTerms.isEmpty) return const [];
    final normalizedQuery = _normalize(cleanQuery);
    if (normalizedQuery.isEmpty) return const [];

    if (_nativeReady) {
      final native = _searchNative(
        cleanQuery,
        limit: limit,
        includeStarter: includeStarter,
      );
      if (native != null) return native;
    }

    final weights = <String, double>{};
    for (final term in mustTerms) {
      weights[term] = 1.0;
      for (final synonym in kQuerySynonyms[term] ?? const <String>[]) {
        final normalized = stem(synonym);
        if (normalized.length > 1) {
          final current = weights[normalized] ?? 0;
          if (current < 0.55) weights[normalized] = 0.55;
        }
      }
      if (!_vocabulary.contains(term)) {
        for (final candidate in _nearbyTerms(term)) {
          final current = weights[candidate] ?? 0;
          if (current < 0.78) weights[candidate] = 0.78;
        }
      }
    }

    final scored = <_ScoredDocument>[];
    for (final item in _indexed) {
      if (!includeStarter && !item.document.isCustom) continue;
      var score = 0.0;
      for (final entry in weights.entries) {
        final frequency = item.terms[entry.key] ?? 0;
        if (frequency == 0) continue;
        final df = _documentFrequency[entry.key] ?? 0;
        if (df == 0) continue;
        final idf = math.log(1 + (_indexed.length - df + 0.5) / (df + 0.5));
        final lengthNorm = 1.2 * (1 - 0.72 + 0.72 * item.length / _averageLength);
        final bm25 = idf *
            (frequency * 2.2) /
            (frequency + lengthNorm);
        score += entry.value * bm25;
      }
      if (score <= 0) continue;

      final title = item.normalizedTitle;
      final body = item.normalizedBody;
      if (title.contains(normalizedQuery)) score += 8.5;
      if (body.contains(normalizedQuery)) score += 2.4;
      final titleTerms = item.titleTerms;
      final coverage = mustTerms.where((term) =>
          titleTerms.contains(term) || item.uniqueTerms.contains(term)).length /
          mustTerms.length;
      score += coverage * 5.5;
      if (coverage < 0.45) score *= 0.65;
      if (item.document.title.length < 8) score -= 0.8;
      scored.add(_ScoredDocument(item.document, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    final results = <SearchResult>[];
    for (final scoredDocument in scored) {
      final document = scoredDocument.document;
      if (!seen.add(document.url)) continue;
      final displaySnippet = document.snippet.isNotEmpty
          ? document.snippet
          : excerptAround(document.body, cleanQuery, maxChars: 210);
      results.add(
        SearchResult(
          id: document.id.isEmpty
              ? 'local-${stableHash(document.url)}'
              : document.id,
          kind: ResultKind.web,
          title: document.title,
          url: document.url,
          snippet: displaySnippet,
          sourceId: 'local',
          sourceName: 'My Search',
          domain: null,
          score: scoredDocument.score,
          meta: {
            'local': true,
            'section': document.section,
            'isCustom': document.isCustom,
            'tags': document.tags,
            'indexed': true,
          },
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  /// Runs the Rust BM25 index and maps its compact hit list back to the
  /// documents already held in memory. Returns `null` on any failure so the
  /// Dart scorer can take over without the reader noticing.
  List<SearchResult>? _searchNative(
    String query, {
    required int limit,
    required bool includeStarter,
  }) {
    final response = _core?.searchIndex(
      query,
      limit: limit,
      includeStarter: includeStarter,
    );
    if (response == null) return null;
    final hits = response['hits'];
    if (hits is! List) return null;
    final byId = <String, LocalDocument>{
      for (final document in allDocuments) document.id: document,
    };
    final seen = <String>{};
    final results = <SearchResult>[];
    for (final hit in hits) {
      if (hit is! Map) continue;
      final document = byId[hit['id']?.toString()];
      if (document == null || !seen.add(document.url)) continue;
      final snippet = document.snippet.isNotEmpty
          ? document.snippet
          : excerptAround(document.body, query, maxChars: 210);
      final matched = (hit['matchedTerms'] as List?)
              ?.map((term) => term.toString())
              .where((term) => term.isNotEmpty)
              .toList() ??
          const <String>[];
      results.add(
        SearchResult(
          id: document.id,
          kind: ResultKind.web,
          title: document.title,
          url: document.url,
          snippet: snippet,
          sourceId: 'local',
          sourceName: 'My Search',
          score: (hit['score'] as num?)?.toDouble() ?? 0,
          meta: {
            'local': true,
            'section': document.section,
            'isCustom': document.isCustom,
            'tags': document.tags,
            'matchedTerms': matched,
            'indexed': true,
            'native': true,
          },
        ),
      );
      if (results.length >= limit) break;
    }
    return results;
  }

  Iterable<String> _nearbyTerms(String term) sync* {
    if (term.length < 4) return;
    var found = 0;
    for (final candidate in _vocabulary) {
      if (candidate.length < 3) continue;
      if (candidate[0] != term[0]) continue;
      if ((candidate.length - term.length).abs() > 1) continue;
      if (!_withinOneEdit(term, candidate)) continue;
      yield candidate;
      found += 1;
      if (found >= 4) return;
    }
  }

  static bool _withinOneEdit(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i += 1;
        j += 1;
        continue;
      }
      if (i + 1 < a.length &&
          j + 1 < b.length &&
          a[i] == b[j + 1] &&
          a[i + 1] == b[j]) {
        edits += 1;
        i += 2;
        j += 2;
        continue;
      }
      edits += 1;
      if (edits > 1) return false;
      if (a.length > b.length) {
        i += 1;
      } else if (b.length > a.length) {
        j += 1;
      } else {
        i += 1;
        j += 1;
      }
    }
    if (i < a.length || j < b.length) edits += 1;
    return edits <= 1;
  }

  /// Fetches a public page and adds a compact text extract to the local index.
  /// This is the only time a page is requested without the reader opening it.
  Future<LocalDocument> indexUrl(String rawUrl) async {
    final url = _cleanUrl(rawUrl);
    if (url == null) {
      throw const LocalIndexException('Enter a full http or https address.');
    }
    final existing = _custom.where((document) => document.url == url).toList();
    if (existing.isNotEmpty) {
      return existing.first;
    }

    String html;
    try {
      html = await _http.getString(
        url,
        timeout: const Duration(seconds: 14),
        headers: const {'Accept': 'text/html,application/xhtml+xml'},
      );
    } catch (error) {
      throw LocalIndexException('Could not fetch that page: $error');
    }
    final document = html_parser.parse(html);
    var title = normalizeWhitespace(document.querySelector('title')?.text ?? '');
    final article = document.querySelector('article') ??
        document.querySelector('main') ??
        document.body;
    if (article == null) {
      throw const LocalIndexException('That page had no readable text.');
    }
    for (final tag in const [
      'script',
      'style',
      'noscript',
      'svg',
      'canvas',
      'nav',
      'footer',
      'header',
      'form',
      'aside',
      'iframe',
    ]) {
      for (final element in article.querySelectorAll(tag)) {
        element.remove();
      }
    }
    var body = normalizeWhitespace(article.text);
    if (body.length < 180) {
      throw const LocalIndexException('That page was too short to index usefully.');
    }
    if (body.length > _maxBodyChars) body = body.substring(0, _maxBodyChars);
    if (title.isEmpty) title = domainOf(url);
    if (title.length > 160) title = truncateText(title, 160);

    final page = LocalDocument(
      id: 'local-${stableHash(url)}',
      title: title,
      url: url,
      snippet: truncateText(body, 210),
      body: body,
      section: 'Indexed pages',
      tags: const [],
      addedAt: DateTime.now(),
      isCustom: true,
    );
    _custom.insert(0, page);
    if (_custom.length > _maxCustomDocuments) _custom.removeLast();
    await _persist();
    _rebuild();
    notifyListeners();
    return page;
  }

  /// Adds text captured by reader mode, avoiding a second network request.
  Future<LocalDocument> indexText({
    required String url,
    required String title,
    required String text,
  }) async {
    final cleanUrl = _cleanUrl(url);
    if (cleanUrl == null) {
      throw const LocalIndexException('This page has no public address to index.');
    }
    final cleanTitle = normalizeWhitespace(title);
    final cleanText = normalizeWhitespace(text);
    if (cleanText.length < 80) {
      throw const LocalIndexException('There is not enough readable text to index.');
    }
    final capped = cleanText.length > _maxBodyChars
        ? cleanText.substring(0, _maxBodyChars)
        : cleanText;
    final existingIndex = _custom.indexWhere((document) => document.url == cleanUrl);
    final page = LocalDocument(
      id: existingIndex == -1
          ? 'local-${stableHash(cleanUrl)}'
          : _custom[existingIndex].id,
      title: cleanTitle.isEmpty ? domainOf(cleanUrl) : truncateText(cleanTitle, 160),
      url: cleanUrl,
      snippet: truncateText(capped, 210),
      body: capped,
      section: 'Indexed pages',
      tags: const [],
      addedAt: DateTime.now(),
      isCustom: true,
    );
    if (existingIndex == -1) {
      _custom.insert(0, page);
    } else {
      _custom[existingIndex] = page;
    }
    if (_custom.length > _maxCustomDocuments) _custom.removeLast();
    await _persist();
    _rebuild();
    notifyListeners();
    return page;
  }

  Future<void> removeDocument(String id) async {
    final before = _custom.length;
    _custom.removeWhere((document) => document.id == id);
    if (before == _custom.length) return;
    await _persist();
    _rebuild();
    notifyListeners();
  }

  Future<void> clearCustomDocuments() async {
    if (_custom.isEmpty) return;
    _custom = [];
    await _persist();
    _rebuild();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        _kDocuments,
        jsonEncode(_custom.map((document) => document.toJson()).toList()),
      );
    } catch (_) {
      // Storage is best-effort; the in-memory index remains usable.
    }
  }

  String? _cleanUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final withScheme = value.startsWith('http') ? value : 'https://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.toString();
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _IndexedDocument {
  _IndexedDocument(this.document) {
    terms = <String, int>{};
    final titleTerms = rawTokens(document.title)
        .where((term) => !kStopWords.contains(term))
        .map(stem)
        .where((term) => term.length > 1);
    final bodyTerms = rawTokens(
      '${document.body} ${document.tags.join(' ')} ${document.section}',
    )
        .where((term) => !kStopWords.contains(term))
        .map(stem)
        .where((term) => term.length > 1);
    for (final term in titleTerms) {
      terms[term] = (terms[term] ?? 0) + 3;
    }
    for (final term in bodyTerms) {
      terms[term] = (terms[term] ?? 0) + 1;
    }
    uniqueTerms = terms.keys.toSet();
    this.titleTerms = titleTerms.toSet();
    length = terms.values.fold(0, (total, value) => total + value);
    normalizedTitle = LocalIndex._normalize(document.title);
    normalizedBody = LocalIndex._normalize('${document.body} ${document.snippet}');
  }

  final LocalDocument document;
  late final Map<String, int> terms;
  late final Set<String> uniqueTerms;
  late final Set<String> titleTerms;
  late final int length;
  late final String normalizedTitle;
  late final String normalizedBody;
}

class _ScoredDocument {
  const _ScoredDocument(this.document, this.score);
  final LocalDocument document;
  final double score;
}
