import 'dart:async';

import '../models/search_models.dart';
import '../services/http_service.dart';
import '../services/settings_service.dart';
import '../services/sift_core.dart';
import '../utils/text_utils.dart';
import 'instant_answers.dart';
import 'local_index.dart';
import 'providers.dart';
import 'ranking.dart';
import 'suggestions.dart';

class DiscoverFeed {
  const DiscoverFeed({
    required this.stories,
    required this.images,
    required this.shelf,
    required this.loadedAt,
    this.errors = const [],
  });

  final List<SearchResult> stories;
  final List<SearchResult> images;
  final List<LocalDocument> shelf;
  final DateTime loadedAt;
  final List<String> errors;

  bool get isEmpty => stories.isEmpty && images.isEmpty && shelf.isEmpty;
}

class SearchEngine {
  SearchEngine({
    required SettingsService settings,
    required SiftHttp http,
    required LocalIndex localIndex,
    SiftCore? core,
  })  : _settings = settings,
        _local = localIndex,
        _core = core,
        _answers = InstantAnswerEngine(http),
        _suggestions = SuggestionEngine(http) {
    _bing = BingWebProvider(http);
    _wikipedia = WikipediaProvider(http);
    _openverse = OpenverseProvider(http);
    _news = GoogleNewsProvider(http);
    _videos = DailymotionProvider(http);
    _hackerNews = HackerNewsProvider(http);
    _stackExchange = StackExchangeProvider(http);
    _searx = SearxProvider(http, () => settings.searxUrl);
  }

  final SettingsService _settings;
  final LocalIndex _local;
  final SiftCore? _core;
  final InstantAnswerEngine _answers;
  final SuggestionEngine _suggestions;

  late final BingWebProvider _bing;
  late final WikipediaProvider _wikipedia;
  late final OpenverseProvider _openverse;
  late final GoogleNewsProvider _news;
  late final DailymotionProvider _videos;
  late final HackerNewsProvider _hackerNews;
  late final StackExchangeProvider _stackExchange;
  late final SearxProvider _searx;

  LocalIndex get localIndex => _local;

  Future<SearchBundle> search(
    SearchRequest request, {
    void Function(SearchBundle)? onPartial,
  }) async {
    final query = normalizeQuery(request.query);
    final started = Stopwatch()..start();
    if (query.isEmpty) {
      return SearchBundle(
        query: query,
        vertical: request.vertical,
        groups: const {},
        statuses: const [],
        elapsedMs: 0,
        nextPage: 0,
      );
    }

    final tasks = _settings.localOnlyMode ? const <_Task>[] : _tasksFor(request);
    final statuses = <ProviderStatus>[];
    final byVertical = <SearchVertical, List<SearchResult>>{};
    final localOnly = _settings.localOnlyMode;
    final answerFuture = _settings.instantAnswers &&
            (request.vertical == SearchVertical.all ||
                request.vertical == SearchVertical.web) &&
            request.page == 0
        ? _answers
            .resolve(query, allowNetwork: !localOnly)
            .catchError((Object _) => null)
            .timeout(
              const Duration(seconds: 4),
              onTimeout: () => null,
            )
        : Future<InstantAnswer?>.value(null);

    await Future.wait(tasks.map((task) async {
      final stopwatch = Stopwatch()..start();
      try {
        final results = await task.provider
            .search(_requestForTask(request, task.vertical, query))
            .timeout(const Duration(seconds: 6));
        stopwatch.stop();
        statuses.add(
          ProviderStatus(
            sourceId: task.provider.definition.id,
            sourceName: task.provider.definition.shortName,
            ok: true,
            count: results.length,
            elapsedMs: stopwatch.elapsedMilliseconds,
            host: task.provider.definition.host,
          ),
        );
        byVertical.putIfAbsent(task.vertical, () => []).addAll(results);
      } catch (error) {
        stopwatch.stop();
        statuses.add(
          ProviderStatus(
            sourceId: task.provider.definition.id,
            sourceName: task.provider.definition.shortName,
            ok: false,
            count: 0,
            elapsedMs: stopwatch.elapsedMilliseconds,
            error: _friendlyError(error),
            host: task.provider.definition.host,
          ),
        );
      }
      onPartial?.call(
        _assemble(
          request,
          query,
          byVertical,
          statuses,
          started,
          tasks: tasks,
        ),
      );
    }));

    final answer = await answerFuture;
    started.stop();
    return _assemble(
      request,
      query,
      byVertical,
      statuses,
      started,
      answer: answer,
      tasks: tasks,
      finalPass: true,
    );
  }

  SearchBundle _assemble(
    SearchRequest request,
    String query,
    Map<SearchVertical, List<SearchResult>> byVertical,
    List<ProviderStatus> statuses,
    Stopwatch started, {
    InstantAnswer? answer,
    required List<_Task> tasks,
    bool finalPass = false,
  }) {
    final groups = <SearchVertical, List<SearchResult>>{};
    for (final entry in byVertical.entries) {
      final vertical = entry.key;
      final ranked = _rankProviders(
        entry.value,
        query,
        vertical: vertical,
      );
      if (ranked.isEmpty) continue;
      groups[vertical] = ranked.take(_limitFor(vertical, request.resultCount)).toList();
    }

    if (request.vertical == SearchVertical.all && groups.isNotEmpty) {
      final combined = <SearchResult>[
        ...(groups[SearchVertical.web] ?? const <SearchResult>[]).take(8),
        ...(groups[SearchVertical.news] ?? const <SearchResult>[]).take(3),
        ...(groups[SearchVertical.discuss] ?? const <SearchResult>[]).take(2),
        ...(groups[SearchVertical.videos] ?? const <SearchResult>[]).take(2),
        ...(groups[SearchVertical.images] ?? const <SearchResult>[]).take(4),
      ];
      final all = _rankProviders(
        combined,
        query,
        vertical: SearchVertical.all,
        diversify: false,
      );
      if (all.isNotEmpty) {
        groups[SearchVertical.all] =
            all.take(_limitFor(SearchVertical.all, request.resultCount)).toList();
      }
    } else if (groups[request.vertical] != null) {
      groups[SearchVertical.all] = groups[request.vertical]!;
    }

    final sorted = [...statuses]..sort((a, b) {
        if (a.ok != b.ok) return a.ok ? -1 : 1;
        return a.sourceName.compareTo(b.sourceName);
      });
    final canPage = tasks.any((task) => task.provider.supportsPaging) &&
        groups.values.any((results) => results.isNotEmpty) &&
        request.page < 5;
    return SearchBundle(
      query: query,
      vertical: request.vertical,
      groups: groups,
      statuses: sorted,
      elapsedMs: started.elapsedMilliseconds,
      answer: answer,
      nextPage: canPage ? request.page + 1 : 0,
      complete: finalPass,
    );
  }

  /// Prefer the Rust fusion model; keep the Dart ranker as a hard fallback.
  List<SearchResult> _rankProviders(
    List<SearchResult> input,
    String query, {
    required SearchVertical vertical,
    bool diversify = true,
  }) {
    final limit = _limitFor(vertical, 30);
    final native = _core?.rank(
      query,
      input,
      limit: limit,
      diversify: diversify && vertical != SearchVertical.images,
      maxPerHost: 2,
    );
    if (native != null) return native;
    return rankAndDedupe(
      input,
      query,
      diversify: diversify && vertical != SearchVertical.images,
      maxPerHost: 2,
    );
  }

  SearchRequest _requestForTask(
    SearchRequest original,
    SearchVertical vertical,
    String query,
  ) {
    final extra = vertical == SearchVertical.images ? 10 : 2;
    return SearchRequest(
      query: query,
      vertical: vertical,
      page: original.page,
      safeSearch: original.safeSearch,
      resultCount: (original.resultCount + extra).clamp(10, 30).toInt(),
      language: original.language,
    );
  }

  int _limitFor(SearchVertical vertical, int requested) {
    final base = requested.clamp(10, 30).toInt();
    return switch (vertical) {
      SearchVertical.images => base + 8,
      SearchVertical.videos => base + 2,
      SearchVertical.all => base + 4,
      _ => base + 2,
    };
  }

  List<_Task> _tasksFor(SearchRequest request) {
    final tasks = <_Task>[];
    void add(SearchProvider provider, SearchVertical vertical) {
      if (!_settings.isSourceEnabled(provider.definition.id)) return;
      if (provider.definition.id == 'searx' && _settings.searxUrl.trim().isEmpty) {
        return;
      }
      tasks.add(_Task(provider, vertical));
    }

    switch (request.vertical) {
      case SearchVertical.all:
        add(_bing, SearchVertical.web);
        add(_wikipedia, SearchVertical.web);
        add(_news, SearchVertical.news);
        add(_openverse, SearchVertical.images);
        add(_videos, SearchVertical.videos);
        add(_hackerNews, SearchVertical.discuss);
        add(_stackExchange, SearchVertical.discuss);
        add(_searx, SearchVertical.web);
        break;
      case SearchVertical.web:
        add(_bing, SearchVertical.web);
        add(_wikipedia, SearchVertical.web);
        add(_searx, SearchVertical.web);
        break;
      case SearchVertical.images:
        add(_openverse, SearchVertical.images);
        add(_searx, SearchVertical.images);
        break;
      case SearchVertical.news:
        add(_news, SearchVertical.news);
        add(_searx, SearchVertical.news);
        break;
      case SearchVertical.videos:
        add(_videos, SearchVertical.videos);
        add(_searx, SearchVertical.videos);
        break;
      case SearchVertical.discuss:
        add(_hackerNews, SearchVertical.discuss);
        add(_stackExchange, SearchVertical.discuss);
        break;
    }
    return tasks;
  }

  Future<List<QuerySuggestion>> suggest(
    String raw, {
    List<QuerySuggestion> local = const [],
    int limit = 8,
  }) {
    return _suggestions.suggest(raw, local: local, limit: limit);
  }

  Future<DiscoverFeed> discover() async {
    final errors = <String>[];
    final storiesFuture = _settings.isSourceEnabled('hackernews')
        ? _hackerNews.frontPage(limit: 14).catchError((Object error) {
            errors.add('Front page: ${_friendlyError(error)}');
            return <SearchResult>[];
          })
        : Future<List<SearchResult>>.value(<SearchResult>[]);
    final imagesFuture = _settings.isSourceEnabled('openverse')
        ? _openverse
            .search(
              const SearchRequest(
                query: 'landscape photography',
                vertical: SearchVertical.images,
                resultCount: 18,
              ),
            )
            .catchError((Object error) {
            errors.add('Images: ${_friendlyError(error)}');
            return <SearchResult>[];
          })
        : Future<List<SearchResult>>.value(<SearchResult>[]);

    final results = await Future.wait<Object>([
      storiesFuture,
      imagesFuture,
    ]);
    final stories = (results[0] as List<SearchResult>);
    final images = (results[1] as List<SearchResult>);

    if (!_local.isLoaded) await _local.load();
    final shelf = _settings.starterIndexEnabled
        ? _local.starterDocuments.toList()
        : <LocalDocument>[];
    if (shelf.length > 6) {
      final start = DateTime.now().difference(DateTime(2026)).inDays % shelf.length;
      final rotated = <LocalDocument>[
        ...shelf.skip(start),
        ...shelf.take(start),
      ];
      shelf
        ..clear()
        ..addAll(rotated.take(6));
    }

    return DiscoverFeed(
      stories: stories,
      images: images.take(10).toList(growable: false),
      shelf: shelf.take(6).toList(growable: false),
      loadedAt: DateTime.now(),
      errors: errors,
    );
  }

  String _friendlyError(Object error) {
    if (error is SiftHttpException) {
      if (error.statusCode != null) return 'HTTP ${error.statusCode}';
      return error.message;
    }
    if (error is TimeoutException) return 'Timed out';
    if (error is FormatException) return 'Unreadable response';
    return 'Unavailable';
  }
}

class _Task {
  const _Task(this.provider, this.vertical);
  final SearchProvider provider;
  final SearchVertical vertical;
}
