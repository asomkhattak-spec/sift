import 'package:flutter_test/flutter_test.dart';
import 'package:sift/core/utils/text_utils.dart';

void main() {
  group('normalizeWhitespace', () {
    test('collapses runs and trims', () {
      expect(normalizeWhitespace('  a \n\t b\u00A0c  '), 'a b c');
    });
  });

  group('normalizeQuery', () {
    test('replaces smart punctuation', () {
      expect(normalizeQuery('‘sift’ – “private”'), "'sift' - \"private\"");
    });

    test('keeps ordinary punctuation', () {
      expect(normalizeQuery('c++ vs rust?'), 'c++ vs rust?');
    });
  });

  group('isProbablyUrl', () {
    test('accepts schemes, bare hosts and localhost', () {
      expect(isProbablyUrl('https://example.com/a'), isTrue);
      expect(isProbablyUrl('example.com'), isTrue);
      expect(isProbablyUrl('localhost:8080'), isTrue);
    });

    test('rejects queries and malformed hosts', () {
      expect(isProbablyUrl('privacy browser'), isFalse);
      expect(isProbablyUrl(''), isFalse);
      expect(isProbablyUrl('.com'), isFalse);
    });
  });

  group('navigableUrl', () {
    test('adds https to bare hosts', () {
      expect(navigableUrl('example.com/docs'), 'https://example.com/docs');
    });

    test('leaves full URLs intact', () {
      expect(navigableUrl('http://example.com'), 'http://example.com');
    });

    test('returns null for a search phrase', () {
      expect(navigableUrl('how to search'), isNull);
    });
  });

  group('stripTrackingParams', () {
    test('drops campaign and utm parameters', () {
      expect(
        stripTrackingParams(
          'https://example.com/a?utm_source=x&fbclid=1&id=7&gclid=2#top',
        ),
        'https://example.com/a?id=7#top',
      );
    });

    test('returns input untouched when nothing matches', () {
      const url = 'https://example.com/a?id=7';
      expect(stripTrackingParams(url), url);
    });

    test('keeps repeated non-tracking values', () {
      expect(
        stripTrackingParams('https://example.com/?tag=a&tag=b&utm_medium=c'),
        'https://example.com/?tag=a&tag=b',
      );
    });

    test('handles strings without a query', () {
      expect(stripTrackingParams('https://example.com'), 'https://example.com');
    });
  });

  group('domainOf', () {
    test('strips www and returns empty for garbage', () {
      expect(domainOf('https://www.example.com/a'), 'example.com');
      expect(domainOf('not a url'), '');
    });
  });

  group('stripHtml', () {
    test('removes tags and decodes entities', () {
      expect(stripHtml('<p>Hello&nbsp;<b>world</b> &amp; co</p>'), 'Hello world & co');
    });

    test('normalizes plain text', () {
      expect(stripHtml('  plain   text '), 'plain text');
    });
  });

  group('truncateText', () {
    test('keeps short strings', () {
      expect(truncateText('short', 20), 'short');
    });

    test('cuts at a word boundary and adds an ellipsis', () {
      expect(truncateText('the quick brown fox jumps', 16), 'the quick brown…');
    });
  });

  group('stableHash', () {
    test('is deterministic and positive', () {
      final first = stableHash('sift');
      expect(first, stableHash('sift'));
      expect(first, greaterThanOrEqualTo(0));
    });
  });

  group('genericUrlHelpers', () {
    test('builds encoded search URLs', () {
      expect(
        buildBingWebUrl('rust ffi'),
        'https://www.bing.com/search?q=rust+ffi',
      );
    });

    test('compactHostTitle prefers known names', () {
      expect(compactHostTitle('https://en.wikipedia.org/wiki/Search'), 'Wikipedia');
      expect(compactHostTitle('https://example.com/x'), 'Example');
    });
  });
}
