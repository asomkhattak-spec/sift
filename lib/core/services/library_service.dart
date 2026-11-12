import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library_models.dart';
import '../models/search_models.dart';
import '../utils/text_utils.dart';
import 'settings_service.dart';

class LibraryService extends ChangeNotifier {
  LibraryService(this._prefs, this._settings) {
    _saved = _readList(_kSaved, SavedPage.fromJson);
    _notes = _readList(_kNotes, Note.fromJson);
    _history = _readList(_kHistory, HistoryEntry.fromJson);
    _saved.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _history.sort((a, b) => b.at.compareTo(a.at));
  }

  final SharedPreferences _prefs;
  final SettingsService _settings;

  static const _kSaved = 'sift.library.saved';
  static const _kNotes = 'sift.library.notes';
  static const _kHistory = 'sift.library.history';
  static const int _maxEntries = 400;

  late List<SavedPage> _saved;
  late List<Note> _notes;
  late List<HistoryEntry> _history;

  List<SavedPage> get saved => List.unmodifiable(_saved);
  List<Note> get notes => List.unmodifiable(_notes);
  List<HistoryEntry> get history => List.unmodifiable(_history);

  List<T> _readList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      return decoded
          .whereType<Map>()
          .map((item) => fromJson(item.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return <T>[];
    }
  }

  Future<void> _writeSaved() async {
    await _prefs.setString(
      _kSaved,
      jsonEncode(_saved.map((page) => page.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> _writeNotes() async {
    await _prefs.setString(
      _kNotes,
      jsonEncode(_notes.map((note) => note.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> _writeHistory() async {
    await _prefs.setString(
      _kHistory,
      jsonEncode(_history.map((entry) => entry.toJson()).toList()),
    );
    notifyListeners();
  }

  bool isSaved(String url) {
    final normalized = _normalizedUrl(url);
    return _saved.any((page) => _normalizedUrl(page.url) == normalized);
  }

  SavedPage? savedFor(String url) {
    final normalized = _normalizedUrl(url);
    for (final page in _saved) {
      if (_normalizedUrl(page.url) == normalized) return page;
    }
    return null;
  }

  Future<SavedPage> saveResult(SearchResult result) async {
    final existing = savedFor(result.url);
    if (existing != null) return existing;
    final page = SavedPage(
      id: idFor('save', result.url),
      title: result.title.isEmpty ? result.host : result.title,
      url: result.url,
      snippet: result.snippet,
      source: result.sourceName,
      savedAt: DateTime.now(),
    );
    _saved.insert(0, page);
    if (_saved.length > _maxEntries) _saved.removeLast();
    await _writeSaved();
    return page;
  }

  Future<SavedPage> saveUrl({
    required String url,
    required String title,
    String snippet = '',
    String source = 'Web',
  }) async {
    final existing = savedFor(url);
    if (existing != null) return existing;
    final page = SavedPage(
      id: idFor('save', url),
      title: title.isEmpty ? domainOf(url) : title,
      url: url,
      snippet: snippet,
      source: source,
      savedAt: DateTime.now(),
    );
    _saved.insert(0, page);
    await _writeSaved();
    return page;
  }

  Future<void> deleteSaved(String id) async {
    _saved.removeWhere((page) => page.id == id);
    await _writeSaved();
  }

  Future<void> markSavedRead(String id, {bool read = true}) async {
    final index = _saved.indexWhere((page) => page.id == id);
    if (index == -1) return;
    _saved[index] = _saved[index].copyWith(read: read);
    await _writeSaved();
  }

  Future<void> setSavedNote(String id, String note) async {
    final index = _saved.indexWhere((page) => page.id == id);
    if (index == -1) return;
    _saved[index] = _saved[index].copyWith(note: note.trim());
    await _writeSaved();
  }

  Future<Note> addNote({
    String title = '',
    String body = '',
    String? url,
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: idFor('note', now.toIso8601String()),
      title: title.trim().isEmpty ? 'Untitled note' : title.trim(),
      body: body,
      updatedAt: now,
      url: url,
    );
    _notes.insert(0, note);
    await _writeNotes();
    return note;
  }

  Future<void> updateNote(Note note) async {
    final index = _notes.indexWhere((item) => item.id == note.id);
    if (index == -1) return;
    _notes[index] = note.copyWith(updatedAt: DateTime.now());
    _notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _writeNotes();
  }

  Future<void> deleteNote(String id) async {
    _notes.removeWhere((note) => note.id == id);
    await _writeNotes();
  }

  /// Records activity only when the user explicitly opted in and is not in a
  /// private session. Callers do not need to repeat the privacy check.
  Future<void> recordQuery(String query, {String? openedUrl, String? title}) async {
    if (!_settings.rememberActivity || _settings.privateBrowsing) return;
    final clean = query.trim();
    if (clean.isEmpty) return;
    final now = DateTime.now();
    if (_history.isNotEmpty && _history.first.query == clean &&
        now.difference(_history.first.at).inSeconds < 45) {
      return;
    }
    _history.insert(
      0,
      HistoryEntry(
        id: idFor('history', clean),
        query: clean,
        at: now,
        openedUrl: openedUrl,
        title: title,
      ),
    );
    if (_history.length > _maxEntries) _history.removeLast();
    await _writeHistory();
  }

  Future<void> recordVisit({
    required String url,
    required String title,
  }) async {
    if (!_settings.rememberActivity || _settings.privateBrowsing) return;
    if (url.isEmpty || url.startsWith('about:')) return;
    final now = DateTime.now();
    if (_history.isNotEmpty &&
        _history.first.openedUrl == url &&
        now.difference(_history.first.at).inMinutes < 2) {
      return;
    }
    _history.insert(
      0,
      HistoryEntry(
        id: idFor('visit', url),
        query: title.isEmpty ? domainOf(url) : title,
        at: now,
        openedUrl: url,
        title: title,
      ),
    );
    if (_history.length > _maxEntries) _history.removeLast();
    await _writeHistory();
  }

  List<HistoryEntry> recentQueries({int limit = 5}) {
    final seen = <String>{};
    final out = <HistoryEntry>[];
    for (final entry in _history) {
      if (entry.openedUrl != null) continue;
      if (!seen.add(entry.query.toLowerCase())) continue;
      out.add(entry);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<QuerySuggestion> querySuggestions({int limit = 4}) {
    return recentQueries(limit: limit)
        .map((entry) => QuerySuggestion(
              text: entry.query,
              kind: SuggestionKind.history,
            ))
        .toList();
  }

  Future<void> removeHistoryEntry(String id) async {
    _history.removeWhere((entry) => entry.id == id);
    await _writeHistory();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _prefs.remove(_kHistory);
    notifyListeners();
  }

  Future<void> clearSaved() async {
    _saved.clear();
    await _prefs.remove(_kSaved);
    notifyListeners();
  }

  Future<void> clearNotes() async {
    _notes.clear();
    await _prefs.remove(_kNotes);
    notifyListeners();
  }

  String _normalizedUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return url.trim().toLowerCase();
    return uri
        .replace(fragment: '')
        .toString()
        .replaceFirst(RegExp(r'/+$'), '')
        .toLowerCase();
  }
}
