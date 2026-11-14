import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../models/search_models.dart';
import '../services/http_service.dart';
import '../utils/formatters.dart';
import '../utils/text_utils.dart';
import 'source_catalog.dart';

SourceDefinition _source(String id) =>
    kSourceCatalog.firstWhere((item) => item.id == id);

abstract class SearchProvider {
  SearchProvider(this.http, this.definition);

  final SiftHttpBase http;
  final SourceDefinition definition;

  bool supports(SearchVertical vertical) =>
      definition.verticals.contains(vertical);

  bool get supportsPaging => true;

  /// Per-source ceiling. Feed endpoints answer in well under a second, while
  /// image indexes and MediaWiki generators deserve a little more room.
  Duration get timeout => const Duration(seconds: 6);

  Future<List<SearchResult>> search(SearchRequest request);
}

String _idFor(String sourceId, String url) => '$sourceId-${stableHash(url)}';

DateTime? _rssDate(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  try {
    return HttpDate.parse(value);
  } catch (_) {
    return DateTime.tryParse(value);
  }
}

XmlElement? _child(XmlElement parent, String name) {
  for (final element in parent.childElements) {
    if (element.localName == name) return element;
  }
  return null;
}

String _childText(XmlElement parent, String name) {
  return _child(parent, name)?.innerText.trim() ?? '';
}

String _mediaThumbnail(XmlElement item) {
  for (final element in item.descendants.whereType<XmlElement>()) {
    if (element.localName == 'content' || element.localName == 'thumbnail') {
      final url = element.getAttribute('url');
      if (url != null && url.startsWith('http')) return url;
    }
  }
  return '';
}

String _titleWithoutPublisher(String title, String? publisher) {
  if (publisher == null || publisher.isEmpty) return title;
  final suffix = ' - $publisher';
  if (title.endsWith(suffix)) {
    return title.substring(0, title.length - suffix.length).trim();
  }
  return title;
}

/* --------------------------------------------------------------------------
 * Web
 * ------------------------------------------------------------------------ */

class BingWebProvider extends SearchProvider {
  BingWebProvider(SiftHttpBase http) : super(http, _source('bing'));

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final count = request.resultCount.clamp(10, 30);
    final uri = Uri.https('www.bing.com', '/search', {
      'q': request.query,
      'format': 'rss',
      'count': '$count',
      'first': '${request.page * count + 1}',
      'setlang': request.language,
      'cc': 'us',
      if (request.safeSearch) 'adlt': 'strict',
    });

    final body = await http.getString(
      uri.toString(),
      headers: const {'Accept': 'application/rss+xml, application/xml, text/xml'},
      timeout: const Duration(seconds: 8),
    );
    final document = XmlDocument.parse(body);
    final items = document.findAllElements('item');
    final results = <SearchResult>[];

    for (final item in items) {
      final title = stripHtml(_childText(item, 'title'));
      final link = _childText(item, 'link');
      if (title.isEmpty || !link.startsWith('http')) continue;
      final snippet = stripHtml(_childText(item, 'description'));
      final published = _rssDate(_childText(item, 'pubDate'));
      results.add(
        SearchResult(
          id: _idFor('bing', link),
          kind: ResultKind.web,
          title: title,
          url: link,
          snippet: snippet,
          sourceId: 'bing',
          sourceName: 'Bing',
          publishedAt: published,
          domain: domainOf(link),
        ),
      );
    }
    return results;
  }
}

class WikipediaProvider extends SearchProvider {
  WikipediaProvider(SiftHttpBase http) : super(http, _source('wikipedia'));

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final limit = request.resultCount.clamp(10, 20);
    final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'generator': 'search',
      'gsrsearch': request.query,
      'gsrlimit': '$limit',
      'gsroffset': '${request.page * limit}',
      'gsrnamespace': '0',
      'prop': 'extracts|pageimages',
      'exintro': '1',
      'explaintext': '1',
      'exsectionformat': 'plain',
      'piprop': 'thumbnail',
      'pithumbsize': '480',
      'redirects': '1',
    });

    final data = await http.getJson(uri.toString());
    final query = data['query'];
    if (query is! Map) return const [];
    final rawPages = query['pages'];
    if (rawPages is! Map) return const [];
    final pages = rawPages.values.whereType<Map>().toList()
      ..sort(
        (a, b) => (a['index'] as num? ?? 0).compareTo(b['index'] as num? ?? 0),
      );

    final results = <SearchResult>[];
    for (final page in pages) {
      final title = (page['title'] as String? ?? '').trim();
      final rawExtract = page['extract'] as String? ?? '';
      final extract = normalizeWhitespace(rawExtract);
      if (title.isEmpty) continue;
      final pageId = page['pageid'];
      final url = pageId is num
          ? 'https://en.wikipedia.org/?curid=$pageId'
          : 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';
      final thumb = page['thumbnail'];
      final thumbnail = thumb is Map ? thumb['source'] as String? : null;
      results.add(
        SearchResult(
          id: _idFor('wikipedia', '$pageId$title'),
          kind: ResultKind.web,
          title: title,
          url: url,
          snippet: extract.isEmpty ? '' : truncateText(extract, 320),
          sourceId: 'wikipedia',
          sourceName: 'Wikipedia',
          domain: 'en.wikipedia.org',
          thumbnailUrl: thumbnail,
          meta: {'pageId': pageId, 'extract': extract},
        ),
      );
    }
    return results;
  }
}

/* --------------------------------------------------------------------------
 * Images
 * ------------------------------------------------------------------------ */

class OpenverseProvider extends SearchProvider {
  OpenverseProvider(SiftHttpBase http) : super(http, _source('openverse'));

  @override
  Duration get timeout => const Duration(seconds: 15);

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final limit = request.resultCount.clamp(10, 30);
    final uri = Uri.https('api.openverse.org', '/v1/images/', {
      'q': request.query,
      'page': '${request.page + 1}',
      'page_size': '$limit',
      'filter_dead': 'true',
      // Openverse accepts a boolean, not the string `all`. Sending an invalid
      // value made every request fall back to the index default.
      'mature': request.safeSearch ? 'false' : 'true',
    });

    final data = await http.getJson(uri.toString());
    final items = data['results'];
    if (items is! List) return const [];

    final results = <SearchResult>[];
    for (final raw in items.whereType<Map>()) {
      final landing = raw['foreign_landing_url'] as String? ?? '';
      final image = raw['url'] as String? ?? '';
      if (!landing.startsWith('http') || !image.startsWith('http')) continue;
      final license = (raw['license'] as String? ?? '').toUpperCase();
      final creator = raw['creator'] as String? ?? '';
      final provider = raw['provider'] as String? ?? raw['source'] as String? ?? '';
      final tags = raw['tags'];
      final tagNames = tags is List
          ? tags
              .whereType<Map>()
              .map((tag) => tag['name']?.toString() ?? '')
              .where((tag) => tag.isNotEmpty)
              .take(4)
              .toList()
          : const <String>[];
      final details = <String>[
        if (creator.isNotEmpty) creator,
        if (provider.isNotEmpty) provider,
        if (license.isNotEmpty) '$license license',
      ];
      final width = raw['width'];
      final height = raw['height'];
      results.add(
        SearchResult(
          id: _idFor('openverse', landing),
          kind: ResultKind.image,
          title: (raw['title'] as String? ?? 'Untitled image').trim(),
          url: landing,
          snippet: details.isEmpty
              ? 'Openly licensed image'
              : '${details.join(' · ')}${tagNames.isEmpty ? '' : ' · ${tagNames.join(', ')}'}',
          sourceId: 'openverse',
          sourceName: 'Openverse',
          domain: domainOf(landing),
          imageUrl: image,
          thumbnailUrl: raw['thumbnail'] as String? ?? image,
          author: creator.isEmpty ? null : creator,
          meta: {
            'license': raw['license'],
            'licenseUrl': raw['license_url'],
            'attribution': raw['attribution'],
            'width': width,
            'height': height,
            'provider': provider,
          },
        ),
      );
    }
    return results;
  }
}

/// Wikimedia Commons through the MediaWiki search generator. One adapter
/// serves both media tabs: photographs for Images and freely licensed video
/// for Videos, with the licence, author and file page kept alongside each hit.
class WikimediaCommonsProvider extends SearchProvider {
  WikimediaCommonsProvider(SiftHttpBase http) : super(http, _source('commons'));

  @override
  Duration get timeout => const Duration(seconds: 15);

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final wantsVideo = request.vertical == SearchVertical.videos;
    final limit = request.resultCount.clamp(10, 30);
    // Image searches often return audio or documents that the MIME filter
    // below drops, so ask for a wider page than the UI needs.
    final pageSize = wantsVideo ? limit : (limit * 2).clamp(10, 50);
    final search =
        wantsVideo ? '${request.query} filetype:video' : request.query;
    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'search',
      'gsrsearch': search,
      'gsrnamespace': '6',
      'gsrlimit': '$pageSize',
      'gsroffset': '${request.page * pageSize}',
      'prop': 'imageinfo',
      'iiprop': 'url|mime|size|extmetadata',
      'iiurlwidth': wantsVideo ? '640' : '720',
      'iiurlheight': wantsVideo ? '360' : '720',
    });

    final data = await http.getJson(uri.toString());
    final query = data['query'];
    if (query is! Map) return const [];
    final pages = query['pages'];
    final items = pages is Map
        ? pages.values
        : pages is List
            ? pages
            : const [];
    final results = <SearchResult>[];
    for (final raw in items.whereType<Map>()) {
      final infoList = raw['imageinfo'];
      if (infoList is! List || infoList.isEmpty) continue;
      final info = infoList.first;
      if (info is! Map) continue;
      final mime = info['mime']?.toString() ?? '';
      final isVideo = mime.startsWith('video/');
      if (wantsVideo != isVideo) continue;
      final page = info['descriptionurl']?.toString() ?? '';
      final title = _commonsTitle(raw['title']?.toString() ?? '');
      if (page.isEmpty || title.isEmpty) continue;

      final extRaw = info['extmetadata'];
      final ext = extRaw is Map ? extRaw : const <String, dynamic>{};
      final license = _extMetadata(ext, 'LicenseShortName');
      final licenseUrl = _extMetadata(ext, 'LicenseUrl');
      final author = _extMetadata(ext, 'Artist');
      final description = stripHtml(_extMetadata(ext, 'ImageDescription'));
      final seconds = info['duration'];
      final duration =
          seconds is num && seconds > 0 ? formatDuration(seconds.round()) : null;
      final width = info['thumbwidth'] ?? info['width'];
      final height = info['thumbheight'] ?? info['height'];
      final thumb = info['thumburl']?.toString();
      final original = info['url']?.toString();
      final poster = thumb != null && thumb.startsWith('http')
          ? thumb
          : original;
      if (poster == null || !poster.startsWith('http')) continue;

      final details = <String>[
        if (author.isNotEmpty) author,
        if (isVideo && duration != null) duration,
        if (description.isNotEmpty) truncateText(description, 120),
        'Wikimedia Commons',
      ];
      results.add(
        SearchResult(
          id: _idFor('commons', page),
          kind: isVideo ? ResultKind.video : ResultKind.image,
          title: title,
          url: page,
          snippet: details.join(' · '),
          sourceId: 'commons',
          sourceName: 'Wikimedia Commons',
          domain: 'commons.wikimedia.org',
          imageUrl: poster,
          thumbnailUrl: poster,
          author: author.isEmpty ? null : author,
          duration: duration,
          meta: {
            'license': license,
            'licenseUrl': licenseUrl,
            'author': author,
            'width': width,
            'height': height,
            'mime': mime,
            'originalUrl': original,
            'pageId': raw['pageid'],
            'attribution': [
              if (author.isNotEmpty) author,
              if (license.isNotEmpty) license,
              'Wikimedia Commons',
            ].join(' · '),
          },
        ),
      );
    }
    return results;
  }

  static String _commonsTitle(String raw) {
    var value = raw.trim();
    if (value.toLowerCase().startsWith('file:')) value = value.substring(5);
    final dot = value.lastIndexOf('.');
    if (dot > 0) value = value.substring(0, dot);
    return value.replaceAll('_', ' ').trim();
  }

  static String _extMetadata(Map meta, String key) {
    final raw = meta[key];
    if (raw is! Map) return '';
    return stripHtml(raw['value']?.toString() ?? '');
  }
}

/* --------------------------------------------------------------------------
 * News
 * ------------------------------------------------------------------------ */

class GoogleNewsProvider extends SearchProvider {
  GoogleNewsProvider(SiftHttpBase http) : super(http, _source('gnews'));

  @override
  bool get supportsPaging => false;

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final uri = Uri.https('news.google.com', '/rss/search', {
      'q': request.query,
      'hl': 'en-US',
      'gl': 'US',
      'ceid': 'US:en',
    });
    final body = await http.getString(
      uri.toString(),
      headers: const {'Accept': 'application/rss+xml, application/xml, text/xml'},
      timeout: const Duration(seconds: 9),
      cacheSeconds: 45,
    );
    final document = XmlDocument.parse(body);
    final items = document.findAllElements('item');
    final results = <SearchResult>[];
    final limit = request.resultCount.clamp(10, 30);

    for (final item in items) {
      if (results.length >= limit) break;
      final sourceElement = _child(item, 'source');
      final publisher = sourceElement?.innerText.trim();
      final sourceUrl = sourceElement?.getAttribute('url');
      final title = _titleWithoutPublisher(
        stripHtml(_childText(item, 'title')),
        publisher,
      );
      final link = _childText(item, 'link');
      if (title.isEmpty || !link.startsWith('http')) continue;
      final rawDescription = stripHtml(_childText(item, 'description'));
      final snippet = rawDescription.length > title.length + 8
          ? truncateText(rawDescription, 240)
          : '';
      final published = _rssDate(_childText(item, 'pubDate'));
      final publisherHost = sourceUrl == null ? '' : domainOf(sourceUrl);
      results.add(
        SearchResult(
          id: _idFor('gnews', link),
          kind: ResultKind.news,
          title: title,
          url: link,
          snippet: snippet,
          sourceId: 'gnews',
          sourceName: 'Google News',
          publishedAt: published,
          domain: publisherHost.isEmpty ? 'news.google.com' : publisherHost,
          thumbnailUrl: _mediaThumbnail(item),
          author: publisher,
          meta: {
            'publisher': publisher,
            'publisherUrl': sourceUrl,
          },
        ),
      );
    }
    return results;
  }
}

/* --------------------------------------------------------------------------
 * Video
 * ------------------------------------------------------------------------ */

class DailymotionProvider extends SearchProvider {
  DailymotionProvider(SiftHttpBase http) : super(http, _source('dailymotion'));

  @override
  Duration get timeout => const Duration(seconds: 8);

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final limit = request.resultCount.clamp(10, 30);
    final uri = Uri.https('api.dailymotion.com', '/videos', {
      'search': request.query,
      'limit': '$limit',
      'page': '${request.page + 1}',
      'fields':
          'id,title,thumbnail_480_url,thumbnail_360_url,url,duration,'
              'owner.screenname,views_total,created_time',
      'family_filter': request.safeSearch ? '1' : '0',
    });
    final data = await http.getJson(uri.toString());
    final items = data['list'];
    if (items is! List) return const [];

    final results = <SearchResult>[];
    for (final raw in items.whereType<Map>()) {
      final id = raw['id']?.toString() ?? '';
      final title = stripHtml(raw['title']?.toString() ?? '');
      final url = raw['url']?.toString() ??
          (id.isEmpty ? '' : 'https://www.dailymotion.com/video/$id');
      if (title.isEmpty || !url.startsWith('http')) continue;
      final owner = raw['owner.screenname']?.toString() ??
          (raw['owner'] is Map
              ? (raw['owner'] as Map)['screenname']?.toString()
              : null);
      final views = raw['views_total'];
      final duration = raw['duration'];
      final created = raw['created_time'];
      final snippetParts = <String>[
        if (owner != null && owner.isNotEmpty) owner,
        if (views is num) '${compactNumber(views)} views',
        if (duration is num) formatDuration(duration.toInt()),
      ];
      results.add(
        SearchResult(
          id: _idFor('dailymotion', url),
          kind: ResultKind.video,
          title: title,
          url: url,
          snippet: snippetParts.join(' · '),
          sourceId: 'dailymotion',
          sourceName: 'Dailymotion',
          domain: 'dailymotion.com',
          thumbnailUrl: raw['thumbnail_480_url']?.toString() ??
              raw['thumbnail_360_url']?.toString(),
          imageUrl: raw['thumbnail_480_url']?.toString(),
          author: owner,
          duration: duration is num ? formatDuration(duration.toInt()) : null,
          publishedAt: created is num
              ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000)
              : null,
          meta: {'views': views, 'videoId': id},
        ),
      );
    }
    return results;
  }
}

/* --------------------------------------------------------------------------
 * Discussion
 * ------------------------------------------------------------------------ */

class HackerNewsProvider extends SearchProvider {
  HackerNewsProvider(SiftHttpBase http) : super(http, _source('hackernews'));

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final limit = request.resultCount.clamp(10, 30);
    final uri = Uri.https('hn.algolia.com', '/api/v1/search', {
      'query': request.query,
      'tags': 'story',
      'hitsPerPage': '$limit',
      'page': '${request.page}',
    });
    final data = await http.getJson(uri.toString());
    final hits = data['hits'];
    if (hits is! List) return const [];
    return _mapHits(hits);
  }

  Future<List<SearchResult>> frontPage({int limit = 15}) async {
    final uri = Uri.https('hn.algolia.com', '/api/v1/search', {
      'tags': 'front_page',
      'hitsPerPage': '$limit',
    });
    final data = await http.getJson(uri.toString(), cacheSeconds: 300);
    final hits = data['hits'];
    if (hits is! List) return const [];
    return _mapHits(hits);
  }

  List<SearchResult> _mapHits(Iterable<dynamic> hits) {
    final results = <SearchResult>[];
    for (final raw in hits.whereType<Map>()) {
      final title = stripHtml(raw['title']?.toString() ?? '');
      if (title.isEmpty) continue;
      final objectId = raw['objectID']?.toString() ?? '';
      final storyUrl = stripHtml(raw['url']?.toString() ?? '');
      final url = storyUrl.startsWith('http')
          ? storyUrl
          : 'https://news.ycombinator.com/item?id=$objectId';
      final points = raw['points'];
      final comments = raw['num_comments'];
      final author = raw['author']?.toString() ?? '';
      final parts = <String>[
        if (points is num) '${points.toInt()} points',
        if (comments is num) '${comments.toInt()} comments',
        if (author.isNotEmpty) 'by $author',
        if (!storyUrl.startsWith('http')) 'text post',
      ];
      results.add(
        SearchResult(
          id: _idFor('hackernews', objectId.isEmpty ? url : objectId),
          kind: ResultKind.discussion,
          title: title,
          url: url,
          snippet: parts.join(' · '),
          sourceId: 'hackernews',
          sourceName: 'Hacker News',
          domain: domainOf(url),
          publishedAt: DateTime.tryParse(raw['created_at']?.toString() ?? ''),
          author: author,
          meta: {
            'points': points,
            'comments': comments,
            'objectId': objectId,
            'discussionUrl': 'https://news.ycombinator.com/item?id=$objectId',
          },
        ),
      );
    }
    return results;
  }
}

class StackExchangeProvider extends SearchProvider {
  StackExchangeProvider(SiftHttpBase http)
      : super(http, _source('stackexchange'));

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final limit = request.resultCount.clamp(10, 30);
    final uri = Uri.https('api.stackexchange.com', '/2.3/search/advanced', {
      'order': 'desc',
      'sort': 'relevance',
      'q': request.query,
      'site': 'stackoverflow',
      'pagesize': '$limit',
      'page': '${request.page + 1}',
      'filter': 'default',
    });
    final data = await http.getJson(uri.toString());
    final items = data['items'];
    if (items is! List) return const [];

    final results = <SearchResult>[];
    for (final raw in items.whereType<Map>()) {
      final title = stripHtml(raw['title']?.toString() ?? '');
      final link = raw['link']?.toString() ?? '';
      if (title.isEmpty || !link.startsWith('http')) continue;
      final tags = raw['tags'];
      final tagList = tags is List
          ? tags.map((tag) => tag.toString()).where((tag) => tag.isNotEmpty)
          : const Iterable<String>.empty();
      final score = raw['score'];
      final answers = raw['answer_count'];
      final answered = raw['is_answered'] == true;
      final parts = <String>[
        if (score is num) '${score.toInt()} votes',
        if (answers is num) '${answers.toInt()} answers',
        if (answered) 'answered',
        if (tagList.isNotEmpty) tagList.take(4).join(', '),
      ];
      final owner = raw['owner'];
      final author = owner is Map ? owner['display_name']?.toString() : null;
      final creation = raw['creation_date'];
      final activity = raw['last_activity_date'];
      results.add(
        SearchResult(
          id: _idFor('stackexchange', link),
          kind: ResultKind.discussion,
          title: title,
          url: link,
          snippet: parts.join(' · '),
          sourceId: 'stackexchange',
          sourceName: 'Stack Exchange',
          domain: 'stackoverflow.com',
          author: author,
          publishedAt: creation is num
              ? DateTime.fromMillisecondsSinceEpoch(creation.toInt() * 1000)
              : null,
          meta: {
            'tags': tagList.toList(),
            'score': score,
            'answers': answers,
            'answered': answered,
            'lastActivity': activity,
            'questionId': raw['question_id'],
          },
        ),
      );
    }
    return results;
  }
}

/* --------------------------------------------------------------------------
 * Optional SearXNG bridge
 * ------------------------------------------------------------------------ */

class SearxProvider extends SearchProvider {
  SearxProvider(SiftHttpBase http, this._baseUrl)
      : super(http, _source('searx'));

  final String Function() _baseUrl;

  @override
  Duration get timeout => const Duration(seconds: 10);

  String _categoryFor(SearchVertical vertical) => switch (vertical) {
        SearchVertical.images => 'images',
        SearchVertical.news => 'news',
        SearchVertical.videos => 'videos',
        _ => 'general',
      };

  ResultKind _kindFor(SearchVertical vertical) => switch (vertical) {
        SearchVertical.images => ResultKind.image,
        SearchVertical.news => ResultKind.news,
        SearchVertical.videos => ResultKind.video,
        _ => ResultKind.web,
      };

  @override
  Future<List<SearchResult>> search(SearchRequest request) async {
    final rawBase = _baseUrl().trim();
    if (rawBase.isEmpty) return const [];
    final normalized = rawBase.startsWith('http') ? rawBase : 'https://$rawBase';
    final base = normalized.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/search').replace(
      queryParameters: {
        'q': request.query,
        'format': 'json',
        'pageno': '${request.page + 1}',
        'language': request.language,
        'safesearch': request.safeSearch ? '1' : '0',
        'categories': _categoryFor(request.vertical),
      },
    );
    final data = await http.getJson(
      uri.toString(),
      headers: const {'Accept': 'application/json'},
      timeout: const Duration(seconds: 10),
    );
    final items = data['results'];
    if (items is! List) return const [];

    final results = <SearchResult>[];
    for (final raw in items.whereType<Map>()) {
      final url = raw['url']?.toString() ?? '';
      final title = stripHtml(raw['title']?.toString() ?? '');
      if (!url.startsWith('http') || title.isEmpty) continue;
      final kind = _kindFor(request.vertical);
      final published = raw['publishedDate']?.toString();
      final thumbnail = raw['thumbnail_src']?.toString() ??
          raw['thumbnail']?.toString() ??
          raw['img_src']?.toString();
      final image = raw['img_src']?.toString() ??
          (kind == ResultKind.image ? thumbnail : null);
      results.add(
        SearchResult(
          id: _idFor('searx', url),
          kind: kind,
          title: title,
          url: url,
          snippet: stripHtml(raw['content']?.toString() ?? ''),
          sourceId: 'searx',
          sourceName: raw['engine']?.toString().isNotEmpty == true
              ? 'SearXNG · ${raw['engine']}'
              : 'SearXNG',
          domain: domainOf(url),
          imageUrl: image,
          thumbnailUrl: thumbnail,
          author: raw['author']?.toString(),
          duration: raw['length']?.toString(),
          publishedAt: published == null ? null : DateTime.tryParse(published),
          meta: {
            'engine': raw['engine'],
            'category': _categoryFor(request.vertical),
          },
        ),
      );
    }
    return results;
  }
}

/// Public helper for callers that want a JSON array from an endpoint whose
/// top-level shape is not an object (suggestions, dictionaries).
Future<dynamic> decodeJsonArray(SiftHttpBase http, String url,
    {int cacheSeconds = 0}) async {
  final body = await http.getString(url, cacheSeconds: cacheSeconds);
  return jsonDecode(body);
}
