import 'package:flutter/material.dart';

import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../widgets/sift_ui.dart';
import '../my_search/my_search_screen.dart';
import 'about_screen.dart';
import 'legal_screen.dart';
import 'privacy_screen.dart';
import 'sources_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SiftServices _services;
  late final TextEditingController _proxyHost;
  late final TextEditingController _proxyPort;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _services.settings.addListener(_changed);
    _proxyHost = TextEditingController(text: _services.settings.proxyHost);
    _proxyPort = TextEditingController(
      text: _services.settings.proxyPort.toString(),
    );
  }

  @override
  void dispose() {
    _services.settings.removeListener(_changed);
    _proxyHost.dispose();
    _proxyPort.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _clearLocalData() async {
    final confirmed = await showSiftSheet<bool>(
      context,
      builder: (_) => const _ConfirmSheet(
        title: 'Clear local data?',
        body:
            'Saved pages, notes, history, and pages you added to My Search will '
            'be removed from this phone. Settings and enabled sources stay as they are.',
        action: 'Clear local data',
      ),
    );
    if (confirmed != true) return;
    final library = _services.library;
    await library.clearSaved();
    await library.clearNotes();
    await library.clearHistory();
    await _services.localIndex.clearCustomDocuments();
    if (mounted) showSiftToast(context, 'Local library cleared.');
  }

  void _applyProxy() {
    final port = int.tryParse(_proxyPort.text.trim());
    if (port == null || port < 1 || port > 65535) {
      showSiftToast(context, 'A proxy port must be between 1 and 65535.', error: true);
      return;
    }
    _services.settings.proxyHost = _proxyHost.text.trim();
    _services.settings.proxyPort = port;
    showSiftToast(context, 'Proxy address saved.');
  }

  void _setTheme(String mode) {
    _services.settings.themeMode = mode;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final settings = _services.settings;
    return Scaffold(
      backgroundColor: p.paper,
      appBar: AppBar(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: SiftIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SiftSpace.page,
          8,
          SiftSpace.page,
          44,
        ),
        children: [
          _Preamble(),
          const SizedBox(height: 22),
          _Section(
            kicker: 'APPEARANCE',
            title: 'A reading surface',
            children: [
              _ChoiceSetting(
                label: 'Theme',
                description: 'System follows your phone. Paper is the warm light theme; ink is the dark one.',
                value: settings.themeMode,
                options: const [
                  ('system', 'System'),
                  ('light', 'Paper'),
                  ('dark', 'Ink'),
                ],
                onChanged: _setTheme,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Serif headlines',
                description: 'Instrument Serif for display type, with IBM Plex Sans for reading.',
                value: settings.serifHeadings,
                onChanged: (value) => settings.serifHeadings = value,
              ),
              const SiftRule(),
              _SliderSetting(
                label: 'Text size',
                description:
                    'Scales the whole interface. Small text stays legible at the bottom of the range.',
                value: settings.textScale,
                min: 0.9,
                max: 1.25,
                divisions: 7,
                label2: '${(settings.textScale * 100).round()}%',
                onChanged: (value) => settings.textScale = value,
              ),
            ],
          ),
          _Section(
            kicker: 'SEARCH',
            title: 'How results are assembled',
            children: [
              _SwitchSetting(
                label: 'Safe search',
                description:
                    'Requests a conservative filter from sources that support it. It is a preference, not a guarantee.',
                value: settings.safeSearch,
                onChanged: (value) => settings.safeSearch = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Search suggestions',
                description:
                    'Ask Bing for query completions while typing. Turn this off to keep every keystroke local.',
                value: settings.suggestionsEnabled,
                onChanged: (value) => settings.suggestionsEnabled = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Instant answers',
                description:
                    'Local calculations, dates, units, and a few public reference lookups shown above results.',
                value: settings.instantAnswers,
                onChanged: (value) => settings.instantAnswers = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Starter shelf in My Search',
                description:
                    'Include 64 curated reference summaries alongside pages you index yourself.',
                value: settings.starterIndexEnabled,
                onChanged: (value) => settings.starterIndexEnabled = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'On-device only',
                description:
                    'Send no query to any web source. Search Sift Local and '
                    'locally computed answers. Instant answers that need the '
                    'network are skipped.',
                value: settings.localOnlyMode,
                onChanged: (value) => settings.localOnlyMode = value,
              ),
              const SiftRule(),
              _CountSetting(
                label: 'Results per page',
                description:
                    'Fewer results are lighter on mobile data. Paging still asks the source for more.',
                value: settings.resultCount,
                onChanged: (value) => settings.resultCount = value,
              ),
              const SiftRule(),
              _NavSetting(
                label: 'Search sources',
                description:
                    'Choose which providers can receive a query, and configure a SearXNG instance.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SourcesScreen(),
                  ),
                ),
              ),
            ],
          ),
          _Section(
            kicker: 'BROWSER',
            title: 'Pages, links, and watching',
            children: [
              _SwitchSetting(
                label: 'Open results inside Sift',
                description:
                    'Use the built-in browser with tabs and reader mode. Turn off to hand every link to your default browser.',
                value: settings.openInApp,
                onChanged: (value) => settings.openInApp = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Private browsing',
                description:
                    'Start reading sessions without saved cookies or browsing history inside Sift. Downloading and external sites still see your network address.',
                value: settings.privateBrowsing,
                onChanged: (value) => settings.privateBrowsing = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Block known trackers',
                description:
                    'Cancel requests to a bundled list of analytics and advertising hosts. This is a filter, not a cloak.',
                value: settings.blockTrackers,
                onChanged: (value) => settings.blockTrackers = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Allow third-party cookies',
                description:
                    'Off by default. Some sign-in flows need it; leaving it off breaks cross-site tracking.',
                value: settings.thirdPartyCookies,
                onChanged: (value) => settings.thirdPartyCookies = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Strip tracking parameters',
                description:
                    'Remove utm_*, fbclid, gclid and similar campaign tags before opening a result.',
                value: settings.stripTrackingParams,
                onChanged: (value) => settings.stripTrackingParams = value,
              ),
              const SiftRule(),
              _SwitchSetting(
                label: 'Hide Sift in the app switcher',
                description:
                    'Blur the app preview on Android. Useful on a shared phone, not a substitute for a screen lock.',
                value: settings.secureScreen,
                onChanged: (value) => settings.secureScreen = value,
              ),
            ],
          ),
          _Section(
            kicker: 'NETWORK',
            title: 'Optional routing',
            children: [
              _SwitchSetting(
                label: 'Route through a proxy',
                description:
                    'Send Sift’s HTTP requests and WebView traffic through an HTTP proxy you trust, such as Orbot on 127.0.0.1:8118. Without a trusted proxy and network hygiene, this does not make you anonymous.',
                value: settings.proxyEnabled,
                onChanged: (value) => settings.proxyEnabled = value,
              ),
              const SiftRule(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _proxyHost,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Proxy host',
                          hintText: '127.0.0.1',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 106,
                      child: TextField(
                        controller: _proxyPort,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '8118',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _applyProxy(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SiftIconButton(
                      icon: Icons.check_rounded,
                      tooltip: 'Save proxy address',
                      onPressed: _applyProxy,
                    ),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            kicker: 'PRIVACY',
            title: 'What this app can and cannot do',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Sift has no account, no advertising SDK, no analytics, and no '
                  'remote sync. Your index and library are local files. Search still '
                  'contacts the sources you enable, and ordinary web pages still see '
                  'your network address. Private search is not the same as anonymity.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.muted,
                        height: 1.65,
                      ),
                ),
              ),
              _NavSetting(
                label: 'Open the privacy dashboard',
                description:
                    'Every network path, retention choice, and honest limitation in one place.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyScreen(),
                  ),
                ),
              ),
              const SiftRule(),
              _NavSetting(
                label: 'Open My Search',
                description:
                    'See what the on-device index holds, or clear the pages you added.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MySearchScreen(showBack: true),
                  ),
                ),
              ),
              const SiftRule(),
              _NavSetting(
                label: 'Clear local data',
                description:
                    'Remove saved pages, notes, history, and your custom index. This cannot be undone.',
                onTap: _clearLocalData,
                destructive: true,
              ),
            ],
          ),
          _Section(
            kicker: 'ABOUT',
            title: 'A small, finished thing',
            children: [
              _NavSetting(
                label: 'About Sift',
                description:
                    'The idea, the Rust core, open-source credits, and the version.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AboutScreen(),
                  ),
                ),
              ),
              const SiftRule(),
              _NavSetting(
                label: 'Privacy policy',
                description: 'Plain-language policy. No dark patterns.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LegalScreen.asset(
                      title: 'Privacy policy',
                      asset: 'assets/legal/privacy.md',
                    ),
                  ),
                ),
              ),
              const SiftRule(),
              _NavSetting(
                label: 'Terms of use',
                description: 'What Sift promises, and what it does not.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LegalScreen.asset(
                      title: 'Terms of use',
                      asset: 'assets/legal/terms.md',
                    ),
                  ),
                ),
              ),
              const SiftRule(),
              _NavSetting(
                label: 'Open-source licenses',
                description:
                    'The fonts, packages, and data sources that make this app possible.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LegalScreen.asset(
                      title: 'Licenses',
                      asset: 'assets/legal/licenses.md',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Preamble extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Text(
      'Defaults are chosen to keep less data, not to hide what leaves the phone. '
      'Every switch describes its actual effect.',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: p.faint,
            height: 1.6,
          ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.kicker,
    required this.title,
    required this.children,
  });

  final String kicker;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSectionHead(
            kicker: kicker,
            title: title,
            bottomPadding: 9,
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.sm),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          height: 1.55,
                          fontSize: 11.5,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Switch.adaptive(
                value: value,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceSetting extends StatelessWidget {
  const _ChoiceSetting({
    required this.label,
    required this.description,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String description;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.55,
                  fontSize: 11.5,
                ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in options)
                InkWell(
                  onTap: () => onChanged(option.$1),
                  borderRadius: BorderRadius.circular(SiftRadius.xs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: value == option.$1 ? p.mossDeep : p.surfaceRaised,
                      border: Border.all(
                        color: value == option.$1 ? p.mossDeep : p.lineStrong,
                      ),
                      borderRadius: BorderRadius.circular(SiftRadius.xs),
                    ),
                    child: Text(
                      option.$2,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: value == option.$1 ? p.paper : p.inkSoft,
                            fontSize: 9.5,
                          ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label2,
    required this.onChanged,
  });

  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label2;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                label2,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.mossDeep,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.55,
                  fontSize: 11.5,
                ),
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: label2,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _CountSetting extends StatelessWidget {
  const _CountSetting({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.muted,
                        height: 1.55,
                        fontSize: 11.5,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SiftIconButton(
            icon: Icons.remove_rounded,
            tooltip: 'Fewer results',
            onPressed: value > 10 ? () => onChanged(value - 5) : null,
            size: 15,
          ),
          SizedBox(
            width: 22,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: p.mossDeep,
                  ),
            ),
          ),
          SiftIconButton(
            icon: Icons.add_rounded,
            tooltip: 'More results',
            onPressed: value < 30 ? () => onChanged(value + 5) : null,
            size: 15,
          ),
        ],
      ),
    );
  }
}

class _NavSetting extends StatelessWidget {
  const _NavSetting({
    required this.label,
    required this.description,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final String description;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: destructive ? p.danger : null,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          height: 1.55,
                          fontSize: 11.5,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: destructive ? p.danger : p.faint,
            ),
          ],
        ),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSheetTitle(title: title, subtitle: body),
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
