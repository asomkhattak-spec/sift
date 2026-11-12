import '../models/search_models.dart';

const Set<String> kStopWords = {
  'a', 'an', 'and', 'are', 'as', 'at', 'be', 'but', 'by', 'for', 'from',
  'has', 'have', 'he', 'her', 'his', 'how', 'i', 'if', 'in', 'into', 'is',
  'it', 'its', 'me', 'my', 'no', 'not', 'of', 'on', 'or', 'our', 'so',
  'that', 'the', 'their', 'them', 'then', 'there', 'these', 'they', 'this',
  'to', 'was', 'we', 'were', 'what', 'when', 'where', 'which', 'who', 'why',
  'will', 'with', 'you', 'your', 'about', 'can', 'do', 'does', 'just',
};

const Map<String, List<String>> kQuerySynonyms = {
  'privacy': ['private', 'anonymity', 'untracked'],
  'private': ['privacy', 'incognito'],
  'anonymous': ['privacy', 'untracked', 'identity'],
  'password': ['passphrase', 'credential', 'login'],
  'passwords': ['password', 'passphrase', 'credential'],
  'security': ['secure', 'protection', 'safety'],
  'encryption': ['encrypted', 'cipher', 'cryptography'],
  'browser': ['web', 'webpage', 'site'],
  'tracker': ['tracking', 'analytics', 'advertising'],
  'trackers': ['tracking', 'analytics', 'advertising'],
  'phone': ['mobile', 'android', 'smartphone'],
  'climate': ['warming', 'carbon', 'weather'],
  'money': ['finance', 'savings', 'investing'],
  'investing': ['index', 'fund', 'compound'],
  'backup': ['backups', 'restore', 'recovery'],
  'health': ['wellness', 'medical', 'sleep'],
  'sleep': ['rest', 'circadian', 'health'],
  'space': ['astronomy', 'planet', 'nasa'],
  'code': ['programming', 'software', 'developer'],
  'search': ['find', 'query', 'discover'],
  'weather': ['forecast', 'temperature', 'rain'],
  'currency': ['exchange', 'rate', 'dollar'],
  'define': ['meaning', 'definition', 'dictionary'],
  'math': ['calculate', 'calculator', 'equation'],
};

final RegExp _tokenPattern = RegExp(r'[a-z0-9]+', caseSensitive: false);

List<String> rawTokens(String input) {
  return _tokenPattern
      .allMatches(input.toLowerCase())
      .map((match) => match.group(0)!)
      .where((token) => token.length > 1)
      .toList();
}

String stem(String token) {
  var word = token;
  if (word.length <= 3) return word;
  if (word.endsWith('ies') && word.length > 4) {
    word = '${word.substring(0, word.length - 3)}y';
  } else if (word.endsWith('sses')) {
    word = word.substring(0, word.length - 2);
  } else if (word.endsWith('ing') && word.length > 5) {
    word = word.substring(0, word.length - 3);
  } else if (word.endsWith('ed') && word.length > 4) {
    word = word.substring(0, word.length - 2);
  } else if (word.endsWith('ly') && word.length > 5) {
    word = word.substring(0, word.length - 2);
  } else if (word.endsWith('es') && word.length > 4) {
    word = word.substring(0, word.length - 2);
  } else if (word.endsWith('s') &&
      !word.endsWith('ss') &&
      !word.endsWith('us') &&
      !word.endsWith('is')) {
    word = word.substring(0, word.length - 1);
  }
  return word;
}

List<String> queryTerms(String query) {
  final seen = <String>{};
  final out = <String>[];
  for (final token in rawTokens(query)) {
    if (kStopWords.contains(token)) continue;
    final normalized = stem(token);
    if (normalized.length < 2) continue;
    if (seen.add(normalized)) out.add(normalized);
  }
  return out;
}

List<String> expandedTerms(String query) {
  final base = queryTerms(query);
  final seen = base.toSet();
  final out = [...base];
  for (final term in base) {
    for (final synonym in kQuerySynonyms[term] ?? const <String>[]) {
      final normalized = stem(synonym);
      if (normalized.length > 1 && seen.add(normalized)) out.add(normalized);
    }
  }
  return out;
}

String _normalizedText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double coverage(List<String> terms, Set<String> present) {
  if (terms.isEmpty) return 0;
  final hits = terms.where(present.contains).length;
  return hits / terms.length;
}

double _sourceWeight(String sourceId) {
  return switch (sourceId) {
    'wikipedia' => 5.0,
    'hackernews' => 3.0,
    'bing' => 2.0,
    'stackexchange' => 1.8,
    'gnews' => 1.4,
    'searx' => 1.2,
    'openverse' => 0.4,
    'dailymotion' => 0.6,
    _ => 0.8,
  };
}

double scoreResult(SearchResult result, String query) {
  final terms = queryTerms(query);
  final normalizedQuery = _normalizedText(query);
  final title = _normalizedText(result.title);
  final snippet = _normalizedText(result.snippet);
  final titleTokens = title.split(' ').map(stem).toSet();
  final snippetTokens = snippet.split(' ').map(stem).toSet();

  var score = 0.0;
  if (normalizedQuery.isNotEmpty && title.contains(normalizedQuery)) {
    score += 34;
  }
  score += coverage(terms, titleTokens) * 18;
  score += coverage(terms, snippetTokens) * 8;
  score += coverage(terms, {...titleTokens, ...snippetTokens}) * 6;
  score += _sourceWeight(result.sourceId);

  if (result.kind == ResultKind.news && result.publishedAt != null) {
    final age = DateTime.now().difference(result.publishedAt!);
    if (!age.isNegative) {
      if (age.inHours <= 2) {
        score += 4;
      } else if (age.inHours <= 24) {
        score += 2;
      } else if (age.inDays <= 4) {
        score += 0.8;
      }
    }
  }

  if (result.title.length < 12) score -= 1.5;
  if (result.snippet.isEmpty) score -= 1.2;
  if (result.url.isEmpty) score -= 50;

  return score;
}

String resultDedupeKey(SearchResult result) {
  final uri = Uri.tryParse(result.url);
  if (uri != null && uri.host.isNotEmpty) {
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return '${uri.host.replaceFirst('www.', '').toLowerCase()}$path';
  }
  return _normalizedText(result.title);
}

List<SearchResult> rankAndDedupe(
  List<SearchResult> input,
  String query, {
  bool diversify = true,
  int maxPerHost = 2,
}) {
  final seenUrls = <String>{};
  final seenTitles = <String>{};
  final scored = <SearchResult>[];
  for (final result in input) {
    if (result.url.isEmpty || result.title.trim().isEmpty) continue;
    final uri = Uri.tryParse(result.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) continue;
    final urlKey = resultDedupeKey(result);
    final titleKey = _normalizedText(result.title).split(' ').take(9).join(' ');
    if (!seenUrls.add(urlKey)) continue;
    if (titleKey.length > 12 && !seenTitles.add(titleKey)) continue;
    scored.add(result.copyWith(score: scoreResult(result, query)));
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  if (!diversify) return scored;

  final counts = <String, int>{};
  final firstPass = <SearchResult>[];
  final deferred = <SearchResult>[];
  for (final result in scored) {
    final host = result.host.toLowerCase();
    final count = counts[host] ?? 0;
    if (count < maxPerHost) {
      counts[host] = count + 1;
      firstPass.add(result);
    } else {
      deferred.add(result);
    }
  }
  return [...firstPass, ...deferred];
}

/// Returns a readable excerpt positioned around a matching query term.
String excerptAround(String text, String query, {int maxChars = 190}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= maxChars) return clean;
  final terms = queryTerms(query);
  final lower = clean.toLowerCase();
  var index = -1;
  for (final term in terms) {
    final found = lower.indexOf(term);
    if (found != -1 && (index == -1 || found < index)) index = found;
  }
  if (index == -1) {
    return '${clean.substring(0, maxChars).trimRight()}…';
  }
  final start = (index - 48).clamp(0, clean.length).toInt();
  var end = (start + maxChars).clamp(0, clean.length).toInt();
  if (end < clean.length) {
    final lastSpace = clean.lastIndexOf(' ', end);
    if (lastSpace > start + 80) end = lastSpace;
  }
  final prefix = start > 0 ? '…' : '';
  final suffix = end < clean.length ? '…' : '';
  return '$prefix${clean.substring(start, end).trim()}$suffix';
}
