import '../models/search_models.dart';

/// Every network source Sift can speak to. Each entry is deliberately
/// explicit about what leaves the phone, because the source panel is part of
/// the product rather than a buried legal page.
const List<SourceDefinition> kSourceCatalog = [
  SourceDefinition(
    id: 'bing',
    name: 'Bing Web',
    shortName: 'Bing',
    description:
        'Broad web results from Bing, requested as an RSS feed so the app '
        'reads structured titles and summaries instead of a script-heavy page.',
    homepage: 'https://www.bing.com',
    host: 'www.bing.com',
    privacyNote:
        'Your query is sent to Microsoft. Sift strips campaign parameters from '
        'opened links and does not attach an account or device identifier.',
    verticals: {SearchVertical.all, SearchVertical.web},
  ),
  SourceDefinition(
    id: 'wikipedia',
    name: 'Wikipedia',
    shortName: 'Wikipedia',
    description:
        'Encyclopedic pages and lead summaries from the free encyclopedia. '
        'A useful counterweight to ranking-driven web results.',
    homepage: 'https://en.wikipedia.org',
    host: 'en.wikipedia.org',
    privacyNote:
        'The Wikimedia Foundation receives your query. No account is used and '
        'page images load from Wikimedia.',
    verticals: {SearchVertical.all, SearchVertical.web},
  ),
  SourceDefinition(
    id: 'gnews',
    name: 'Google News',
    shortName: 'News',
    description:
        'Recent headlines from the Google News RSS index, with the publisher '
        'shown instead of the redirect host.',
    homepage: 'https://news.google.com',
    host: 'news.google.com',
    privacyNote:
        'Your query is sent to Google News. Article links point at the '
        'publisher, which then sees your visit directly.',
    verticals: {SearchVertical.news},
  ),
  SourceDefinition(
    id: 'openverse',
    name: 'Openverse',
    shortName: 'Images',
    description:
        'A search index of openly licensed images from Flickr, Wikimedia, '
        'museums and other collections.',
    homepage: 'https://openverse.org',
    host: 'api.openverse.org',
    privacyNote:
        'Openverse receives your query. Full-size images are loaded from the '
        'original image host when you open them.',
    verticals: {SearchVertical.images},
  ),
  SourceDefinition(
    id: 'commons',
    name: 'Wikimedia Commons',
    shortName: 'Commons',
    description:
        'Freely licensed photographs, diagrams and video from Wikimedia '
        'Commons. Every result carries its author and licence so attribution '
        'is one tap away.',
    homepage: 'https://commons.wikimedia.org',
    host: 'commons.wikimedia.org',
    privacyNote:
        'The Wikimedia Foundation receives your query. Media files and their '
        'pages are loaded from Wikimedia when you preview or open them.',
    verticals: {SearchVertical.images, SearchVertical.videos},
  ),
  SourceDefinition(
    id: 'dailymotion',
    name: 'Dailymotion',
    shortName: 'Video',
    description:
        'Public video results with duration and creator attribution. Video '
        'playback happens on Dailymotion.',
    homepage: 'https://www.dailymotion.com',
    host: 'api.dailymotion.com',
    privacyNote:
        'Dailymotion receives your query. Choosing a video opens its page, '
        'where Dailymotion applies its own cookies and player policy.',
    verticals: {SearchVertical.videos},
  ),
  SourceDefinition(
    id: 'hackernews',
    name: 'Hacker News',
    shortName: 'HN',
    description:
        'Stories and discussions from the Hacker News community, searched '
        'through Algolia’s public index.',
    homepage: 'https://news.ycombinator.com',
    host: 'hn.algolia.com',
    privacyNote:
        'Algolia receives your query on behalf of the public Hacker News '
        'index. Sift sends no user identifier.',
    verticals: {SearchVertical.discuss},
  ),
  SourceDefinition(
    id: 'stackexchange',
    name: 'Stack Exchange',
    shortName: 'Stack',
    description:
        'Questions from Stack Overflow, ranked by relevance and annotated with '
        'score, answers and tags so you can judge an answer before opening it.',
    homepage: 'https://stackoverflow.com',
    host: 'api.stackexchange.com',
    privacyNote:
        'Stack Exchange receives your query through its public API. Sift adds '
        'no key and no account.',
    verticals: {SearchVertical.discuss},
  ),
  SourceDefinition(
    id: 'searx',
    name: 'SearXNG',
    shortName: 'SearXNG',
    description:
        'Connect a SearXNG instance you trust for an additional independent '
        'meta-search source. Sift does not ship or silently choose a public '
        'instance.',
    homepage: 'https://docs.searxng.org',
    host: 'your instance',
    privacyNote:
        'Your instance operator can see your queries and upstream sources. '
        'Only add an instance you control or trust.',
    defaultEnabled: false,
    isCustom: true,
    verticals: {
      SearchVertical.all,
      SearchVertical.web,
      SearchVertical.images,
      SearchVertical.news,
      SearchVertical.videos,
    },
  ),
];

SourceDefinition? sourceById(String id) {
  for (final source in kSourceCatalog) {
    if (source.id == id) return source;
  }
  return null;
}
