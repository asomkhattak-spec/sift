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
import '../settings/privacy_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/sources_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onOpenTab});

  /// Switches the root shell to another bottom tab. Used by the home
  /// shortcuts so they are real navigation rather than decoration.
  final ValueChanged<int>? onOpenTab;

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
    final compactHeader = _hasSearched || _showSuggestions;
    void openSources() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SourcesScreen()),
      );
    }

    void openPrivacy() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
      );
    }

    return Scaffold(
      backgroundColor: context.sift.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _Header(
                controller: _controller,
                focusNode: _focus,
                onSubmitted: _submit,
                localOnly: settings.localOnlyMode,
                compact: compactHeader,
                onSources: openSources,
                onPrivacy: openPrivacy,
                onSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
            ),
            if (!_showSuggestions &&
                !settings.localOnlyMode &&
                _hasSearched)
              _VerticalTabs(
                selected: _vertical,
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
      final settings = _services.settings;
      return _Landing(
        key: const ValueKey('landing'),
        shelf: _shelf,
        shelfLoaded: _shelfLoaded,
        recent: rememberActivity
            ? _services.library.recentQueries(limit: 4)
            : const [],
        localOnly: settings.localOnlyMode,
        onQuery: _submit,
        onToggleLocalOnly: () {
          settings.localOnlyMode = !settings.localOnlyMode;
          if (settings.localOnlyMode && _vertical != SearchVertical.all) {
            _vertical = SearchVertical.all;
          }
        },
        onOpenSources: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SourcesScreen()),
        ),
        onOpenTab: widget.onOpenTab,
        onOpenPrivacy: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
        ),
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
          8,
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
            childAspectRatio: 0.68,
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
            const SizedBox(height: 6),
            for (final result in primary) tileFor(result),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 20),
              SiftSectionHead(
                title: 'Images',
                action: 'See all',
                onAction: () => _selectVertical(SearchVertical.images),
                bottomPadding: 10,
              ),
              SizedBox(
                height: 152,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final result = images[index];
                    return SizedBox(
                      width: 132,
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

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: SiftSpace.page),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          const SizedBox(height: 6),
          for (var index = 0; index < results.length; index++)
            tileFor(
              results[index],
              lead: index == 0 && _vertical == SearchVertical.news,
            ),
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
    required this.compact,
    required this.onSources,
    required this.onPrivacy,
    required this.onSettings,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final bool localOnly;
  final bool compact;
  final VoidCallback onSources;
  final VoidCallback onPrivacy;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final modeHint = localOnly
        ? 'Search your on-device index'
        : 'Search the web, or type a site';
    return Container(
      color: p.paper,
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        compact ? 4 : 6,
        SiftSpace.page,
        compact ? 8 : 6,
      ),
      child: Column(
        children: [
          if (compact)
            SizedBox(
              height: 42,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SiftCircleAction(
                      icon: Icons.shield_outlined,
                      tooltip: 'Privacy controls',
                      onPressed: onPrivacy,
                      size: 38,
                      iconSize: 19,
                    ),
                  ),
                  const SiftWordmark(size: 27),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SiftCircleAction(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onPressed: onSettings,
                      size: 38,
                      iconSize: 19,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: p.faint),
                const SizedBox(width: 6),
                Text(
                  'No ads · No account',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.muted,
                        fontSize: 12,
                      ),
                ),
                const Spacer(),
                SiftCircleAction(
                  icon: Icons.shield_outlined,
                  tooltip: 'Privacy controls',
                  onPressed: onPrivacy,
                  size: 38,
                  iconSize: 19,
                ),
                const SizedBox(width: 2),
                SiftCircleAction(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onPressed: onSettings,
                  size: 38,
                  iconSize: 19,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Center(child: SiftWordmark(size: 62)),
            const SizedBox(height: 18),
          ],
          SiftSearchBar(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: onSubmitted,
            onSources: onSources,
            compact: compact,
            hintText: modeHint,
          ),
        ],
      ),
    );
  }
}

class _VerticalTabs extends StatelessWidget {
  const _VerticalTabs({
    required this.selected,
    required this.onSelect,
  });

  final SearchVertical selected;
  final ValueChanged<SearchVertical> onSelect;

  static const _order = <SearchVertical>[
    SearchVertical.all,
    SearchVertical.images,
    SearchVertical.videos,
    SearchVertical.news,
    SearchVertical.discuss,
    SearchVertical.web,
  ];

  IconData _iconFor(SearchVertical vertical) => switch (vertical) {
        SearchVertical.all => Icons.search_rounded,
        SearchVertical.web => Icons.language_rounded,
        SearchVertical.images => Icons.image_outlined,
        SearchVertical.news => Icons.article_outlined,
        SearchVertical.videos => Icons.play_circle_outline_rounded,
        SearchVertical.discuss => Icons.forum_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Row(
          children: [
            for (final vertical in _order)
              _ResultTab(
                label: vertical.label,
                icon: _iconFor(vertical),
                selected: vertical == selected,
                onTap: () => onSelect(vertical),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultTab extends StatelessWidget {
  const _ResultTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final color = selected ? p.mossDeep : p.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label results',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: color,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w500 : FontWeight.w400,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Container(
                height: 3,
                width: selected ? 36 : 0,
                decoration: BoxDecoration(
                  color: p.moss,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
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

  IconData _iconFor(QuerySuggestion suggestion) => switch (suggestion.kind) {
        SuggestionKind.history => Icons.history_rounded,
        SuggestionKind.local => Icons.memory_rounded,
        SuggestionKind.web => Icons.search_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        for (final suggestion in suggestions)
          InkWell(
            onTap: () => onSelect(suggestion.text),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: SiftSpace.page),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Icon(
                      _iconFor(suggestion),
                      size: 18,
                      color: suggestion.kind == SuggestionKind.local
                          ? p.moss
                          : p.faint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      suggestion.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: p.ink,
                            fontSize: 16,
                            height: 1.3,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.north_west_rounded,
                    size: 15,
                    color: p.faint.withOpacity(0.75),
                  ),
                ],
              ),
            ),
          ),
        InkWell(
          onTap: () => onSelect(query),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              SiftSpace.page,
              16,
              SiftSpace.page,
              16,
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 20, color: p.moss),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    'Search for “$query”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: SiftTextAction(
            label: 'Close suggestions',
            icon: null,
            onTap: onDismiss,
            color: p.muted,
          ),
        ),
      ],
    );
  }
}

class _Landing extends StatelessWidget {
  const _Landing({
    required this.shelf,
    required this.shelfLoaded,
    required this.recent,
    required this.localOnly,
    required this.onQuery,
    required this.onToggleLocalOnly,
    required this.onOpenSources,
    required this.onOpenTab,
    required this.onOpenPrivacy,
    required this.onOpenDoc,
    super.key,
  });

  final List<LocalDocument> shelf;
  final bool shelfLoaded;
  final List<HistoryEntry> recent;
  final bool localOnly;
  final ValueChanged<String> onQuery;
  final VoidCallback onToggleLocalOnly;
  final VoidCallback onOpenSources;
  final ValueChanged<int>? onOpenTab;
  final VoidCallback onOpenPrivacy;
  final ValueChanged<LocalDocument> onOpenDoc;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    const starters = [
      'Rust ownership',
      'How does a heat pump work?',
      'Open source maps',
      'Best time to visit Japan',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SiftSpace.page,
        12,
        SiftSpace.page,
        28,
      ),
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            SiftPillChip(
              label: localOnly ? 'On-device' : 'Web + local',
              icon: localOnly ? Icons.memory_rounded : Icons.public_rounded,
              selected: localOnly,
              onTap: onToggleLocalOnly,
            ),
            SiftPillChip(
              label: 'Sources',
              icon: Icons.tune_rounded,
              onTap: onOpenSources,
            ),
          ],
        ),
        if (onOpenTab != null) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.lg),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SiftShortcut(
                    icon: Icons.manage_search_rounded,
                    label: 'My Search',
                    color: p.moss,
                    onTap: () => onOpenTab!(2),
                  ),
                ),
                Expanded(
                  child: SiftShortcut(
                    icon: Icons.explore_outlined,
                    label: 'Discover',
                    color: SiftPalette.wordmarkGreen,
                    onTap: () => onOpenTab!(1),
                  ),
                ),
                Expanded(
                  child: SiftShortcut(
                    icon: Icons.bookmarks_outlined,
                    label: 'Library',
                    color: p.clay,
                    onTap: () => onOpenTab!(3),
                  ),
                ),
                Expanded(
                  child: SiftShortcut(
                    icon: Icons.shield_outlined,
                    label: 'Privacy',
                    color: const Color(0xFFF9AB00),
                    onTap: onOpenPrivacy,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(SiftRadius.lg),
          child: InkWell(
            onTap: onOpenPrivacy,
            borderRadius: BorderRadius.circular(SiftRadius.lg),
            child: Container(
              padding: const EdgeInsets.fromLTRB(15, 15, 11, 15),
              decoration: BoxDecoration(
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(SiftRadius.lg),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: p.mossWash,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.verified_user_outlined,
                      size: 21,
                      color: p.moss,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Private by default',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: p.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No account, no ad server. Only the sources you keep '
                          'switched on ever see a query.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: p.muted,
                                    fontSize: 12.5,
                                    height: 1.45,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: p.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Try a search',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: p.ink,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final starter in starters)
              _QueryChip(label: starter, onTap: () => onQuery(starter)),
          ],
        ),
        if (recent.isNotEmpty) ...[
          const SizedBox(height: 26),
          Row(
            children: [
              Text(
                'Recent',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: p.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
              ),
              const Spacer(),
              Icon(Icons.lock_outline_rounded, size: 13, color: p.faint),
              const SizedBox(width: 4),
              Text(
                'Only on this device',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.faint,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.lg),
            ),
            child: Column(
              children: [
                for (var index = 0; index < recent.length; index++) ...[
                  if (index > 0)
                    Divider(height: 1, thickness: 0.6, color: p.line),
                  InkWell(
                    onTap: () => onQuery(recent[index].query),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 18,
                            color: p.faint,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              recent[index].query,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: p.ink,
                                    fontSize: 14,
                                  ),
                            ),
                          ),
                          Icon(
                            Icons.north_west_rounded,
                            size: 14,
                            color: p.faint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 26),
        Row(
          children: [
            Text(
              'From My Search',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: p.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const Spacer(),
            if (onOpenTab != null)
              SiftTextAction(
                label: 'See all',
                onTap: () => onOpenTab!(2),
              ),
          ],
        ),
        const SizedBox(height: 10),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.surfaceRaised,
              borderRadius: BorderRadius.circular(SiftRadius.lg),
            ),
            child: Text(
              'Your local shelf is empty. Add pages in My Search to keep them '
              'indexed and searchable on this phone.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.muted,
                    height: 1.55,
                  ),
            ),
          )
        else
          SizedBox(
            height: 160,
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
        const SizedBox(height: 28),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: p.faint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Queries travel from this phone to the sources you enable. Sift '
                'has no account and no ad server in the middle. Network '
                'anonymity still needs a VPN or proxy you trust.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.faint,
                      height: 1.55,
                      fontSize: 11,
                    ),
              ),
            ),
          ],
        ),
      ],
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
      color: p.surfaceRaised,
      borderRadius: BorderRadius.circular(SiftRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SiftRadius.pill),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 13, 9),
          decoration: BoxDecoration(
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(SiftRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 15, color: p.muted),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.inkSoft,
                      fontSize: 12.5,
                    ),
              ),
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
      width: 236,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(SiftRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SiftRadius.lg),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.section.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.mossDeep,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.7,
                      ),
                ),
                const SizedBox(height: 7),
                Text(
                  document.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: p.ink,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  child: Text(
                    document.snippet,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.memory_rounded,
                      size: 13,
                      color: p.faint,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'On-device',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.faint,
                            fontSize: 10.5,
                          ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 15,
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
        18,
        SiftSpace.page,
        20,
      ),
      children: [
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: p.moss,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Searching the sources you chose…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.muted,
                    fontSize: 12.5,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 20),
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
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 4),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(SiftRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: p.mossWash,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.memory_rounded,
                    size: 16,
                    color: p.moss,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'From your device',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                SiftBadge(
                  'My Search',
                  color: p.mossDeep,
                  background: p.mossWash,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (var index = 0; index < matches.length; index++) ...[
            if (index > 0)
              Divider(height: 1, thickness: 0.6, color: p.line),
            InkWell(
              onTap: () => onOpen(matches[index]),
              onLongPress: () => onLongPress(matches[index]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            matches[index].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontSize: 15,
                                  height: 1.35,
                                  fontWeight: FontWeight.w400,
                                  color: p.mossDeep,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${matches[index].meta['section']?.toString() ?? 'Indexed'}'
                            '  ·  On-device',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: p.muted,
                                      fontSize: 11.5,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: p.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
