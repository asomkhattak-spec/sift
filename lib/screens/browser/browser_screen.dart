import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/search/local_index.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../core/utils/navigation.dart';
import '../../core/utils/text_utils.dart';
import '../../widgets/sift_ui.dart';

/// The reading surface. Each tab keeps its own WebView so back/forward state,
/// scroll position, and a signed-in session survive switching tabs. Private
/// mode is handled by the WebView's incognito setting rather than by pretending
/// the network cannot see the request.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    this.initialUrl = '',
    this.initialTitle = '',
    super.key,
  });

  final String initialUrl;
  final String initialTitle;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserTab {
  _BrowserTab({required this.url, String title = ''})
      : title = title.isEmpty ? (url.isEmpty ? 'New tab' : domainOf(url)) : title;

  String url;
  String title;
  bool loading = false;
  double progress = 0;
  InAppWebViewController? controller;
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final SiftServices _services;
  late final TextEditingController _address;
  final FocusNode _addressFocus = FocusNode();
  final TextEditingController _find = TextEditingController();
  final FocusNode _findFocus = FocusNode();

  late final List<_BrowserTab> _tabs;
  int _current = 0;
  bool _findOpen = false;
  int _matches = 0;
  bool _reading = false;

  _BrowserTab get _tab => _tabs[_current];

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _tabs = [
      _BrowserTab(url: widget.initialUrl, title: widget.initialTitle),
    ];
    _address = TextEditingController(text: _readableUrl(widget.initialUrl));
    if (_services.settings.privateBrowsing) {
      // A fresh cookie jar is the strongest honest version of "private" that a
      // WebView can offer. It does not hide the IP address.
      unawaited(_clearPrivateSession());
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _find.dispose();
    _addressFocus.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  String _readableUrl(String raw) {
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return raw;
    final path = uri.path == '/' ? '' : uri.path;
    final text = '${uri.host}$path';
    return text.length > 74 ? '${text.substring(0, 71)}…' : text;
  }

  Uri? _asAddress(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.contains(' ')) return null;
    var candidate = value;
    if (!value.contains('://')) candidate = 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    if (!(uri.isScheme('http') || uri.isScheme('https'))) return null;
    final host = uri.host;
    if (host.isEmpty) return null;
    final isIp = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    if (!host.contains('.') && host != 'localhost' && !isIp) return null;
    return uri;
  }

  void _paintAddress() {
    if (_addressFocus.hasFocus) return;
    final text = _readableUrl(_tab.url);
    if (_address.text != text) _address.text = text;
  }

  Future<void> _submitAddress(String raw) async {
    final uri = _asAddress(raw);
    if (uri == null) {
      final query = normalizeQuery(raw);
      if (query.isNotEmpty) startSiftSearch(context, query);
      return;
    }
    await _load(uri.toString());
  }

  Future<void> _load(String rawUrl) async {
    final cleaned = _services.settings.stripTrackingParams
        ? stripTrackingParams(rawUrl)
        : rawUrl;
    final uri = Uri.tryParse(cleaned);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      showSiftToast(context, 'That is not a web address.', error: true);
      return;
    }
    _tab.url = cleaned;
    _tab.title = domainOf(cleaned);
    _tab.loading = true;
    setState(_paintAddress);
    final controller = _tab.controller;
    if (controller == null) return;
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(cleaned)),
    );
    if (mounted) setState(_paintAddress);
  }

  Future<void> _openNewTab([String url = '']) async {
    if (_tabs.length >= 8) {
      showSiftToast(context, 'Eight tabs is the limit on this phone.');
      return;
    }
    setState(() {
      _tabs.add(_BrowserTab(url: url));
      _current = _tabs.length - 1;
      _address.text = _readableUrl(url);
    });
    if (url.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(url));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addressFocus.requestFocus();
      });
    }
  }

  Future<void> _closeTab(int index) async {
    if (_tabs.length == 1) {
      setState(() {
        _tabs[0] = _BrowserTab(url: '');
        _current = 0;
        _address.clear();
      });
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_current >= _tabs.length) _current = _tabs.length - 1;
      _paintAddress();
    });
  }

  Future<void> _closeBrowser() async {
    if (_services.settings.privateBrowsing) {
      await _clearPrivateSession();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clearPrivateSession() async {
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (_) {
      // A platform without a cookie manager still runs the rest of the app.
    }
  }

  Future<void> _goBack() async {
    final controller = _tab.controller;
    if (controller == null) return;
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else {
      await _closeBrowser();
    }
  }

  Future<void> _goForward() async {
    final controller = _tab.controller;
    if (controller == null) return;
    if (await controller.canGoForward()) await controller.goForward();
  }

  Future<void> _reload() async {
    await _tab.controller?.reload();
  }

  Future<void> _openTabsSheet() async {
    final selected = await showSiftSheet<int>(
      context,
      builder: (_) => _TabsSheet(
        tabs: _tabs,
        current: _current,
        onNew: () {
          Navigator.of(context).pop(_TabsSheet.newTab);
        },
        onClose: (index) {
          Navigator.of(context).pop(_TabsSheet.closeTab(index));
        },
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == _TabsSheet.newTab) {
      await _openNewTab();
      return;
    }
    if (selected <= _TabsSheet.closeBase) {
      await _closeTab(_TabsSheet.closedIndex(selected));
      return;
    }
    if (selected >= 0 && selected < _tabs.length) {
      setState(() {
        _current = selected;
        _paintAddress();
      });
    }
  }

  Future<void> _save() async {
    final tab = _tab;
    if (tab.url.isEmpty) {
      showSiftToast(context, 'Nothing to save yet.');
      return;
    }
    await _services.library.saveUrl(
      url: tab.url,
      title: tab.title,
      snippet: '',
      source: 'Web',
    );
    if (mounted) showSiftToast(context, 'Saved to your library.');
  }

  Future<void> _index() async {
    final tab = _tab;
    if (tab.url.isEmpty) {
      showSiftToast(context, 'Open a page first.');
      return;
    }
    setState(() => _reading = true);
    try {
      final document = await _services.localIndex.indexUrl(tab.url);
      if (!mounted) return;
      showSiftToast(context, 'Indexed “${document.title}”.');
    } on LocalIndexException catch (error) {
      if (mounted) showSiftToast(context, error.message, error: true);
    } catch (_) {
      if (mounted) {
        showSiftToast(context, 'That page could not be indexed.', error: true);
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _share() async {
    final tab = _tab;
    if (tab.url.isEmpty) return;
    await shareSiftText(
      context,
      text: tab.title,
      title: tab.title,
      url: tab.url,
    );
  }

  Future<void> _copy() async {
    final tab = _tab;
    if (tab.url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: tab.url));
    if (mounted) showSiftToast(context, 'Link copied.');
  }

  Future<void> _openExternal() async {
    final ok = await _services.native.openExternal(_tab.url);
    if (!ok && mounted) {
      showSiftToast(context, 'No app could open this address.', error: true);
    }
  }

  Future<void> _extractReader() async {
    final tab = _tab;
    final controller = tab.controller;
    if (controller == null || tab.url.isEmpty) {
      showSiftToast(context, 'Open a page first.');
      return;
    }
    setState(() => _reading = true);
    try {
      final raw = await controller.evaluateJavascript(source: _readerScript);
      final extracted = _readPayload(raw);
      if (!mounted) return;
      final text = extracted.$2.trim();
      if (text.length < 180) {
        showSiftToast(
          context,
          'This page does not expose a readable article. Try another page.',
          error: true,
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            url: tab.url,
            title: extracted.$1.isEmpty ? tab.title : extracted.$1,
            text: text,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        showSiftToast(context, 'Reader mode could not read this page.', error: true);
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  (String, String) _readPayload(dynamic raw) {
    dynamic parsed = raw;
    if (raw is String) {
      try {
        parsed = jsonDecode(raw);
      } catch (_) {
        return ('', raw);
      }
    }
    if (parsed is Map) {
      return (
        parsed['title']?.toString() ?? '',
        parsed['text']?.toString() ?? '',
      );
    }
    return ('', '');
  }

  Future<void> _showMenu() async {
    final action = await showSiftSheet<String>(
      context,
      builder: (_) => _BrowserMenu(
        canSave: _tab.url.isNotEmpty,
        privateMode: _services.settings.privateBrowsing,
        reading: _reading,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'reader':
        await _extractReader();
        break;
      case 'find':
        _openFind();
        break;
      case 'save':
        await _save();
        break;
      case 'index':
        await _index();
        break;
      case 'share':
        await _share();
        break;
      case 'copy':
        await _copy();
        break;
      case 'reload':
        await _reload();
        break;
      case 'external':
        await _openExternal();
        break;
      case 'tabs':
        await _openTabsSheet();
        break;
    }
  }

  void _openFind() {
    setState(() => _findOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocus.requestFocus();
    });
  }

  void _closeFind() {
    _tab.controller?.clearMatches();
    setState(() {
      _findOpen = false;
      _matches = 0;
      _find.clear();
    });
    _findFocus.unfocus();
  }

  Future<void> _runFind(String value) async {
    final controller = _tab.controller;
    if (controller == null) return;
    final needle = value.trim();
    if (needle.isEmpty) {
      await controller.clearMatches();
      if (mounted) setState(() => _matches = 0);
      return;
    }
    await controller.findAllAsync(find: needle);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _goBack();
      },
      child: Scaffold(
        backgroundColor: p.paper,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _TopChrome(
                address: _address,
                focusNode: _addressFocus,
                loading: _tab.loading,
                progress: _tab.progress,
                onClose: _closeBrowser,
                onSubmitted: _submitAddress,
                onMenu: _showMenu,
                onReload: _reload,
              ),
              if (_findOpen)
                _FindBar(
                  controller: _find,
                  focusNode: _findFocus,
                  matches: _matches,
                  onChanged: _runFind,
                  onPrevious: () => _tab.controller?.findNext(forward: false),
                  onNext: () => _tab.controller?.findNext(forward: true),
                  onClose: _closeFind,
                ),
              Expanded(
                child: IndexedStack(
                  index: _current,
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      _buildTab(i),
                  ],
                ),
              ),
              _BottomChrome(
                onBack: _goBack,
                onForward: _goForward,
                onTabs: _openTabsSheet,
                onReader: _extractReader,
                onMenu: _showMenu,
                tabCount: _tabs.length,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    final tab = _tabs[index];
    final settings = _services.settings;
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: tab.url.isEmpty
              ? null
              : URLRequest(url: WebUri(tab.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            javaScriptCanOpenWindowsAutomatically: true,
            supportMultipleWindows: true,
            useShouldInterceptRequest: true,
            useOnDownloadStart: true,
            thirdPartyCookiesEnabled: settings.thirdPartyCookies,
            incognito: settings.privateBrowsing,
            cacheEnabled: !settings.privateBrowsing,
            clearCache: settings.privateBrowsing,
            geolocationEnabled: false,
            mediaPlaybackRequiresUserGesture: true,
            allowsBackForwardNavigationGestures: true,
            domStorageEnabled: true,
            databaseEnabled: true,
            supportZoom: true,
            useHybridComposition: true,
          ),
          shouldInterceptRequest: (controller, request) async {
            if (!settings.blockTrackers || request.isForMainFrame == true) {
              return null;
            }
            final uri = Uri.tryParse(request.url.toString());
            if (uri == null) return null;
            if (_services.blocker.shouldBlock(
              uri,
              isMainFrame: false,
            )) {
              _services.blocker.recordBlocked();
              return WebResourceResponse(
                contentType: 'text/plain',
                data: Uint8List(0),
              );
            }
            return null;
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final uri = action.request.url;
            if (uri == null) return NavigationActionPolicy.ALLOW;
            final scheme = uri.scheme.toLowerCase();
            if (scheme == 'http' || scheme == 'https') {
              return NavigationActionPolicy.ALLOW;
            }
            if (scheme == 'about' || scheme == 'javascript' || scheme == 'data') {
              return NavigationActionPolicy.CANCEL;
            }
            final opened = await _services.native.openExternal(uri.toString());
            if (!opened && mounted) {
              showSiftToast(context, 'No app could handle that link.', error: true);
            }
            return NavigationActionPolicy.CANCEL;
          },
          onCreateWindow: (controller, action) async {
            final url = action.request.url?.toString() ?? '';
            if (url.isNotEmpty) await _openNewTab(url);
            return true;
          },
          onDownloadStartRequest: (controller, request) async {
            final filename = request.suggestedFilename?.trim();
            final guessed = request.url.toString().split('/').last;
            final ok = await _services.native.download(
              url: request.url.toString(),
              filename: (filename == null || filename.isEmpty)
                  ? (guessed.isEmpty ? 'sift-download' : guessed)
                  : filename,
              mime: request.mimeType ?? 'application/octet-stream',
              userAgent: request.userAgent,
            );
            if (mounted) {
              showSiftToast(
                context,
                ok
                    ? 'Download started. Android will show progress in notifications.'
                    : 'Android could not start that download.',
                error: !ok,
              );
            }
          },
          onWebViewCreated: (controller) {
            tab.controller = controller;
          },
          onLoadStart: (controller, url) {
            tab.loading = true;
            if (url != null) tab.url = url.toString();
            if (mounted) setState(_paintAddress);
          },
          onProgressChanged: (controller, progress) {
            if (!mounted) return;
            setState(() => tab.progress = progress / 100);
            if (index == _current) _paintAddress();
          },
          onLoadStop: (controller, url) async {
            final title = await controller.getTitle();
            tab.loading = false;
            tab.progress = 1;
            if (url != null) tab.url = url.toString();
            if (title != null && title.trim().isNotEmpty) {
              tab.title = title.trim();
            }
            if (mounted) setState(_paintAddress);
          },
          onUpdateVisitedHistory: (controller, url, isReload) {
            if (url != null) tab.url = url.toString();
            if (!mounted) return;
            setState(_paintAddress);
            if (mounted && index == _current) _paintAddress();
          },
          onFindResultReceived:
              (controller, activeMatchOrdinal, numberOfMatches, isDoneCounting) {
            if (!mounted || index != _current) return;
            setState(() => _matches = numberOfMatches);
          },
        ),
        if (tab.url.isEmpty)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _StartPage(
                onSearch: () {
                  _addressFocus.requestFocus();
                },
                onOpen: (url) => _load(url),
              ),
            ),
          ),
        if (tab.loading && tab.progress < 0.95)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              value: tab.progress == 0 ? null : tab.progress,
              minHeight: 1.5,
              backgroundColor: Colors.transparent,
              color: context.sift.moss,
            ),
          ),
        if (_reading)
          const Positioned(
            right: 14,
            top: 14,
            child: SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
      ],
    );
  }
}

const String _readerScript = r'''
(function () {
  try {
    var pick = document.querySelector('article') ||
      document.querySelector('[role="main"]') ||
      document.querySelector('main') ||
      document.body;
    var clone = pick.cloneNode(true);
    var strip = 'script,style,noscript,svg,canvas,nav,footer,header,form,aside,iframe,video,button';
    clone.querySelectorAll(strip).forEach(function (node) { node.remove(); });
    var text = (clone.innerText || clone.textContent || '')
      .replace(/[ \t]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n')
      .trim();
    return JSON.stringify({
      title: document.title || '',
      text: text.slice(0, 90000)
    });
  } catch (error) {
    return JSON.stringify({ title: document.title || '', text: '' });
  }
})();
''';

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    required this.address,
    required this.focusNode,
    required this.loading,
    required this.progress,
    required this.onClose,
    required this.onSubmitted,
    required this.onMenu,
    required this.onReload,
  });

  final TextEditingController address;
  final FocusNode focusNode;
  final bool loading;
  final double progress;
  final VoidCallback onClose;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onMenu;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      color: p.paper,
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 7),
      child: Row(
        children: [
          SiftIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close browser',
            onPressed: onClose,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(SiftRadius.sm),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 11),
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: p.moss,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: address,
                      focusNode: focusNode,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: onSubmitted,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.inkSoft,
                            fontSize: 12,
                          ),
                      decoration: InputDecoration(
                        hintText: 'Search Sift or enter an address',
                        hintStyle:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: p.faint,
                                  fontSize: 12,
                                ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          value: progress == 0 ? null : progress,
                          color: p.moss,
                        ),
                      ),
                    )
                  else
                    SiftIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reload',
                      size: 15,
                      onPressed: onReload,
                    ),
                ],
              ),
            ),
          ),
          SiftIconButton(
            icon: Icons.more_vert_rounded,
            tooltip: 'Page menu',
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.controller,
    required this.focusNode,
    required this.matches,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int matches;
  final ValueChanged<String> onChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Find in page',
                border: InputBorder.none,
                isDense: true,
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            '$matches',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.faint,
                  fontSize: 9,
                ),
          ),
          SiftIconButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: 'Previous match',
            size: 17,
            onPressed: matches == 0 ? null : onPrevious,
          ),
          SiftIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Next match',
            size: 17,
            onPressed: matches == 0 ? null : onNext,
          ),
          SiftIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close find',
            size: 17,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _BottomChrome extends StatelessWidget {
  const _BottomChrome({
    required this.onBack,
    required this.onForward,
    required this.onTabs,
    required this.onReader,
    required this.onMenu,
    required this.tabCount,
  });

  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onTabs;
  final VoidCallback onReader;
  final VoidCallback onMenu;
  final int tabCount;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border(top: BorderSide(color: p.line)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom > 0
            ? MediaQuery.paddingOf(context).bottom
            : 6,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          SiftIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: onBack,
          ),
          SiftIconButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Forward',
            onPressed: onForward,
          ),
          SiftIconButton(
            icon: Icons.chrome_reader_mode_outlined,
            tooltip: 'Reader mode',
            onPressed: onReader,
          ),
          SiftIconButton(
            icon: Icons.tab_outlined,
            tooltip: 'Tabs',
            badge: tabCount > 1 ? '$tabCount' : null,
            onPressed: onTabs,
          ),
          SiftIconButton(
            icon: Icons.more_horiz_rounded,
            tooltip: 'More',
            onPressed: onMenu,
          ),
        ],
      ),
    );
  }
}

class _StartPage extends StatelessWidget {
  const _StartPage({required this.onSearch, required this.onOpen});

  final VoidCallback onSearch;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(SiftSpace.page, 34, SiftSpace.page, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftWordmark(size: 34),
          const SizedBox(height: 12),
          Text(
            'A new tab, with nothing watching it.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: p.muted,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 25),
          InkWell(
            onTap: onSearch,
            borderRadius: BorderRadius.circular(SiftRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: p.surface,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(SiftRadius.sm),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: p.moss),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search with Sift, or type an address above',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.muted,
                          ),
                    ),
                  ),
                  Icon(Icons.arrow_upward_rounded, size: 15, color: p.faint),
                ],
              ),
            ),
          ),
          const SizedBox(height: 27),
          const SiftSectionHead(
            kicker: 'A FEW DOORS',
            title: 'Places worth reading',
            bottomPadding: 8,
          ),
          _Door(
            title: 'Wikipedia',
            subtitle: 'The free encyclopedia',
            onTap: () => onOpen('https://en.wikipedia.org'),
          ),
          _Door(
            title: 'Hacker News',
            subtitle: 'A daily argument about software',
            onTap: () => onOpen('https://news.ycombinator.com'),
          ),
          _Door(
            title: 'OpenStreetMap',
            subtitle: 'A map that anyone can correct',
            onTap: () => onOpen('https://www.openstreetmap.org'),
          ),
          _Door(
            title: 'Internet Archive',
            subtitle: 'A library of the web’s memory',
            onTap: () => onOpen('https://archive.org'),
          ),
        ],
      ),
    );
  }
}

class _Door extends StatelessWidget {
  const _Door({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_outward_rounded, size: 15, color: p.faint),
          ],
        ),
      ),
    );
  }
}

class _TabsSheet extends StatelessWidget {
  static const int newTab = -2;
  static const int closeBase = -1000;

  static int closeTab(int index) => closeBase - index;
  static int closedIndex(int selected) => closeBase - selected;

  const _TabsSheet({
    required this.tabs,
    required this.current,
    required this.onNew,
    required this.onClose,
  });

  final List<_BrowserTab> tabs;
  final int current;
  final VoidCallback onNew;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSheetTitle(
            title: 'Tabs',
            subtitle: '${tabs.length} open · private mode is a setting, not a cloak.',
          ),
          for (var i = 0; i < tabs.length; i++)
            InkWell(
              onTap: () => Navigator.of(context).pop(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: p.line)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 27,
                      height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == current ? p.mossWash : p.surfaceRaised,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(
                        Icons.public_rounded,
                        size: 13,
                        color: i == current ? p.mossDeep : p.faint,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tabs[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            tabs[i].url.isEmpty
                                ? 'New tab'
                                : domainOf(tabs[i].url),
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: p.faint,
                                      fontSize: 8,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    SiftIconButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close tab',
                      size: 15,
                      onPressed: () => onClose(i),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 13),
          SiftButton(
            label: 'New tab',
            icon: Icons.add_rounded,
            tone: SiftButtonTone.line,
            onPressed: onNew,
          ),
        ],
      ),
    );
  }
}

class _BrowserMenu extends StatelessWidget {
  const _BrowserMenu({
    required this.canSave,
    required this.privateMode,
    required this.reading,
  });

  final bool canSave;
  final bool privateMode;
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(context).bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSheetTitle(
            title: 'This page',
            subtitle: privateMode
                ? 'Private session. Cookies are cleared at launch; the site still sees your network address.'
                : 'The page is loaded directly from its own host.',
          ),
          if (reading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: p.moss,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Reading the page…',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 9,
                        ),
                  ),
                ],
              ),
            ),
          _Action(
            icon: Icons.chrome_reader_mode_outlined,
            label: 'Reader mode',
            note: 'Strip navigation and read the article',
            onTap: () => Navigator.of(context).pop('reader'),
          ),
          _Action(
            icon: Icons.search_rounded,
            label: 'Find in page',
            note: 'Search the rendered text',
            onTap: () => Navigator.of(context).pop('find'),
          ),
          _Action(
            icon: Icons.bookmark_add_outlined,
            label: 'Save page',
            note: 'Keep the address and title in your library',
            enabled: canSave,
            onTap: () => Navigator.of(context).pop('save'),
          ),
          _Action(
            icon: Icons.add_to_photos_outlined,
            label: 'Add to My Search',
            note: 'Fetch once and add a local text extract',
            enabled: canSave,
            onTap: () => Navigator.of(context).pop('index'),
          ),
          const SiftRule(),
          _Action(
            icon: Icons.ios_share_rounded,
            label: 'Share link',
            onTap: canSave ? () => Navigator.of(context).pop('share') : null,
          ),
          _Action(
            icon: Icons.copy_rounded,
            label: 'Copy link',
            onTap: canSave ? () => Navigator.of(context).pop('copy') : null,
          ),
          _Action(
            icon: Icons.open_in_new_rounded,
            label: 'Open in another app',
            onTap: canSave ? () => Navigator.of(context).pop('external') : null,
          ),
          _Action(
            icon: Icons.refresh_rounded,
            label: 'Reload',
            onTap: canSave ? () => Navigator.of(context).pop('reload') : null,
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    this.note,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? note;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final active = enabled && onTap != null;
    return InkWell(
      onTap: active ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 17, color: active ? p.inkSoft : p.faint),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: active ? p.ink : p.faint,
                        ),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.faint,
                            fontSize: 8,
                            height: 1.5,
                          ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.faint),
          ],
        ),
      ),
    );
  }
}

/// Reader mode is a real local view: it holds the extracted text, never loads
/// the page again, and can add that exact extract to the on-device index.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.url,
    required this.title,
    required this.text,
    super.key,
  });

  final String url;
  final String title;
  final String text;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final SiftServices _services;
  bool _indexing = false;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
  }

  int get _minutes => (widget.text.split(RegExp(r'\s+')).length / 225).ceil();

  Future<void> _save() async {
    await _services.library.saveUrl(
      url: widget.url,
      title: widget.title,
      snippet: truncateText(widget.text, 210),
      source: 'Reader',
    );
    if (mounted) showSiftToast(context, 'Saved to your library.');
  }

  Future<void> _index() async {
    setState(() => _indexing = true);
    try {
      await _services.localIndex.indexText(
        url: widget.url,
        title: widget.title,
        text: widget.text,
      );
      if (mounted) showSiftToast(context, 'Added to My Search.');
    } on LocalIndexException catch (error) {
      if (mounted) showSiftToast(context, error.message, error: true);
    } catch (_) {
      if (mounted) showSiftToast(context, 'Could not index this page.', error: true);
    } finally {
      if (mounted) setState(() => _indexing = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) showSiftToast(context, 'Article text copied.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final paragraphs = widget.text
        .split(RegExp(r'\n{1,}'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: SiftIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back to browser',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Reader',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
        actions: [
          SiftIconButton(
            icon: Icons.copy_rounded,
            tooltip: 'Copy article',
            size: 17,
            onPressed: _copy,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SiftSpace.page,
          8,
          SiftSpace.page,
          48,
        ),
        children: [
          Text(
            widget.title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontSize: 35,
                  height: 1.08,
                ),
          ),
          const SizedBox(height: 9),
          Text(
            '${domainOf(widget.url)} · ${_minutes < 1 ? 1 : _minutes} min read',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.faint,
                  fontSize: 9,
                ),
          ),
          const SizedBox(height: 20),
          const SiftRule(),
          const SizedBox(height: 18),
          for (final paragraph in paragraphs) ...[
            SelectableText(
              paragraph,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: p.inkSoft,
                    height: 1.75,
                    fontSize: 15,
                  ),
            ),
            const SizedBox(height: 13),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: SiftButton(
                  label: 'Save page',
                  icon: Icons.bookmark_add_outlined,
                  tone: SiftButtonTone.line,
                  compact: true,
                  onPressed: _save,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: SiftButton(
                  label: 'Add to My Search',
                  icon: Icons.add_rounded,
                  tone: SiftButtonTone.quiet,
                  compact: true,
                  busy: _indexing,
                  onPressed: _indexing ? null : _index,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
