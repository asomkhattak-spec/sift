import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/native_bridge.dart';
import '../core/services/sift_scope.dart';
import '../core/theme/sift_theme.dart';
import '../core/utils/navigation.dart';
import '../screens/discover/discover_screen.dart';
import '../screens/library/library_screen.dart';
import '../screens/my_search/my_search_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/privacy_screen.dart';
import '../screens/welcome_sheet.dart';
import '../widgets/sift_ui.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _searchKey = GlobalKey<SearchScreenState>();
  final _discoverKey = GlobalKey<DiscoverScreenState>();
  final _mySearchKey = GlobalKey<MySearchScreenState>();
  final _libraryKey = GlobalKey<LibraryScreenState>();

  final Set<int> _built = {0};
  int _index = 0;
  StreamSubscription<IncomingIntent>? _intentSubscription;
  late final SiftServices _services;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _services.searchBus.addListener(_onExternalSearch);
    _intentSubscription = _services.native.intents.listen(_handleIntent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeInitialIntent();
      _maybeWelcome();
    });
  }

  @override
  void dispose() {
    _services.searchBus.removeListener(_onExternalSearch);
    _intentSubscription?.cancel();
    super.dispose();
  }

  void _onExternalSearch() {
    final query = _services.searchBus.takePending();
    if (query == null || !mounted) return;
    _select(0);
    // The Search tab may only just have been inserted into the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchKey.currentState?.runSearch(query);
    });
  }

  Future<void> _consumeInitialIntent() async {
    final intent = await _services.native.initialIntent();
    if (intent != null && mounted) _handleIntent(intent);
  }

  void _handleIntent(IncomingIntent intent) {
    if (!mounted) return;
    final query = intent.query ?? intent.sharedText;
    if (query != null && query.trim().isNotEmpty) {
      _services.searchBus.submit(query);
      return;
    }
    final url = intent.url;
    if (url != null && url.isNotEmpty) {
      unawaited(openSiftUrl(context, url, title: 'Shared link'));
    }
  }

  Future<void> _maybeWelcome() async {
    final settings = _services.settings;
    if (!settings.isFirstRun || !mounted) return;
    await settings.markOpened();
    if (!mounted) return;
    final action = await showSiftSheet<WelcomeAction>(
      context,
      builder: (_) => const WelcomeSheet(),
    );
    if (!mounted) return;
    switch (action) {
      case WelcomeAction.search:
        _select(0);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchKey.currentState?.focusSearch();
        });
        break;
      case WelcomeAction.privacy:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
        );
        break;
      case null:
        break;
    }
  }

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_index == index) return;
    setState(() {
      _index = index;
      _built.add(index);
    });
  }

  Widget _pageFor(int index) {
    if (!_built.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => SearchScreen(key: _searchKey, onOpenTab: _select),
      1 => DiscoverScreen(key: _discoverKey),
      2 => MySearchScreen(key: _mySearchKey),
      _ => LibraryScreen(key: _libraryKey),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Scaffold(
      backgroundColor: p.paper,
      body: IndexedStack(
        index: _index,
        children: [
          for (var index = 0; index < 4; index++) _pageFor(index),
        ],
      ),
      bottomNavigationBar: SiftBottomBar(
        index: _index,
        onSelect: _select,
      ),
    );
  }
}

class SiftBottomBar extends StatelessWidget {
  const SiftBottomBar({
    required this.index,
    required this.onSelect,
    super.key,
  });

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.search_outlined, Icons.search, 'Search'),
    (Icons.explore_outlined, Icons.explore, 'Discover'),
    (Icons.manage_search_outlined, Icons.manage_search, 'My Search'),
    (Icons.bookmarks_outlined, Icons.bookmarks, 'Library'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Material(
      color: p.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SiftRule(color: p.lineStrong),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _BottomItem(
                        icon: _items[i].$1,
                        selectedIcon: _items[i].$2,
                        label: _items[i].$3,
                        selected: i == index,
                        onTap: () => onSelect(i),
                      ),
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

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final color = selected ? p.mossDeep : p.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: selected ? 46 : 36,
              height: 28,
              decoration: BoxDecoration(
                color: selected ? p.mossWash : Colors.transparent,
                borderRadius: BorderRadius.circular(SiftRadius.pill),
              ),
              child: Icon(
                selected ? selectedIcon : icon,
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 10,
                    letterSpacing: 0,
                    fontWeight:
                        selected ? FontWeight.w500 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
