import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

const Set<String> kTrackingParams = {
  'gclid',
  'dclid',
  'fbclid',
  'msclkid',
  'yclid',
  'twclid',
  'igshid',
  'mc_cid',
  'mc_eid',
  'mkt_tok',
  'vero_id',
  'oly_anon_id',
  'oly_enc_id',
  'rb_clickid',
  's_cid',
  'wickedid',
  'ref_src',
  'ref_url',
  'spm',
};

String normalizeWhitespace(String input) {
  return input.replaceAll(RegExp(r'[\s\u00A0]+'), ' ').trim();
}

/// Converts a fragment of markup to readable plain text.
String stripHtml(String input) {
  if (input.isEmpty) return '';
  if (!input.contains('<') && !input.contains('&')) {
    return normalizeWhitespace(input);
  }
  try {
    final fragment = html_parser.parseFragment(input);
    return normalizeWhitespace(fragment.text ?? '');
  } catch (_) {
    return normalizeWhitespace(input.replaceAll(RegExp(r'<[^>]*>'), ' '));
  }
}

String decodeEntities(String input) {
  if (!input.contains('&')) return input;
  try {
    return html_parser.parseFragment(input).text ?? input;
  } catch (_) {
    return input;
  }
}

String truncateText(String input, int maxChars) {
  final clean = normalizeWhitespace(input);
  if (clean.length <= maxChars) return clean;
  final cut = clean.substring(0, maxChars);
  final lastSpace = cut.lastIndexOf(' ');
  final base = lastSpace > maxChars * 0.6 ? cut.substring(0, lastSpace) : cut;
  return '$base…';
}

String normalizeQuery(String raw) {
  var query = normalizeWhitespace(raw);
  // Smart punctuation from keyboard substitution is common; search APIs prefer
  // the plain characters.
  query = query
      .replaceAll('\u2018', "'")
      .replaceAll('\u2019', "'")
      .replaceAll('\u201C', '"')
      .replaceAll('\u201D', '"')
      .replaceAll('\u2013', '-')
      .replaceAll('\u2014', '-');
  return query;
}

bool isProbablyUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.contains(' ')) return false;
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return uri.host.isNotEmpty;
  }
  if (value.startsWith('localhost')) return true;
  if (!value.contains('.')) return false;
  final candidate = Uri.tryParse('https://$value');
  if (candidate == null || candidate.host.isEmpty) return false;
  return candidate.host.contains('.') &&
      !candidate.host.startsWith('.') &&
      !candidate.host.endsWith('.');
}

String? navigableUrl(String raw) {
  if (!isProbablyUrl(raw)) return null;
  final value = raw.trim();
  final parsed = Uri.tryParse(value);
  if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https')) {
    return parsed.toString();
  }
  return 'https://$value';
}

String domainOf(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return '';
  return parsed.host.replaceFirst('www.', '');
}

/// Removes common campaign parameters without otherwise touching the URL.
/// Returns the original string when nothing matched or parsing failed.
String stripTrackingParams(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasQuery) return url;
  final filtered = <String, dynamic>{};
  var changed = false;
  uri.queryParametersAll.forEach((key, values) {
    final lower = key.toLowerCase();
    if (kTrackingParams.contains(lower) || lower.startsWith('utm_')) {
      changed = true;
      return;
    }
    filtered[key] = values;
  });
  if (!changed) return url;
  try {
    return uri.replace(queryParameters: filtered).toString();
  } catch (_) {
    return url;
  }
}

String buildBingWebUrl(String query) {
  return 'https://www.bing.com/search?q=${Uri.encodeQueryComponent(query)}';
}

String buildExternalSearchUrl(String query) {
  return buildBingWebUrl(query);
}

String idFor(String prefix, String value) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_fnv1a(value)}';
}

int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(value)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

int stableHash(String value) => _fnv1a(value);

Map<String, dynamic>? tryDecodeObject(String source) {
  try {
    final value = jsonDecode(source);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
  return null;
}

String compactHostTitle(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null) return url;
  final host = parsed.host.replaceFirst('www.', '');
  if (host.isEmpty) return url;
  const known = {
    'en.wikipedia.org': 'Wikipedia',
    'news.ycombinator.com': 'Hacker News',
    'stackoverflow.com': 'Stack Overflow',
    'openverse.org': 'Openverse',
    'dailymotion.com': 'Dailymotion',
    'www.dailymotion.com': 'Dailymotion',
    'news.google.com': 'Google News',
    'www.bing.com': 'Bing',
    'bing.com': 'Bing',
  };
  return known[parsed.host] ??
      host.split('.').first[0].toUpperCase() + host.split('.').first.substring(1);
}
