import 'package:flutter/foundation.dart';

enum SearchVertical { all, web, images, news, videos, discuss }

extension SearchVerticalX on SearchVertical {
  String get label => switch (this) {
        SearchVertical.all => 'All',
        SearchVertical.web => 'Web',
        SearchVertical.images => 'Images',
        SearchVertical.news => 'News',
        SearchVertical.videos => 'Videos',
        SearchVertical.discuss => 'Discuss',
      };

  String get pluralTitle => switch (this) {
        SearchVertical.all => 'Results',
        SearchVertical.web => 'Web results',
        SearchVertical.images => 'Images',
        SearchVertical.news => 'News',
        SearchVertical.videos => 'Videos',
        SearchVertical.discuss => 'Conversations',
      };

  bool get isMedia =>
      this == SearchVertical.images || this == SearchVertical.videos;
}

enum ResultKind { web, image, news, video, discussion }

@immutable
class SearchResult {
  const SearchResult({
    required this.id,
    required this.kind,
    required this.title,
    required this.url,
    required this.snippet,
    required this.sourceId,
    required this.sourceName,
    this.publishedAt,
    this.domain,
    this.imageUrl,
    this.thumbnailUrl,
    this.author,
    this.duration,
    this.meta = const {},
    this.score = 0,
  });

  final String id;
  final ResultKind kind;
  final String title;
  final String url;
  final String snippet;
  final String sourceId;
  final String sourceName;
  final DateTime? publishedAt;
  final String? domain;
  final String? imageUrl;
  final String? thumbnailUrl;
  final String? author;
  final String? duration;
  final Map<String, dynamic> meta;
  final double score;

  String get host {
    if (domain != null && domain!.isNotEmpty) return domain!;
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty) return sourceName;
    return parsed.host.replaceFirst('www.', '');
  }

  String get displayUrl {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    final path = parsed.path == '/' ? '' : parsed.path;
    final shown = '${parsed.host.replaceFirst('www.', '')}$path';
    return shown.length > 72 ? '${shown.substring(0, 69)}…' : shown;
  }

  SearchResult copyWith({double? score, String? snippet, String? title}) {
    return SearchResult(
      id: id,
      kind: kind,
      title: title ?? this.title,
      url: url,
      snippet: snippet ?? this.snippet,
      sourceId: sourceId,
      sourceName: sourceName,
      publishedAt: publishedAt,
      domain: domain,
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      author: author,
      duration: duration,
      meta: meta,
      score: score ?? this.score,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'url': url,
        'snippet': snippet,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'publishedAt': publishedAt?.toIso8601String(),
        'domain': domain,
        'imageUrl': imageUrl,
        'thumbnailUrl': thumbnailUrl,
        'author': author,
        'duration': duration,
        'meta': meta,
        'score': score,
      };

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      id: json['id'] as String? ?? '',
      kind: ResultKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => ResultKind.web,
      ),
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      domain: json['domain'] as String?,
      imageUrl: json['imageUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      author: json['author'] as String?,
      duration: json['duration'] as String?,
      meta: (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }
}

@immutable
class AnswerFact {
  const AnswerFact(this.label, this.value);
  final String label;
  final String value;
}

@immutable
class InstantAnswer {
  const InstantAnswer({
    required this.kind,
    required this.title,
    this.subtitle,
    this.body,
    this.facts = const [],
    this.link,
    this.linkLabel,
    this.source,
    this.imageUrl,
    this.isLive = false,
  });

  final String kind;
  final String title;
  final String? subtitle;
  final String? body;
  final List<AnswerFact> facts;
  final String? link;
  final String? linkLabel;
  final String? source;
  final String? imageUrl;
  final bool isLive;
}

@immutable
class ProviderStatus {
  const ProviderStatus({
    required this.sourceId,
    required this.sourceName,
    required this.ok,
    required this.count,
    required this.elapsedMs,
    this.error,
    this.host,
  });

  final String sourceId;
  final String sourceName;
  final bool ok;
  final int count;
  final int elapsedMs;
  final String? error;
  final String? host;
}

@immutable
class SearchRequest {
  const SearchRequest({
    required this.query,
    this.vertical = SearchVertical.all,
    this.page = 0,
    this.safeSearch = true,
    this.resultCount = 10,
    this.language = 'en',
  });

  final String query;
  final SearchVertical vertical;
  final int page;
  final bool safeSearch;
  final int resultCount;
  final String language;

  SearchRequest copyWith({
    String? query,
    SearchVertical? vertical,
    int? page,
  }) {
    return SearchRequest(
      query: query ?? this.query,
      vertical: vertical ?? this.vertical,
      page: page ?? this.page,
      safeSearch: safeSearch,
      resultCount: resultCount,
      language: language,
    );
  }
}

@immutable
class SearchBundle {
  const SearchBundle({
    required this.query,
    required this.vertical,
    required this.groups,
    required this.statuses,
    required this.elapsedMs,
    this.answer,
    this.nextPage = 0,
    this.complete = true,
  });

  final String query;
  final SearchVertical vertical;
  final Map<SearchVertical, List<SearchResult>> groups;
  final List<ProviderStatus> statuses;
  final int elapsedMs;
  final InstantAnswer? answer;
  final int nextPage;

  /// False while providers are still answering; the UI can keep a subtle
  /// "gathering" indicator instead of blocking on the slowest source.
  final bool complete;

  List<SearchResult> get all => groups[SearchVertical.all] ?? const [];
  List<SearchResult> get web => groups[SearchVertical.web] ?? const [];
  List<SearchResult> get images => groups[SearchVertical.images] ?? const [];
  List<SearchResult> get news => groups[SearchVertical.news] ?? const [];
  List<SearchResult> get videos => groups[SearchVertical.videos] ?? const [];
  List<SearchResult> get discussions =>
      groups[SearchVertical.discuss] ?? const [];

  List<SearchResult> forVertical(SearchVertical vertical) {
    if (vertical == SearchVertical.all) return all;
    return groups[vertical] ?? const [];
  }

  bool get isEmpty => all.isEmpty && web.isEmpty && images.isEmpty && news.isEmpty &&
      videos.isEmpty && discussions.isEmpty;

  SearchBundle merge(SearchBundle newer) {
    final merged = <SearchVertical, List<SearchResult>>{};
    for (final vertical in SearchVertical.values) {
      final existing = groups[vertical] ?? const <SearchResult>[];
      final extra = newer.groups[vertical] ?? const <SearchResult>[];
      if (existing.isEmpty && extra.isEmpty) continue;
      final seen = <String>{};
      merged[vertical] = [
        ...existing,
        ...extra,
      ].where((r) => seen.add(_dedupeKey(r))).toList(growable: false);
    }
    return SearchBundle(
      query: newer.query,
      vertical: newer.vertical,
      groups: merged,
      statuses: newer.statuses,
      elapsedMs: elapsedMs + newer.elapsedMs,
      answer: answer ?? newer.answer,
      nextPage: newer.nextPage,
    );
  }

  static String _dedupeKey(SearchResult result) {
    final uri = Uri.tryParse(result.url);
    if (uri == null) return result.title.toLowerCase().trim();
    return '${uri.host.replaceFirst('www.', '')}${uri.path.replaceAll(RegExp(r'/+$'), '')}'
        .toLowerCase();
  }
}

@immutable
class QuerySuggestion {
  const QuerySuggestion({required this.text, this.kind = SuggestionKind.web});

  final String text;
  final SuggestionKind kind;
}

enum SuggestionKind { history, local, web }

@immutable
class SourceDefinition {
  const SourceDefinition({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.homepage,
    required this.host,
    required this.privacyNote,
    this.defaultEnabled = true,
    this.isCustom = false,
    this.verticals = const {SearchVertical.web},
  });

  final String id;
  final String name;
  final String shortName;
  final String description;
  final String homepage;
  final String host;
  final String privacyNote;
  final bool defaultEnabled;
  final bool isCustom;
  final Set<SearchVertical> verticals;
}
