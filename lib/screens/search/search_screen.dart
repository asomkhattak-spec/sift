import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/library_models.dart';
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
import '../settings/settings_screen.dart';
import '../settings/sources_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  final Map<SearchVertical, SearchBundle> _cache = {};
  final List<QuerySuggestion> _suggestions = [];

  SearchVertical _vertical = SearchVertical.all;
  SearchBundle? _bundle;
  List<SearchResult> _localMatches = const [];
  List<LocalDocument> _shelf = const [];
  String _query = '';
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;
  bool _fetching = false;
  bool _shelfLoaded = false;
  int _requestToken = 0;
  int _suggestionToken = 0;
  Timer? _suggestTimer;
  late final SiftServices _services;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
    _loadShelf();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _services.settings.isFirstRun) return;
      if (_query.isEmpty && _controller.text.isEmpty) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadShelf() async {
    final index = _services.localIndex;
    try {
      if (!index.isLoaded) await index.load();
      if (!mounted) return;
      if (!_services.settings.starterIndexEnabled) {
        setState(() {
          _shelf = const [];
          _shelfLoaded = true;
        });
        return;
      }
      final seen = <String>{};
      final shelf = <LocalDocument>[];
      for (final document in index.starterDocuments) {
        final section = document.section.toLowerCase();
        if (!seen.add(section)) continue;
        shelf.add(document);
      }
      setState(() {
        _shelf = shelf.take(6).toList(growable: false);
        _shelfLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _shelfLoaded = true);
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (!_focus.hasFocus) {
      setState(_suggestions.clear);
      return;
    }
    _refreshSuggestions();
    setState(() {});
  }

  void _onTextChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshSuggestions();
  }

  void _refreshSuggestions() {
    _suggestTimer?.cancel();
    _suggestionToken++;
    final raw = _controller.text.trim();
    if (!_focus.hasFocus || raw.isEmpty || !_services.settings.suggestionsEnabled) {
      if (_suggestions.isNotEmpty) setState(_suggestions.clear);
      return;
    }

    final local = _services.library.querySuggestions(limit: 4);
    setState(() {
      _suggestions
        ..clear()
        ..addAll(local);
    });
    if (raw.length < 2) return;

    final token = ++_suggestionToken;
    _suggestTimer = Timer(const Duration(milliseconds: 220), () async {
      final network = await _services.engine.suggest(raw, limit: 7);
      if (!mounted || token != _suggestionToken || !_focus.hasFocus) return;
      final merged = <QuerySuggestion>[];
      final seen = <String>{};
      for (final item in [...local, ...network]) {
        final key = item.text.toLowerCase();
        if (!seen.add(key)) continue;
        merged.add(item);
      }
      setState(() {
        _suggestions
          ..clear()
          ..addAll(merged.take(8));
      });
    });
  }

  /// Called by the root shell when a query arrives from an Android intent,
  /// the browser start page, or Discover.
  void runSearch(String query) {
    final clean = normalizeQuery(query);
    if (clean.isEmpty) return;
    _controller.text = clean;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    setState(() {
      _vertical = SearchVertical.all;
    });
    _submit(clean);
  }

  void focusSearch() {
    _focus.requestFocus();
  }

  Future<void> _submit(String raw) async {
    final value = raw.trim();
    if (value.isEmpty) return;
    _focus.unfocus();
    _suggestions.clear();

    final direct = navigableUrl(value);
    if (direct != null && isProbablyUrl(value)) {
      await openSiftUrl(context, direct);
      return;
    }

    final query = normalizeQuery(value);
    if (query.isEmpty) return;
    if (query != _query) {
      _cache.clear();
      _localMatches = const [];
    }
    _query = query;
    _controller.text = query;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    unawaited(_services.library.recordQuery(query));
    await _performSearch(SearchVertical.all, query: query);
  }

  Future<void> _performSearch(
    SearchVertical vertical, {
    String? query,
    int page = 0,
  }) async {
    final target = query ?? _query;
    if (target.isEmpty) return;
    final token = ++_requestToken;
    setState(() {
      _vertical = vertical;
      _loading = true;
      _loadingMore = false;
      _error = null;
      if (page == 0) _bundle = null;
    });
    _scrollToTop();

    final request = SearchRequest(
      query: target,
      vertical: vertical,
      page: page,
      safeSearch: _services.settings.safeSearch,
      resultCount: _services.settings.resultCount,
      language: _services.settings.language,
    );

    if (page == 0) {
      setState(() => _fetching = true);
      _services.localIndex
          .search(
            target,
            limit: 4,
            includeStarter: _services.settings.starterIndexEnabled,
          )
          .then((local) {
        if (!mounted || token != _requestToken) return;
        setState(() => _localMatches = local);
      }).catchError((Object _) {});
    }

    SearchBundle? bundle;
    String? error;
    try {
      bundle = await _services.engine.search(
        request,
        onPartial: (partial) {
          if (!mounted || token != _requestToken) return;
          setState(() {
            _bundle = partial;
            _loading = false;
          });
        },
      );
    } catch (failure) {
      error = failure.toString();
    }
    if (!mounted || token != _requestToken) return;

    if (bundle != null) {
      _cache[vertical] = bundle;
    }
    setState(() {
      if (bundle != null) _bundle = bundle;
      _error = error;
      _loading = false;
      _fetching = false;
    });
  }

  void _selectVertical(SearchVertical vertical) {
    if (_vertical == vertical && !_loading) {
      return;
    }
    _focus.unfocus();
    _suggestions.clear();
    final cached = _cache[vertical];
    if (cached != null) {
      setState(() {
        _vertical = vertical;
        _bundle = cached;
        _error = null;
        _loading = false;
        _fetching = false;
      });
      _scrollToTop();
      return;
    }
    if (_query.isEmpty) {
      setState(() => _vertical = vertical);
      return;
    }
    _performSearch(vertical);
  }

  Future<void> _loadMore() async {
    final bundle = _bundle;
    if (bundle == null || bundle.nextPage <= 0 || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final newer = await _services.engine.search(
        SearchRequest(
          query: _query,
          vertical: _vertical,
          page: bundle.nextPage,
          safeSearch: _services.settings.safeSearch,
          resultCount: _services.settings.resultCount,
          language: _services.settings.language,
        ),
      );
      if (!mounted) return;
      final merged = bundle.merge(newer);
      _cache[_vertical] = merged;
      setState(() {
        _bundle = merged;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showSiftToast(context, 'More results did not arrive.', error: true);
    }
  }

  void _scrollToTop() {
    if (!_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool get _showSuggestions =>
      _focus.hasFocus && _controller.text.trim().isNotEmpty;

  bool get _hasSearched => _query.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final settings = _services.settings;
    return Scaffold(
      backgroundColor: context.sift.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              controller: _controller,
              focusNode: _focus,
              onSubmitted: _submit,
              localOnly: settings.localOnlyMode,
              onToggleLocalOnly: () {
                settings.localOnlyMode = !settings.localOnlyMode;
                if (_hasSearched) {
                  _cache.clear();
                  _performSearch(_vertical, query: _query);
                }
              },
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
            ),
            if (!settings.localOnlyMode &&
                (_hasSearched || _controller.text.trim().isNotEmpty))
              _VerticalTabs(
                selected: _vertical,
                bundle: _bundle,
                onSelect: _selectVertical,
              ),
            Expanded(
              child: _showSuggestions
                  ? _SuggestionPanel(
                      suggestions: _suggestions,
                      query: _controller.text.trim(),
                      onSelect: _submit,
                      onDismiss: () => _focus.unfocus(),
                    )
                  : _buildBody(settings.rememberActivity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool rememberActivity) {
    if (!_hasSearched) {
      return _Landing(
        key: const ValueKey('landing'),
        controller: _controller,
        shelf: _shelf,
        shelfLoaded: _shelfLoaded,
        recent: rememberActivity
            ? _services.library.recentQueries(limit: 4)
            : const [],
        onQuery: _submit,
        onOpenDoc: (document) => openSiftUrl(
          context,
          document.url,
          title: document.title,
        ),
      );
    }

    if (_loading && _bundle == null && _localMatches.isEmpty) {
      return const _SearchLoading();
    }

    final bundle = _bundle;
    return RefreshIndicator(
      color: context.sift.moss,
      backgroundColor: context.sift.surface,
      onRefresh: () => _performSearch(_vertical, query: _query),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(SiftSpace.page, 8, SiftSpace.page, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bundle != null)
                    ProviderStrip(
                      statuses: bundle.statuses,
                      elapsedMs: bundle.elapsedMs,
                      onTap: () => _showSources(bundle),
                    ),
                  if (_fetching && bundle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.2,
                              color: context.sift.moss,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            bundle.complete
                                ? 'Up to date'
                                : 'Gathering more sources…',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: context.sift.faint,
                                  fontSize: 9,
                                ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: SiftErrorNote(
                        message:
                            'The search sources did not answer cleanly. $_error',
                        onRetry: () => _performSearch(_vertical, query: _query),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (bundle != null &&
              bundle.answer != null &&
              (_vertical == SearchVertical.all ||
                  _vertical == SearchVertical.web))
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SiftSpace.page,
                8,
                SiftSpace.page,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: AnswerCard(
                  answer: bundle.answer!,
                  onOpenLink: (url) =>
                      openSiftUrl(context, url, title: bundle.answer?.title ?? ''),
                ),
              ),
            ),
          if (_localMatches.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SiftSpace.page,
                10,
                SiftSpace.page,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _LocalMatches(
                  matches: _localMatches,
                  onOpen: (result) => openSiftUrl(
                    context,
                    result.url,
                    title: result.title,
                  ),
                  onLongPress: (result) =>
                      showResultActions(context, result),
                ),
              ),
            ),
          if (bundle != null) _resultsSliver(bundle),
          if (bundle != null &&
              bundle.isEmpty &&
              _localMatches.isEmpty &&
              _error == null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: SiftSpace.page),
              sliver: SliverToBoxAdapter(
                child: EmptyResults(
                  query: _query,
                  onChangeSources: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SourcesScreen(),
                    ),
                  ),
                ),
              ),
            ),
          if (bundle != null && bundle.nextPage > 0 && !bundle.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                SiftSpace.page,
                8,
                SiftSpace.page,
                28,
              ),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: _loadingMore
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        )
                      : SiftButton(
                          label: 'More results',
                          tone: SiftButtonTone.line,
                          compact: true,
                          onPressed: _loadMore,
                        ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 34)),
        ],
      ),
    );
  }

  Widget _resultsSliver(SearchBundle bundle) {
    final results = bundle.forVertical(_vertical);
    if (results.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    if (_vertical == SearchVertical.images) {
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          SiftSpace.page,
          10,
          SiftSpace.page,
          0,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width > 620
                ? 4
                : MediaQuery.sizeOf(context).width > 380
                    ? 3
                    : 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 16,
            childAspectRatio: 0.7,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final result = results[index];
              return ImageResultTile(
                result: result,
                onTap: () => showImagePreview(context, result),
              );
            },
            childCount: results.length,
          ),
        ),
      );
    }

    Widget tileFor(SearchResult result, {bool lead = false}) {
      final tap = () => openSiftUrl(context, result.url, title: result.title);
      final longPress = () => showResultActions(context, result);
      return switch (result.kind) {
        ResultKind.news => NewsResultTile(
            result: result,
            lead: lead,
            onTap: tap,
            onLongPress: longPress,
          ),
        ResultKind.video => VideoResultTile(
            result: result,
            onTap: tap,
            onLongPress: longPress,
          ),
        ResultKind.discussion => DiscussionResultTile(
            result: result,
            onTap: tap,
            onLongPress: longPress,
          ),
        ResultKind.image => ImageResultTile(
            result: result,
            onTap: () => showImagePreview(context, result),
          ),
        ResultKind.web => WebResultTile(
            result: result,
            dense: _vertical == SearchVertical.all,
            onTap: tap,
            onLongPress: longPress,
          ),
      };
    }

    if (_vertical == SearchVertical.all) {
      final primary =
          results.where((result) => result.kind != ResultKind.image).toList();
      final images = bundle.images.take(6).toList();
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: SiftSpace.page),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: 4),
            SiftSectionHead(
              kicker: '${primary.length} ranked on device',
              title: 'Top results',
              bottomPadding: 2,
            ),
            for (var index = 0; index < primary.length; index++) ...[
              if (index > 0) const SiftRule(),
              tileFor(primary[index]),
            ],
            if (images.isNotEmpty) ...[
              const SizedBox(height: 22),
              SiftSectionHead(
                kicker: 'Openverse and the web',
                title: 'Images',
                bottomPadding: 10,
              ),
              SizedBox(
                height: 176,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final result = images[index];
                    return SizedBox(
                      width: 138,
                      child: ImageResultTile(
                        result: result,
                        onTap: () => showImagePreview(context, result),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 18),
          ]),
        ),
      );
    }

    final title = _vertical.pluralTitle;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: SiftSpace.page),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          const SizedBox(height: 4),
          SiftSectionHead(
            kicker: '${results.length} from ${bundle.statuses.where((s) => s.ok).length} sources',
            title: title,
            bottomPadding: 2,
          ),
          for (var index = 0; index < results.length; index++) ...[
            if (index > 0) const SiftRule(),
            tileFor(
              results[index],
              lead: index == 0 &&
                  _vertical == SearchVertical.news,
            ),
          ],
          const SizedBox(height: 18),
        ]),
      ),
    );
  }

  void _showSources(SearchBundle bundle) {
    showSiftSheet<void>(
      context,
      builder: (sheetContext) => _SourceStatusSheet(bundle: bundle),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.localOnly,
    required this.onToggleLocalOnly,
    required this.onSettings,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final bool localOnly;
  final VoidCallback onToggleLocalOnly;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        SiftSpace.page,
        8,
        SiftSpace.page,
        8,
      ),
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SiftWordmark(size: 24),
              const SizedBox(width: 9),
              InkWell(
                onTap: onToggleLocalOnly,
                borderRadius: BorderRadius.circular(SiftRadius.xs),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: localOnly ? p.mossWash : Colors.transparent,
                    border: Border.all(
                      color: localOnly ? p.moss : p.line,
                    ),
                    borderRadius: BorderRadius.circular(SiftRadius.xs),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        localOnly
                            ? Icons.memory_rounded
                            : Icons.public_rounded,
                        size: 12,
                        color: localOnly ? p.mossDeep : p.faint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        localOnly ? 'ON-DEVICE' : 'WEB + LOCAL',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: localOnly ? p.mossDeep : p.faint,
                              fontSize: 8.5,
                              letterSpacing: 0.8,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SiftIconButton(
                icon: Icons.tune_rounded,
                tooltip: 'Settings',
                onPressed: onSettings,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SiftSearchBar(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: onSubmitted,
            hintText: localOnly
                ? 'Search your on-device index'
                : 'Search the web, or type a site',
          ),
        ],
      ),
    );
  }
}

class _VerticalTabs extends StatelessWidget {
  const _VerticalTabs({
    required this.selected,
    required this.bundle,
    required this.onSelect,
  });

  final SearchVertical selected;
  final SearchBundle? bundle;
  final ValueChanged<SearchVertical> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      color: p.paper,
      padding: const EdgeInsets.only(left: SiftSpace.page, right: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final vertical in SearchVertical.values)
              SiftFilterTab(
                label: vertical.label,
                selected: vertical == selected,
                count: bundle?.forVertical(vertical).length,
                onTap: () => onSelect(vertical),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestions,
    required this.query,
    required this.onSelect,
    required this.onDismiss,
  });

  final List<QuerySuggestion> suggestions;
  final String query;
  final ValueChanged<String> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SiftSpace.page,
        16,
        SiftSpace.page,
        24,
      ),
      children: [
        Row(
          children: [
            const Expanded(child: SiftKicker('Suggestions')),
            SiftTextAction(label: 'Close', onTap: onDismiss),
          ],
        ),
        const SizedBox(height: 8),
        for (final suggestion in suggestions)
          InkWell(
            onTap: () => onSelect(suggestion.text),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                children: [
                  Icon(
                    switch (suggestion.kind) {
                      SuggestionKind.history => Icons.history_rounded,
                      SuggestionKind.local => Icons.storage_outlined,
                      SuggestionKind.web => Icons.search_rounded,
                    },
                    size: 17,
                    color: suggestion.kind == SuggestionKind.web
                        ? p.faint
                        : p.moss,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      suggestion.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: p.ink,
                            fontSize: 15,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (suggestion.kind != SuggestionKind.web)
                    SiftBadge(
                      suggestion.kind == SuggestionKind.history
                          ? 'History'
                          : 'On device',
                      color: p.mossDeep,
                      background: p.mossWash,
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.north_west_rounded,
                    size: 14,
                    color: p.faint,
                  ),
                ],
              ),
            ),
          ),
        const SiftRule(),
        InkWell(
          onTap: () => onSelect(query),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Row(
              children: [
                Icon(Icons.arrow_forward_rounded, size: 17, color: p.clay),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Search for “$query”',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Landing extends StatelessWidget {
  const _Landing({
    required this.controller,
    required this.shelf,
    required this.shelfLoaded,
    required this.recent,
    required this.onQuery,
    required this.onOpenDoc,
    super.key,
  });

  final TextEditingController controller;
  final List<LocalDocument> shelf;
  final bool shelfLoaded;
  final List<HistoryEntry> recent;
  final ValueChanged<String> onQuery;
  final ValueChanged<LocalDocument> onOpenDoc;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final now = DateTime.now();
    const starters = [
      'Rust ownership',
      'How does a heat pump work?',
      'Open source maps',
      'Best time to visit Japan',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SiftSpace.page,
        22,
        SiftSpace.page,
        30,
      ),
      children: [
        SiftKicker(greetingFor(now), color: p.clay),
        const SizedBox(height: 10),
        Text(
          'What are you looking for?',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 30,
                height: 1.08,
                letterSpacing: -0.5,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Answers come from the on-device index first, and only from the web '
          'sources you keep switched on.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: p.muted,
                height: 1.55,
              ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: const [
            _TrustChip(icon: Icons.block_outlined, label: 'No ads'),
            _TrustChip(icon: Icons.person_off_outlined, label: 'No account'),
            _TrustChip(icon: Icons.tune_rounded, label: 'You choose sources'),
          ],
        ),
        const SizedBox(height: 30),
        SiftSectionHead(
          kicker: 'Try one',
          title: 'Start somewhere',
          bottomPadding: 10,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final starter in starters)
              _QueryChip(label: starter, onTap: () => onQuery(starter)),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 28),
          const SiftSectionHead(
            kicker: 'Only on this device',
            title: 'Recent searches',
            bottomPadding: 4,
          ),
          for (final entry in recent)
            InkWell(
              onTap: () => onQuery(entry.query),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 15, color: p.faint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: p.inkSoft,
                            ),
                      ),
                    ),
                    Icon(
                      Icons.north_west_rounded,
                      size: 13,
                      color: p.faint,
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 28),
        SiftSectionHead(
          kicker: 'A curated shelf, not a crawl',
          title: 'From My Search',
          bottomPadding: 10,
        ),
        if (!shelfLoaded)
          const SizedBox(
            height: 130,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 1.4),
              ),
            ),
          )
        else if (shelf.isEmpty)
          Text(
            'The local shelf is empty. Open My Search to add pages you want '
            'to keep and search on this device.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.55,
                ),
          )
        else
          SizedBox(
            height: 142,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: shelf.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final document = shelf[index];
                return _ShelfCard(
                  document: document,
                  onTap: () => onOpenDoc(document),
                );
              },
            ),
          ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded, size: 13, color: p.faint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Queries go from this phone to the sources you enable. There '
                  'is no Sift account and no ad server in the middle. Network '
                  'anonymity still needs a VPN or proxy you trust.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.faint,
                        height: 1.55,
                        fontSize: 8.5,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          controller.text.isEmpty
              ? 'Tip: long-press any result for save, share, and on-device indexing.'
              : '',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.faint,
                fontSize: 8.5,
                letterSpacing: 0.1,
              ),
        ),
      ],
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(SiftRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: p.moss),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.muted,
                  fontSize: 8.5,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

class _QueryChip extends StatelessWidget {
  const _QueryChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(SiftRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SiftRadius.sm),
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border.all(color: p.lineStrong),
            borderRadius: BorderRadius.circular(SiftRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.inkSoft,
                      fontSize: 12,
                    ),
              ),
              const SizedBox(width: 7),
              Icon(Icons.arrow_outward_rounded, size: 12, color: p.clay),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfCard extends StatelessWidget {
  const _ShelfCard({required this.document, required this.onTap});

  final LocalDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return SizedBox(
      width: 204,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(SiftRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SiftRadius.md),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              border: Border.all(color: p.lineStrong),
              borderRadius: BorderRadius.circular(SiftRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.section.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.clay,
                        fontSize: 8,
                        letterSpacing: 0.8,
                      ),
                ),
                const SizedBox(height: 7),
                Expanded(
                  child: Text(
                    document.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                  ),
                ),
                Row(
                  children: [
                    Text(
                      'Reference',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.faint,
                            fontSize: 8,
                          ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.north_east_rounded,
                      size: 12,
                      color: p.moss,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchLoading extends StatelessWidget {
  const _SearchLoading();

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SiftSpace.page,
        16,
        SiftSpace.page,
        20,
      ),
      children: [
        Row(
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.3,
                color: p.moss,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              'ASKING THE SOURCES',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: p.muted,
                    fontSize: 9,
                    letterSpacing: 1,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SiftSkeletonRows(rows: 4),
      ],
    );
  }
}

class _LocalMatches extends StatelessWidget {
  const _LocalMatches({
    required this.matches,
    required this.onOpen,
    required this.onLongPress,
  });

  final List<SearchResult> matches;
  final ValueChanged<SearchResult> onOpen;
  final ValueChanged<SearchResult> onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      decoration: BoxDecoration(
        color: p.mossWash,
        border: Border.all(color: p.moss.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(SiftRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SiftKicker(
                  'On this device',
                  color: p.mossDeep,
                  trailing: SiftBadge(
                    'My Search',
                    color: p.mossDeep,
                    background: p.surface.withOpacity(0.55),
                  ),
                ),
              ),
              Text(
                '${matches.length}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.mossDeep,
                      fontSize: 8.5,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final match in matches)
            InkWell(
              onTap: () => onOpen(match),
              onLongPress: () => onLongPress(match),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.article_outlined, size: 14, color: p.moss),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            match.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontSize: 13,
                                      color: p.ink,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (match.meta['section']?.toString() ?? 'Indexed')
                                .toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: p.faint,
                                  fontSize: 7.5,
                                  letterSpacing: 0.5,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.north_west_rounded,
                      size: 12,
                      color: p.moss,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceStatusSheet extends StatelessWidget {
  const _SourceStatusSheet({required this.bundle});

  final SearchBundle bundle;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final settings = SiftScope.servicesOf(context).settings;
    final failed = bundle.statuses.where((status) => !status.ok).toList();
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
            title: 'Where this came from',
            subtitle:
                'Each request left this device directly. Sift runs no proxy '
                'and keeps no copy of provider responses.',
          ),
          const SizedBox(height: 14),
          for (final status in bundle.statuses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      status.ok
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 15,
                      color: status.ok ? p.moss : p.clay,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.sourceName,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontSize: 13,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status.ok
                              ? '${status.count} results · ${status.elapsedMs} ms'
                              : status.error ?? 'Unavailable',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: p.faint,
                                    fontSize: 8.5,
                                    letterSpacing: 0.2,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  if (status.host != null)
                    Text(
                      status.host!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.faint,
                            fontSize: 8,
                          ),
                    ),
                ],
              ),
            ),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 10),
            SiftErrorNote(
              message:
                  '${failed.length} ${pluralize(failed.length, 'source')} did '
                  'not answer. The rest of the page still reflects the results '
                  'that did.',
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.surfaceRaised,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  settings.proxyEnabled
                      ? Icons.route_rounded
                      : Icons.lan_outlined,
                  size: 15,
                  color: p.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    settings.proxyEnabled
                        ? 'HTTP requests are routed through '
                            '${settings.proxyHost}:${settings.proxyPort}. '
                            'The proxy can see those requests; use one you trust.'
                        : 'No proxy is set. Your network provider can see which '
                            'hosts this phone contacted, even though they cannot '
                            'see the Sift interface or local index.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
