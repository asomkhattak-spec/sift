import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/search_models.dart';
import '../../core/search/local_index.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/navigation.dart';
import '../../core/utils/text_utils.dart';
import '../../widgets/result_widgets.dart';
import '../../widgets/search_bar.dart';
import '../../widgets/sift_ui.dart';

enum _Scope { all, custom, starter }

class MySearchScreen extends StatefulWidget {
  const MySearchScreen({super.key, this.showBack = false});

  /// When pushed as its own route, show a way back. The tab instance leaves
  /// this false and relies on the root navigation bar.
  final bool showBack;

  @override
  State<MySearchScreen> createState() => MySearchScreenState();
}

class MySearchScreenState extends State<MySearchScreen> {
  late final SiftServices _services;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  _Scope _scope = _Scope.all;
  List<SearchResult> _results = const [];
  String _query = '';
  String? _error;
  bool _searching = false;
  bool _indexing = false;
  int _token = 0;
  Timer? _debounce;

  LocalIndex get _index => _services.localIndex;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _index.addListener(_onIndexChanged);
    _controller.addListener(_onChanged);
    _ensureLoaded();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _index.removeListener(_onIndexChanged);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onIndexChanged() {
    if (!mounted) return;
    setState(() {});
    if (_query.isNotEmpty) unawaited(_runSearch(_query));
  }

  Future<void> _ensureLoaded() async {
    if (_index.isLoaded || _index.isLoading) return;
    await _index.load();
  }

  void _onChanged() {
    final text = _controller.text.trim();
    if (text == _query) return;
    _debounce?.cancel();
    if (text.isEmpty) {
      _query = '';
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(text));
    });
  }

  Future<void> _runSearch(String raw) async {
    final query = normalizeQuery(raw);
    if (query.isEmpty) return;
    final token = ++_token;
    setState(() {
      _query = query;
      _searching = true;
      _error = null;
    });
    try {
      final results = await _index.search(
        query,
        limit: 40,
        includeStarter:
            _scope != _Scope.custom && _services.settings.starterIndexEnabled,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _results = switch (_scope) {
          _Scope.all => results,
          _Scope.custom => results
              .where((result) => result.meta['isCustom'] == true)
              .toList(),
          _Scope.starter => _services.settings.starterIndexEnabled
              ? results.where((result) => result.meta['isCustom'] != true).toList()
              : const <SearchResult>[],
        };
        _searching = false;
      });
    } catch (error) {
      if (!mounted || token != _token) return;
      setState(() {
        _error = error.toString();
        _searching = false;
      });
    }
  }

  void _selectScope(_Scope scope) {
    setState(() => _scope = scope);
    if (_query.isNotEmpty) unawaited(_runSearch(_query));
  }

  void focusSearch() {
    _focus.requestFocus();
  }

  Future<void> _open(SearchResult result) async {
    await _services.library.recordQuery(result.title, openedUrl: result.url);
    if (!mounted) return;
    await openSiftUrl(context, result.url, title: result.title);
  }

  Future<void> _addPage() async {
    final controller = TextEditingController();
    final url = await showSiftSheet<String>(
      context,
      builder: (sheetContext) => _IndexPageSheet(controller: controller),
    );
    controller.dispose();
    if (url == null || url.trim().isEmpty || !mounted) return;
    setState(() => _indexing = true);
    try {
      final document = await _index.indexUrl(url);
      if (!mounted) return;
      showSiftToast(
        context,
        '“${truncateText(document.title, 48)}” is in My Search.',
      );
      if (_query.isNotEmpty) await _runSearch(_query);
    } on LocalIndexException catch (error) {
      if (mounted) {
        showSiftToast(context, error.message, error: true);
      }
    } catch (error) {
      if (mounted) {
        showSiftToast(context, 'Could not index that page: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _indexing = false);
    }
  }

  Future<void> _addNote() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final saved = await showSiftSheet<bool>(
      context,
      builder: (sheetContext) => _NewNoteSheet(title: title, body: body),
    );
    if (saved == true && mounted) {
      final text = '${title.text.trim()}\n\n${body.text.trim()}';
      await _services.library.addNote(
        title: title.text.trim().isEmpty ? 'Untitled note' : title.text.trim(),
        body: body.text.trim(),
        url: null,
      );
      try {
        await _index.indexText(
          url: 'https://sift.local/note/${DateTime.now().millisecondsSinceEpoch}',
          title: title.text.trim().isEmpty ? 'Untitled note' : title.text.trim(),
          text: text,
        );
      } catch (_) {
        // Notes still live in the library; indexing is a convenience.
      }
      if (mounted) showSiftToast(context, 'Note saved to Library.');
    }
    title.dispose();
    body.dispose();
  }

  Future<void> _remove(LocalDocument document) async {
    final confirmed = await showSiftSheet<bool>(
      context,
      builder: (sheetContext) => _ConfirmSheet(
        title: 'Remove from index?',
        body:
            '“${document.title}” will leave My Search. The page itself is not touched.',
        action: 'Remove page',
      ),
    );
    if (confirmed == true) await _index.removeDocument(document.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final custom = _index.customDocuments;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SiftSpace.page,
            20,
            SiftSpace.page,
            36,
          ),
          children: [
            if (widget.showBack)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SiftIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back to settings',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            SiftPageTitle(
              kicker: 'A SEARCH ENGINE OF YOUR OWN',
              title: 'My Search',
              subtitle:
                  'Sift keeps a private full-text index on this phone. Add pages '
                  'you trust, write notes, and search them with typo tolerance and '
                  'local BM25 ranking — no query leaves the device.',
              actions: [
                SiftIconButton(
                  icon: Icons.note_add_outlined,
                  tooltip: 'Write a note',
                  onPressed: _addNote,
                ),
              ],
              bottom: 18,
            ),
            SiftSearchBar(
              controller: _controller,
              focusNode: _focus,
              hintText: 'Search your indexed pages',
              onSubmitted: _runSearch,
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: _services.settings.starterIndexEnabled
                        ? _index.starterCount.toString()
                        : '0',
                    label: 'shelf entries',
                  ),
                ),
                Container(width: 1, height: 30, color: p.line),
                Expanded(
                  child: _Stat(
                    value: _index.customCount.toString(),
                    label: 'your pages',
                  ),
                ),
                Container(width: 1, height: 30, color: p.line),
                Expanded(
                  child: _Stat(
                    value: _index.usesNativeCore ? 'RUST' : 'DART',
                    label: 'ranking core',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                SiftButton(
                  label: 'Index a page',
                  icon: Icons.add_link_rounded,
                  compact: true,
                  busy: _indexing,
                  onPressed: _indexing ? null : _addPage,
                ),
                const Spacer(),
                Text(
                  _services.settings.starterIndexEnabled
                      ? 'Shelf on'
                      : 'Shelf off',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.faint,
                        fontSize: 8.5,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const SiftRule(),
            const SizedBox(height: 13),
            Row(
              children: [
                SiftFilterTab(
                  label: 'Everything',
                  selected: _scope == _Scope.all,
                  onTap: () => _selectScope(_Scope.all),
                ),
                SiftFilterTab(
                  label: 'Your pages',
                  selected: _scope == _Scope.custom,
                  onTap: () => _selectScope(_Scope.custom),
                ),
                SiftFilterTab(
                  label: 'Shelf',
                  selected: _scope == _Scope.starter,
                  onTap: () => _selectScope(_Scope.starter),
                ),
              ],
            ),
            const SiftRule(),
            const SizedBox(height: 16),
            if (_query.isEmpty) ...[
              if (_scope != _Scope.starter) ...[
                _CustomPages(
                  documents: custom,
                  onOpen: (document) => openSiftUrl(
                    context,
                    document.url,
                    title: document.title,
                  ),
                  onRemove: _remove,
                  onAdd: _addPage,
                ),
                const SizedBox(height: 26),
              ],
              if (_scope != _Scope.custom &&
                  _services.settings.starterIndexEnabled) ...[
                _ShelfPreview(
                  documents: _index.starterDocuments,
                  onOpen: (document) => openSiftUrl(
                    context,
                    document.url,
                    title: document.title,
                  ),
                ),
              ] else if (_scope != _Scope.custom) ...[
                SiftEmpty(
                  icon: Icons.tune_rounded,
                  title: 'The starter shelf is off',
                  body:
                      'Only pages and notes you add yourself are searched. The '
                      'shelf can be turned back on in Settings → Search.',
                ),
              ],
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _searching
                          ? 'Searching the local index…'
                          : '${_results.length} local ${pluralize(_results.length, 'match')} for “$_query”',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.muted,
                          ),
                    ),
                  ),
                  if (_searching)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.3,
                        color: p.moss,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (_error != null)
                SiftErrorNote(
                  message: _error!,
                  onRetry: () => _runSearch(_query),
                )
              else if (!_searching && _results.isEmpty)
                SiftEmpty(
                  icon: Icons.manage_search_outlined,
                  title: 'Nothing in the index yet',
                  body:
                      'Your index only searches pages you have added, or the starter '
                      'shelf if it is enabled. Try a broader word, add a page, or '
                      'search the web instead.',
                  action: SiftButton(
                    label: 'Search the web',
                    icon: Icons.travel_explore_rounded,
                    tone: SiftButtonTone.line,
                    onPressed: () {
                      _services.searchBus.submit(_query);
                    },
                  ),
                )
              else
                for (var i = 0; i < _results.length; i++) ...[
                  WebResultTile(
                    result: _results[i],
                    dense: true,
                    onTap: () => _open(_results[i]),
                    onLongPress: () =>
                        showResultActions(context, _results[i]),
                  ),
                  if (i != _results.length - 1) const SiftRule(),
                ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: p.mossDeep,
                fontSize: 17,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.faint,
                fontSize: 8.5,
              ),
        ),
      ],
    );
  }
}

class _CustomPages extends StatelessWidget {
  const _CustomPages({
    required this.documents,
    required this.onOpen,
    required this.onRemove,
    required this.onAdd,
  });

  final List<LocalDocument> documents;
  final ValueChanged<LocalDocument> onOpen;
  final ValueChanged<LocalDocument> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    if (documents.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SiftSectionHead(
            kicker: 'YOUR CORPUS',
            title: 'Pages you trust',
            bottomPadding: 4,
          ),
          SiftEmpty(
            icon: Icons.library_add_outlined,
            title: 'Your index is empty',
            body:
                'Add a reference page, documentation, or a long article. Sift '
                'stores a compact text extract on this phone and never uploads it.',
            action: SiftButton(
              label: 'Index the first page',
              icon: Icons.add_link_rounded,
              compact: true,
              onPressed: onAdd,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SiftSectionHead(
          kicker: 'YOUR CORPUS',
          title: 'Pages you trust',
          action: 'Add another',
          onAction: onAdd,
          bottomPadding: 4,
        ),
        for (var i = 0; i < documents.length; i++) ...[
          InkWell(
            onTap: () => onOpen(documents[i]),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.mossWash,
                      borderRadius: BorderRadius.circular(SiftRadius.xs),
                    ),
                    child: Icon(
                      Icons.article_outlined,
                      size: 15,
                      color: p.mossDeep,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          documents[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${domainOf(documents[i].url)} · ${documents[i].body.length} characters',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: p.faint,
                                    fontSize: 8.5,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  SiftIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Remove from index',
                    onPressed: () => onRemove(documents[i]),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
          if (i != documents.length - 1) const SiftRule(),
        ],
      ],
    );
  }
}

class _ShelfPreview extends StatelessWidget {
  const _ShelfPreview({required this.documents, required this.onOpen});

  final List<LocalDocument> documents;
  final ValueChanged<LocalDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final sections = <String, List<LocalDocument>>{};
    for (final document in documents) {
      sections.putIfAbsent(document.section, () => []).add(document);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SiftSectionHead(
          kicker: 'THE STARTER SHELF',
          title: 'A small, chosen reference',
          bottomPadding: 8,
        ),
        Text(
          'Curated summaries with links to the original sources. Toggle the shelf '
          'off in Settings if you only want your own pages.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: p.muted,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 15),
        for (final entry in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 7),
            child: SiftKicker(entry.key),
          ),
          for (final document in entry.value.take(3))
            InkWell(
              onTap: () => onOpen(document),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.clay,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        document.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: p.inkSoft,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 11),
        ],
      ],
    );
  }
}

class _IndexPageSheet extends StatelessWidget {
  const _IndexPageSheet({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SiftSheetTitle(
            title: 'Index a page',
            subtitle:
                'Sift fetches one public page, extracts its readable text, and keeps '
                'about 14,000 characters in a local index. The page is never sent anywhere else.',
          ),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'https://example.org/article',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          const SizedBox(height: 10),
          Text(
            'Only public pages work. Paywalled, signed-in, and script-only pages '
            'usually cannot be read.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.faint,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SiftButton(
                  label: 'Cancel',
                  tone: SiftButtonTone.line,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SiftButton(
                  label: 'Fetch and index',
                  icon: Icons.download_rounded,
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewNoteSheet extends StatelessWidget {
  const _NewNoteSheet({required this.title, required this.body});

  final TextEditingController title;
  final TextEditingController body;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SiftSheetTitle(
            title: 'A note for the index',
            subtitle:
                'Notes are stored in Library and can be searched from My Search.',
          ),
          TextField(
            controller: title,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: body,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'What do you want to remember?',
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SiftButton(
                  label: 'Cancel',
                  tone: SiftButtonTone.line,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SiftButton(
                  label: 'Save note',
                  icon: Icons.check_rounded,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.action,
  });

  final String title;
  final String body;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SiftSheetTitle(title: title, subtitle: body),
          Row(
            children: [
              Expanded(
                child: SiftButton(
                  label: 'Keep it',
                  tone: SiftButtonTone.line,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SiftButton(
                  label: action,
                  tone: SiftButtonTone.clay,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
