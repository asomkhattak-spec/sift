import 'dart:convert';

import '../models/search_models.dart';
import '../services/http_service.dart';

/// Query completion. History stays in front, then lightweight public
/// autocomplete; failure is silent because typing should never wait on it.
class SuggestionEngine {
  SuggestionEngine(this._http);

  final SiftHttpBase _http;

  Future<List<QuerySuggestion>> suggest(
    String raw, {
    List<QuerySuggestion> local = const [],
    int limit = 8,
  }) async {
    final query = raw.trim();
    final merged = <QuerySuggestion>[];
    final seen = <String>{};
    for (final suggestion in local) {
      final key = suggestion.text.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      merged.add(suggestion);
      if (merged.length >= limit) return merged;
    }
    if (query.length < 2) return merged;

    try {
      final uri = Uri.https('api.bing.com', '/osjson.aspx', {'query': query});
      final body = await _http.getString(
        uri.toString(),
        headers: const {'Accept': 'application/json'},
        timeout: const Duration(milliseconds: 1200),
        cacheSeconds: 180,
      );
      final decoded = jsonDecode(body);
      if (decoded is List && decoded.length >= 2 && decoded[1] is List) {
        for (final item in (decoded[1] as List).whereType<String>()) {
          final text = item.trim();
          if (text.isEmpty || text.length > 120) continue;
          final key = text.toLowerCase();
          if (!seen.add(key)) continue;
          merged.add(QuerySuggestion(text: text));
          if (merged.length >= limit) break;
        }
      }
    } catch (_) {
      // Suggestions are an enhancement, never a prerequisite for search.
    }
    return merged;
  }
}
