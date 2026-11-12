import 'package:flutter/material.dart';

import '../../core/search/source_catalog.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../widgets/sift_ui.dart';
import 'legal_screen.dart';
import 'privacy_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final SiftServices _services;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final index = _services.localIndex;
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
          'About',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SiftSpace.page,
          10,
          SiftSpace.page,
          44,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Sift',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 54,
                      height: 0.9,
                    ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SiftBadge('1.0.0', background: p.surfaceRaised),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A quiet search engine for a phone.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: p.muted,
                  fontStyle: FontStyle.italic,
                ),
          ),
          const SizedBox(height: 26),
          Text(
            'Sift began with a simple constraint: a search app should be a tool, '
            'not a feed. There is no account, no advertising inventory, no '
            'recommendation engine, and no reason for the app to know who you are. '
            'It asks several independent sources, merges their answers on this phone, '
            'and leaves a small local index you control.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: p.inkSoft,
                  height: 1.72,
                ),
          ),
          const SizedBox(height: 22),
          _FactRow(
            icon: Icons.memory_rounded,
            title: 'The difficult core is Rust',
            body:
                'Query planning, normalization, URL cleanup, reciprocal-rank fusion, '
                'and BM25 scoring run in a small native library when the build ships it. '
                'Dart falls back to equivalent logic when the library is absent.',
          ),
          _FactRow(
            icon: Icons.phone_android_rounded,
            title: 'On-device by default',
            body:
                'My Search indexes a compact extract of pages you add. The index is '
                '${index.customCount} custom pages plus ${index.starterCount} curated '
                'shelf entries, and it never leaves the sandbox.',
          ),
          _FactRow(
            icon: Icons.hub_outlined,
            title: 'A meta-search, not a crawl',
            body:
                'Maintaining a web-scale independent crawl is not possible inside a '
                'phone app. Sift instead combines ${kSourceCatalog.length} public '
                'providers, clearly named, with local ranking and instant answers.',
          ),
          _FactRow(
            icon: Icons.visibility_off_outlined,
            title: 'Privacy is a discipline',
            body:
                'No analytics SDK ships in the app. Tracking parameters are stripped, '
                'known tracker hosts are filtered, and private browsing starts clean. '
                'The privacy screen states what a network can still see.',
          ),
          const SizedBox(height: 12),
          const SiftRule(),
          const SizedBox(height: 18),
          SiftSectionHead(
            kicker: 'OPEN SOURCE',
            title: 'Standing on good work',
            bottomPadding: 8,
          ),
          Text(
            'Sift uses Flutter and Dart, flutter_inappwebview, shared_preferences, '
            'the html and xml parsers, url_launcher, and FFI. Type is set in '
            'Instrument Serif by Smythe and IBM Plex by IBM. The starter shelf links '
            'to Wikipedia and other public references; their text remains under their '
            'own licenses. Full notices are bundled with the app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.65,
                ),
          ),
          const SizedBox(height: 18),
          SiftButton(
            label: 'Open-source licenses',
            icon: Icons.description_outlined,
            tone: SiftButtonTone.line,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LegalScreen.asset(
                  title: 'Licenses',
                  asset: 'assets/legal/licenses.md',
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SiftButton(
            label: 'Privacy dashboard',
            icon: Icons.shield_outlined,
            tone: SiftButtonTone.line,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacyScreen(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const SiftRule(),
          const SizedBox(height: 16),
          Text(
            'Built as a standalone, ad-free application. No account, no subscription, '
            'no “upgrade to remove ads.” If you find a bug, the source is public.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.faint,
                  height: 1.6,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Package io.github.asomkhattak.sift',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.faint,
                  fontSize: 8,
                ),
          ),
        ],
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
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
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: p.lineStrong),
              borderRadius: BorderRadius.circular(SiftRadius.xs),
            ),
            child: Icon(icon, size: 16, color: p.mossDeep),
          ),
          const SizedBox(width: 12),
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
