import 'package:flutter/material.dart';

import '../../core/search/source_catalog.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/sift_ui.dart';
import 'legal_screen.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final SiftServices _services;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _services.settings.addListener(_changed);
    _services.library.addListener(_changed);
  }

  @override
  void dispose() {
    _services.settings.removeListener(_changed);
    _services.library.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _confirm(String title, String body, String action) async {
    final confirmed = await showSiftSheet<bool>(
      context,
      builder: (_) => _ConfirmSheet(title: title, body: body, action: action),
    );
    if (confirmed != true) return;
    if (action.startsWith('Clear index')) {
      await _services.localIndex.clearCustomDocuments();
    } else if (action.startsWith('Clear history')) {
      await _services.library.clearHistory();
    } else {
      await _services.library.clearSaved();
      await _services.library.clearNotes();
      await _services.library.clearHistory();
      await _services.localIndex.clearCustomDocuments();
    }
    if (mounted) showSiftToast(context, 'Done. The local data is gone.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final settings = _services.settings;
    final activeSources = kSourceCatalog
        .where((source) => settings.isSourceEnabled(source.id))
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
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Privacy',
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
          Text(
            'Sift is private by construction, not by promise. It has no account, '
            'no telemetry, and no advertising code. Search still requires a network '
            'request, and a website you open still learns that your phone visited it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: p.inkSoft,
                  height: 1.65,
                ),
          ),
          const SizedBox(height: 22),
          _Callout(
            title: 'What “fully untraceable” would require',
            body:
                'A search app alone cannot guarantee anonymity. Your mobile carrier, '
                'Wi-Fi operator, and the destination servers can observe connections; '
                'browser fingerprinting can link sessions; a proxy only moves who sees '
                'the request. Sift reduces account-based and app-level tracking and '
                'gives you a real proxy option. It does not claim to defeat a network '
                'observer or a determined fingerprinting site.',
          ),
          const SizedBox(height: 25),
          const SiftSectionHead(
            kicker: 'WHAT LEAVES THE PHONE',
            title: 'Only the query you send',
            bottomPadding: 8,
          ),
          _DataRow(
            icon: Icons.cloud_upload_outlined,
            title: 'A search query',
            body: activeSources.isEmpty
                ? 'No network source is currently enabled. Web search will use local results only.'
                : 'Sent to ${pluralize(activeSources.length, 'enabled source')}: ${activeSources.map((source) => source.shortName).join(', ')}.',
          ),
          _DataRow(
            icon: Icons.article_outlined,
            title: 'A page you choose to index',
            body:
                'Fetched once, stripped to readable text, and stored locally. It is not sent to Sift or any other server.',
          ),
          _DataRow(
            icon: Icons.image_outlined,
            title: 'Images and video',
            body:
                'Thumbnails load from the image or video host. Opening a result contacts that site directly, with its own cookies and policy.',
          ),
          _DataRow(
            icon: Icons.ads_click_outlined,
            title: 'Advertising and analytics',
            body:
                'None from Sift. Known tracker hosts are filtered out of in-app page requests by default; sites can still track you server-side.',
          ),
          const SizedBox(height: 25),
          const SiftSectionHead(
            kicker: 'CONTROLS',
            title: 'Reduce what is retained',
            bottomPadding: 8,
          ),
          _Toggle(
            label: 'Private browsing',
            description: 'No saved cookies or in-app browsing history by default.',
            value: settings.privateBrowsing,
            onChanged: (value) => settings.privateBrowsing = value,
          ),
          _Toggle(
            label: 'Remember activity',
            description:
                'Keep a local list of queries and opened pages. Off by default; clearing it is always one tap away.',
            value: settings.rememberActivity,
            onChanged: (value) => settings.rememberActivity = value,
          ),
          _Toggle(
            label: 'Block known trackers',
            description:
                'Cancel requests to a bundled host list. This raises the cost of casual tracking; it does not stop first-party analytics.',
            value: settings.blockTrackers,
            onChanged: (value) => settings.blockTrackers = value,
          ),
          _Toggle(
            label: 'Allow third-party cookies',
            description:
                'Off by default. Turning it on may fix some logins and re-enables cross-site tracking.',
            value: settings.thirdPartyCookies,
            onChanged: (value) => settings.thirdPartyCookies = value,
          ),
          _Toggle(
            label: 'Strip tracking parameters',
            description:
                'Remove utm_*, fbclid, gclid and similar tags from links before opening.',
            value: settings.stripTrackingParams,
            onChanged: (value) => settings.stripTrackingParams = value,
          ),
          _Toggle(
            label: 'Hide the app preview',
            description:
                'Blur Sift in the Android app switcher. This is shoulder-surfing protection, not encryption.',
            value: settings.secureScreen,
            onChanged: (value) => settings.secureScreen = value,
          ),
          const SizedBox(height: 24),
          const SiftSectionHead(
            kicker: 'YOUR LOCAL RECORD',
            title: 'Inspect and erase',
            bottomPadding: 8,
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.sm),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'History entries',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '${_services.library.history.length}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: p.mossDeep,
                            ),
                      ),
                    ],
                  ),
                ),
                const SiftRule(),
                _ClearRow(
                  label: 'Clear search history',
                  onTap: () => _confirm(
                    'Clear history?',
                    'Recent queries and opened pages will be removed from this phone.',
                    'Clear history',
                  ),
                ),
                const SiftRule(),
                _ClearRow(
                  label: 'Clear the custom index',
                  onTap: () => _confirm(
                    'Clear indexed pages?',
                    'The ${_services.localIndex.customCount} pages you added to My Search will be removed. The starter shelf is not affected.',
                    'Clear index',
                  ),
                ),
                const SiftRule(),
                _ClearRow(
                  label: 'Clear everything local',
                  onTap: () => _confirm(
                    'Clear all local data?',
                    'Saved pages, notes, history, and indexed pages will be erased. Settings and source choices remain.',
                    'Clear everything',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.eco_outlined, size: 16, color: p.moss),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Network activity was ${settings.rememberActivity ? 'recorded locally' : 'not recorded'} '
                  'as of ${timeOfDayLabel(DateTime.now())}. Sift has no server to send it to.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.faint,
                        height: 1.55,
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SiftButton(
            label: 'Read the full privacy policy',
            icon: Icons.open_in_new_rounded,
            tone: SiftButtonTone.line,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalScreen.asset(
                  title: 'Privacy policy',
                  asset: 'assets/legal/privacy.md',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: p.mossWash,
        border: Border(
          left: BorderSide(color: p.moss, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: p.mossDeep,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.mossDeep.withOpacity(0.86),
                  height: 1.6,
                ),
          ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: p.clay),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.muted,
                        height: 1.6,
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

class _Toggle extends StatelessWidget {
  const _Toggle({
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
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
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _ClearRow extends StatelessWidget {
  const _ClearRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

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
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: p.danger,
                    ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 17, color: p.faint),
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
