import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sift/core/models/search_models.dart';
import 'package:sift/core/search/providers.dart';
import 'package:sift/core/search/source_catalog.dart';
import 'package:sift/core/services/http_service.dart';
import 'package:sift/core/services/settings_service.dart';

/// Serves canned payloads by URL fragment and records every request so the
/// tests can assert on query parameters without any network access.
class _FakeHttp extends SiftHttpBase {
  _FakeHttp(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<String> calls = [];

  Map<String, dynamic> _bodyFor(String url) {
    calls.add(url);
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
    int maxBytes = 0,
  }) async {
    return _bodyFor(url);
  }

  @override
  Future<String> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 9),
    int cacheSeconds = 0,
    int maxBytes = 0,
  }) async {
    return jsonEncode(_bodyFor(url));
  }

  @override
  void clearCache() {}

  @override
  void setProxy({
    required bool enabled,
    String host = '127.0.0.1',
    int port = 8118,
  }) {}
}

Map<String, dynamic> _commons(String mime, {int duration = 0}) {
  return {
    'query': {
      'pages': [
        {
          'pageid': 11,
          'title': 'File:Alpine_lake_at_sunrise.jpg',
          'imageinfo': [
            {
              'mime': mime,
              'url': 'https://upload.wikimedia.org/original.jpg',
              'thumburl': 'https://upload.wikimedia.org/thumb.jpg',
              'thumbwidth': 720,
              'thumbheight': 480,
              'width': 4000,
              'height': 2667,
              'duration': duration,
              'descriptionurl':
                  'https://commons.wikimedia.org/wiki/File:Alpine_lake_at_sunrise.jpg',
              'extmetadata': {
                'LicenseShortName': {'value': 'CC BY-SA 4.0'},
                'LicenseUrl': {
                  'value': 'https://creativecommons.org/licenses/by-sa/4.0',
                },
                'Artist': {
                  'value':
                      '<a href="//commons.wikimedia.org/wiki/User:E">E. Climber</a>',
                },
                'ImageDescription': {
                  'value': 'Still water below the <b>north face</b>.',
                },
              },
            },
          ],
        },
        {
          'pageid': 12,
          'title': 'File:Ambient_loop.ogg',
          'imageinfo': [
            {
              'mime': 'audio/ogg',
              'url': 'https://upload.wikimedia.org/loop.ogg',
              'descriptionurl':
                  'https://commons.wikimedia.org/wiki/File:Ambient_loop.ogg',
            },
          ],
        },
      ],
    },
  };
}

void main() {
  group('Wikimedia Commons', () {
    test('maps image metadata and drops non-image files', () async {
      final http = _FakeHttp({'commons.wikimedia': _commons('image/jpeg')});
      final results = await WikimediaCommonsProvider(http).search(
        const SearchRequest(
          query: 'alpine lake',
          vertical: SearchVertical.images,
          resultCount: 20,
        ),
      );

      expect(results, hasLength(1));
      final image = results.single;
      expect(image.kind, ResultKind.image);
      expect(image.title, 'Alpine lake at sunrise');
      expect(image.url,
          'https://commons.wikimedia.org/wiki/File:Alpine_lake_at_sunrise.jpg');
      expect(image.imageUrl, 'https://upload.wikimedia.org/thumb.jpg');
      expect(image.thumbnailUrl, 'https://upload.wikimedia.org/thumb.jpg');
      expect(image.author, 'E. Climber');
      expect(image.snippet, contains('E. Climber'));
      expect(image.snippet, contains('Still water below the north face.'));
      expect(image.meta['license'], 'CC BY-SA 4.0');
      expect(image.meta['width'], 720);
      expect(image.meta['height'], 480);
      expect(image.meta['mime'], 'image/jpeg');

      final uri = Uri.parse(http.calls.single);
      expect(uri.queryParameters['gsrsearch'], 'alpine lake');
      expect(uri.queryParameters['gsrnamespace'], '6');
      // The provider asks for a wider page than the UI needs so that audio and
      // documents can be filtered out without starving the grid.
      expect(uri.queryParameters['gsrlimit'], '30');
      expect(uri.queryParameters['iiurlwidth'], '720');
    });

    test('searches freely licensed video and keeps the duration', () async {
      final http = _FakeHttp(
        {'commons.wikimedia': _commons('video/webm', duration: 83)},
      );
      final results = await WikimediaCommonsProvider(http).search(
        const SearchRequest(
          query: 'rust',
          vertical: SearchVertical.videos,
          resultCount: 20,
        ),
      );

      expect(results, hasLength(1));
      final video = results.single;
      expect(video.kind, ResultKind.video);
      expect(video.duration, '1:23');
      expect(video.meta['mime'], 'video/webm');
      expect(video.snippet, contains('1:23'));

      final uri = Uri.parse(http.calls.single);
      expect(uri.queryParameters['gsrsearch'], 'rust filetype:video');
      expect(uri.queryParameters['iiurlwidth'], '640');
      expect(uri.queryParameters['gsrlimit'], '20');
    });

    test('converts the page number into a generator offset', () async {
      final http = _FakeHttp({'commons.wikimedia': _commons('image/jpeg')});
      await WikimediaCommonsProvider(http).search(
        const SearchRequest(
          query: 'alpine lake',
          vertical: SearchVertical.images,
          page: 2,
          resultCount: 20,
        ),
      );

      final uri = Uri.parse(http.calls.single);
      expect(uri.queryParameters['gsroffset'], '80');
    });
  });

  group('Openverse', () {
    test('maps the image response and sends a boolean mature filter', () async {
      final http = _FakeHttp({
        'openverse': {
          'results': [
            {
              'title': 'Mountain light',
              'foreign_landing_url': 'https://www.flickr.com/photos/anna/123',
              'url': 'https://live.staticflickr.com/1/mountains.jpg',
              'thumbnail': 'https://live.staticflickr.com/1/mountains_t.jpg',
              'creator': 'Anna Berg',
              'provider': 'flickr',
              'license': 'by-sa',
              'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/',
              'width': 4000,
              'height': 3000,
              'tags': [
                {'name': 'mountains'},
                {'name': 'snow'},
              ],
            },
            {
              'title': 'Broken landing page',
              'foreign_landing_url': 'not a url',
              'url': 'https://live.staticflickr.com/2/broken.jpg',
            },
          ],
        },
      });

      final provider = OpenverseProvider(http);
      final results = await provider.search(
        const SearchRequest(
          query: 'mountains',
          vertical: SearchVertical.images,
          resultCount: 20,
        ),
      );

      expect(results, hasLength(1));
      final image = results.single;
      expect(image.kind, ResultKind.image);
      expect(image.title, 'Mountain light');
      expect(image.url, 'https://www.flickr.com/photos/anna/123');
      expect(image.imageUrl, 'https://live.staticflickr.com/1/mountains.jpg');
      expect(image.thumbnailUrl,
          'https://live.staticflickr.com/1/mountains_t.jpg');
      expect(image.author, 'Anna Berg');
      expect(image.meta['width'], 4000);
      expect(image.meta['height'], 3000);
      expect(image.meta['license'], 'by-sa');
      expect(image.snippet, contains('BY-SA license'));
      expect(image.snippet, contains('mountains, snow'));

      final uri = Uri.parse(http.calls.single);
      expect(uri.queryParameters['q'], 'mountains');
      expect(uri.queryParameters['page'], '1');
      expect(uri.queryParameters['page_size'], '20');
      expect(uri.queryParameters['filter_dead'], 'true');
      expect(uri.queryParameters['mature'], 'false');
    });

    test('turns safe search off only when the user asks', () async {
      final http = _FakeHttp({'openverse': {'results': []}});
      final provider = OpenverseProvider(http);

      await provider.search(
        const SearchRequest(
          query: 'mountains',
          vertical: SearchVertical.images,
          safeSearch: false,
        ),
      );
      expect(
        Uri.parse(http.calls.single).queryParameters['mature'],
        'true',
      );

      await provider.search(
        const SearchRequest(
          query: 'mountains',
          vertical: SearchVertical.images,
        ),
      );
      expect(
        Uri.parse(http.calls.last).queryParameters['mature'],
        'false',
      );
    });
  });

  test('each provider keeps its tuned timeout ceiling', () {
    final http = _FakeHttp(const {});
    expect(BingWebProvider(http).timeout, const Duration(seconds: 6));
    expect(WikipediaProvider(http).timeout, const Duration(seconds: 6));
    expect(OpenverseProvider(http).timeout, const Duration(seconds: 15));
    expect(WikimediaCommonsProvider(http).timeout, const Duration(seconds: 15));
    expect(DailymotionProvider(http).timeout, const Duration(seconds: 8));
    expect(
      SearxProvider(http, () => 'https://searx.example').timeout,
      const Duration(seconds: 10),
    );
  });

  test('Commons is on by default for both media tabs', () {
    final commons = kSourceCatalog.firstWhere((source) => source.id == 'commons');
    expect(
      commons.verticals,
      containsAll([SearchVertical.images, SearchVertical.videos]),
    );
    expect(kDefaultEnabledSources, contains('commons'));
  });
}