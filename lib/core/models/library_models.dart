import 'package:flutter/foundation.dart';

@immutable
class SavedPage {
  const SavedPage({
    required this.id,
    required this.title,
    required this.url,
    required this.snippet,
    required this.source,
    required this.savedAt,
    this.read = false,
    this.note,
  });

  final String id;
  final String title;
  final String url;
  final String snippet;
  final String source;
  final DateTime savedAt;
  final bool read;
  final String? note;

  SavedPage copyWith({bool? read, String? note}) => SavedPage(
        id: id,
        title: title,
        url: url,
        snippet: snippet,
        source: source,
        savedAt: savedAt,
        read: read ?? this.read,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'snippet': snippet,
        'source': source,
        'savedAt': savedAt.toIso8601String(),
        'read': read,
        'note': note,
      };

  factory SavedPage.fromJson(Map<String, dynamic> json) => SavedPage(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled',
        url: json['url'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        source: json['source'] as String? ?? '',
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
        read: json['read'] as bool? ?? false,
        note: json['note'] as String?,
      );
}

@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.url,
  });

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;
  final String? url;

  Note copyWith({String? title, String? body, DateTime? updatedAt, String? url}) =>
      Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
        url: url ?? this.url,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updatedAt': updatedAt.toIso8601String(),
        'url': url,
      };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
        url: json['url'] as String?,
      );
}

@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.query,
    required this.at,
    this.openedUrl,
    this.title,
  });

  final String id;
  final String query;
  final DateTime at;
  final String? openedUrl;
  final String? title;

  Map<String, dynamic> toJson() => {
        'id': id,
        'query': query,
        'at': at.toIso8601String(),
        'openedUrl': openedUrl,
        'title': title,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String? ?? '',
        query: json['query'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        openedUrl: json['openedUrl'] as String?,
        title: json['title'] as String?,
      );
}

@immutable
class IndexedDocument {
  const IndexedDocument({
    required this.id,
    required this.title,
    required this.url,
    required this.source,
    required this.body,
    required this.addedAt,
    this.topics = const [],
    this.isStarter = false,
  });

  final String id;
  final String title;
  final String url;
  final String source;
  final String body;
  final DateTime addedAt;
  final List<String> topics;
  final bool isStarter;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'source': source,
        'body': body,
        'addedAt': addedAt.toIso8601String(),
        'topics': topics,
        'isStarter': isStarter,
      };

  factory IndexedDocument.fromJson(Map<String, dynamic> json) => IndexedDocument(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        source: json['source'] as String? ?? '',
        body: json['body'] as String? ?? '',
        addedAt:
            DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
        topics: (json['topics'] as List?)?.cast<String>() ?? const [],
        isStarter: json['isStarter'] as bool? ?? false,
      );
}

@immutable
class LocalHit {
  const LocalHit({
    required this.document,
    required this.score,
    required this.matchedTerms,
    required this.snippet,
  });

  final IndexedDocument document;
  final double score;
  final List<String> matchedTerms;
  final String snippet;

  String get strength {
    if (score >= 12) return 'strong match';
    if (score >= 6) return 'good match';
    return 'related';
  }
}

@immutable
class LocalSearchResult {
  const LocalSearchResult({
    required this.query,
    required this.hits,
    required this.elapsedMs,
    this.correctedTerm,
  });

  final String query;
  final List<LocalHit> hits;
  final int elapsedMs;
  final String? correctedTerm;
}
