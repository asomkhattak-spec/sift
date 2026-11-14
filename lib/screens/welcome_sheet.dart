import 'package:flutter/material.dart';

import '../core/theme/sift_theme.dart';
import '../widgets/sift_ui.dart';

enum WelcomeAction { search, privacy }

class WelcomeSheet extends StatelessWidget {
  const WelcomeSheet({super.key});

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
            title: 'A quieter way to look.',
            subtitle:
                'Sift asks several independent sources at once and ranks what '
                'comes back on this phone.',
          ),
          const SizedBox(height: 22),
          const _WelcomePrinciple(
            index: '01',
            title: 'The ranking is local',
            body:
                'Your query is scored by a small Rust engine bundled with the '
                'app. There is no account and no advertising profile.',
          ),
          const _WelcomePrinciple(
            index: '02',
            title: 'You choose the sources',
            body:
                'Turn providers on or off, bring your own SearXNG instance, or '
                'search only the private index you build yourself.',
          ),
          const _WelcomePrinciple(
            index: '03',
            title: 'The browser has limits',
            body:
                'Private sessions, tracker blocking, third-party cookies off, '
                'and known tracking parameters stripped before a page opens.',
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: p.clayWash,
              border: Border.all(color: p.clay.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(SiftRadius.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: p.clay),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'No app can make your network traffic anonymous on its own. '
                    'For that threat model, route Sift through a VPN you trust '
                    'or Orbot using the proxy setting.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.inkSoft,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SiftButton(
            label: 'Start searching',
            icon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () => Navigator.of(context).pop(WelcomeAction.search),
          ),
          const SizedBox(height: 4),
          Center(
            child: SiftTextAction(
              label: 'Read the privacy note',
              icon: null,
              onTap: () => Navigator.of(context).pop(WelcomeAction.privacy),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomePrinciple extends StatelessWidget {
  const _WelcomePrinciple({
    required this.index,
    required this.title,
    required this.body,
  });

  final String index;
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
          SizedBox(
            width: 30,
            child: Text(
              index,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: p.clay,
                    fontSize: 11.5,
                    height: 1.7,
                    letterSpacing: 0.6,
                  ),
            ),
          ),
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
                        height: 1.5,
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
