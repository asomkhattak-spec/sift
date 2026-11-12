import 'package:flutter_test/flutter_test.dart';
import 'package:sift/core/models/search_models.dart';

SearchResult result({
  required String id,
  required String url,
  String title = 'Title',
  double score = 0,
}) {
  return SearchResult(
    id: id,
    kind: ResultKind.web,
    title: title,
    url: url,
    snippet: 'Snippet',
    sourceId: 'test',
    sourceName: 'Test',
    score: score,
  );
}

void main() {
  test('SearchVertical labels stay stable', () {
    expect(SearchVertical.all.label, 'All');
    expect(SearchVertical.discuss.pluralTitle, 'Conversations');
    expect(SearchVertical.images.isMedia, isTrue);
    expect(SearchVertical.news.isMedia, isFalse);
  });

  test('SearchResult round-trips through JSON', () {
    final original = SearchResult(
      id: 'r1',
      kind: ResultKind.news,
      title: 'A headline',
      url: 'https://example.com/story',
      snippet: 'Something happened.',
      sourceId: 'gnews',
      sourceName: 'Google News',
      publishedAt: DateTime.utc(2026, 3, 7),
      imageUrl: 'https://example.com/i.jpg',
      author: 'A. Writer',
      meta: const {'k': 'v'},
      score: 0.75,
    );
    final decoded = SearchResult.fromJson(original.toJson());
    expect(decoded.id, original.id);
    expect(decoded.kind, ResultKind.news);
    expect(decoded.publishedAt, original.publishedAt);
    expect(decoded.meta['k'], 'v');
    expect(decoded.score, closeTo(0.75, 0.0001));
  });

  test('SearchResult falls back safely for unknown kinds', () {
    final decoded = SearchResult.fromJson(const {'kind': 'hologram'});
    expect(decoded.kind, ResultKind.web);
    expect(decoded.title, '');
    expect(decoded.meta, isEmpty);
  });

  test('host and displayUrl come from the URL when domain is absent', () {
    final item = result(id: '1', url: 'https://www.example.com/a/b?q=1');
    expect(item.host, 'example.com');
    expect(item.displayUrl, 'example.com/a/b');
  });

  test('copyWith keeps identity and replaces only requested fields', () {
    final item = result(id: '1', url: 'https://example.com', score: 1);
    final copy = item.copyWith(score: 2, title: 'Better');
    expect(copy.id, '1');
    expect(copy.url, 'https://example.com');
    expect(copy.title, 'Better');
    expect(copy.score, 2);
  });

  test('SearchBundle merge dedupes by host and path', () {
    final first = SearchBundle(
      query: 'q',
      vertical: SearchVertical.all,
      groups: {
        SearchVertical.all: [
          result(id: 'a', url: 'https://example.com/x'),
          result(id: 'b', url: 'https://other.com/y'),
        ],
      },
      statuses: const [],
      elapsedMs: 10,
      nextPage: 1,
    );
    final second = SearchBundle(
      query: 'q',
      vertical: SearchVertical.all,
      groups: {
        SearchVertical.all: [
          result(id: 'c', url: 'https://www.example.com/x/'),
          result(id: 'd', url: 'https://third.com/z'),
        ],
      },
      statuses: const [],
      elapsedMs: 20,
      nextPage: 2,
    );
    final merged = first.merge(second);
    expect(merged.all.map((r) => r.id), ['a', 'b', 'd']);
    expect(merged.elapsedMs, 30);
    expect(merged.nextPage, 2);
  });

  test('SearchBundle exposes vertical groups and emptiness', () {
    const empty = SearchBundle(
      query: 'q',
      vertical: SearchVertical.all,
      groups: {},
      statuses: [],
      elapsedMs: 0,
    );
    expect(empty.isEmpty, isTrue);
    expect(empty.forVertical(SearchVertical.web), isEmpty);

    final bundle = SearchBundle(
      query: 'q',
      vertical: SearchVertical.all,
      groups: {
        SearchVertical.web: [result(id: 'w', url: 'https://example.com')],
      },
      statuses: const [],
      elapsedMs: 0,
    );
    expect(bundle.isEmpty, isFalse);
    expect(bundle.forVertical(SearchVertical.web), hasLength(1));
    expect(bundle.forVertical(SearchVertical.all), isEmpty);
  });

  test('SearchRequest copyWith keeps preserved settings', () {
    const request = SearchRequest(
      query: 'one',
      vertical: SearchVertical.news,
      resultCount: 20,
      safeSearch: false,
      language: 'de',
    );
    final next = request.copyWith(query: 'two', page: 3);
    expect(next.query, 'two');
    expect(next.page, 3);
    expect(next.vertical, SearchVertical.news);
    expect(next.resultCount, 20);
    expect(next.safeSearch, isFalse);
    expect(next.language, 'de');
  });
}
