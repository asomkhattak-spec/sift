import 'package:flutter_test/flutter_test.dart';
import 'package:sift/core/models/search_models.dart';
import 'package:sift/core/search/ranking.dart';

SearchResult web(String id, String title, String snippet, String url) {
  return SearchResult(
    id: id,
    kind: ResultKind.web,
    title: title,
    url: url,
    snippet: snippet,
    sourceId: 'test',
    sourceName: 'Test',
  );
}

void main() {
  test('stem normalizes common suffixes and leaves short words alone', () {
    expect(stem('running'), 'runn');
    expect(stem('privacy'), 'privacy');
    expect(stem('policies'), 'policy');
    expect(stem('the'), 'the');
  });

  test('queryTerms removes stop words and dedupes', () {
    final terms = queryTerms('the private browser for private tracking');
    expect(terms, contains('private'));
    expect(terms, contains('browser'));
    expect(terms, contains('track'));
    expect(terms, isNot(contains('the')));
    expect(terms.where((t) => t == 'private'), hasLength(1));
  });

  test('expandedTerms adds curated synonyms', () {
    final terms = expandedTerms('privacy');
    expect(terms, contains('privacy'));
    expect(terms, contains('private'));
    expect(terms, contains('anonymity'));
  });

  test('coverage is a fraction of matched terms', () {
    expect(coverage(const [], const {}), 0);
    expect(coverage(['a', 'b'], {'a', 'b'}), 1);
    expect(coverage(['a', 'b'], {'a'}), 0.5);
  });

  test('scoreResult rewards an exact title and relevant snippet', () {
    final relevant = web(
      'b',
      'Sift private search',
      'A private search room with no ads.',
      'https://example.com/b',
    );
    final unrelated = web(
      'a',
      'Unrelated',
      'Nothing here.',
      'https://example.com/a',
    );
    expect(scoreResult(relevant, 'sift private search'),
        greaterThan(scoreResult(unrelated, 'sift private search')));
  });

  test('rankAndDedupe filters invalid results and orders by score', () {
    final ranked = rankAndDedupe([
      web('a', 'Unrelated', 'nothing', 'https://example.com/a'),
      web('b', 'Sift private search', 'private search',
          'https://example.com/b'),
      web('bad', '', 'empty title', 'https://example.com/c'),
      web('scheme', 'Mail link', 'x', 'mailto:someone@example.com'),
    ], 'sift private search');
    expect(ranked.map((r) => r.id), ['b', 'a']);
  });

  test('rankAndDedupe removes canonical URL duplicates', () {
    final ranked = rankAndDedupe([
      web('a', 'One', 'same', 'https://example.com/path/'),
      web('b', 'Two', 'same', 'https://www.example.com/path'),
      web('c', 'Three', 'same', 'https://other.com/path'),
    ], 'path');
    expect(ranked.map((r) => r.id), containsAll(['a', 'c']));
    expect(ranked.map((r) => r.id), isNot(contains('b')));
  });

  test('excerptAround centers a matching term and adds ellipses', () {
    final text = '${'prefix ' * 40}needle in the middle ${'suffix ' * 40}';
    final excerpt = excerptAround(text, 'needle', maxChars: 120);
    expect(excerpt, contains('needle'));
    expect(excerpt.startsWith('…'), isTrue);
    expect(excerpt.endsWith('…'), isTrue);
  });

  test('excerptAround returns short text unchanged', () {
    expect(excerptAround('short text', 'short'), 'short text');
  });
}
