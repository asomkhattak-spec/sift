import 'package:flutter/foundation.dart';

/// A tiny in-process handoff for searches started outside the Search tab:
/// Android intents, the browser start page, and Discover shortcuts.
class SearchBus extends ChangeNotifier {
  String? _pending;
  int _revision = 0;

  int get revision => _revision;

  void submit(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;
    _pending = clean;
    _revision += 1;
    notifyListeners();
  }

  String? takePending() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
