import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ota/update_service.dart';
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
    _services.updates.addListener(_changed);
    _services.remoteUi.addListener(_changed);
    unawaited(_services.updates.reconcileInstalledVersion());
  }

  @override
  void dispose() {
    _services.updates.removeListener(_changed);
    _services.remoteUi.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _checkedLabel(DateTime? value) {
    if (value == null) return 'Not checked yet';
    final elapsed = DateTime.now().difference(value);
    if (elapsed.inMinutes < 1) return 'Checked just now';
    if (elapsed.inHours < 1) return 'Checked ${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return 'Checked ${elapsed.inHours} h ago';
    return 'Checked ${elapsed.inDays} d ago';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final index = _services.localIndex;
    final updates = _services.updates;
    final remoteUi = _services.remoteUi.config;
    final update = updates.manifest;
    final status = switch (updates.phase) {
      UpdatePhase.checking => 'Checking the release channel…',
      UpdatePhase.upToDate => 'Sift is up to date.',
      UpdatePhase.available => update == null
          ? 'An update is available.'
          : 'Sift ${update.versionName} is available · ${update.sizeLabel}.',
      UpdatePhase.downloading =>
        'Downloading update · ${(updates.progress * 100).round()}%',
      UpdatePhase.downloaded => 'The update is downloaded and ready to install.',
      UpdatePhase.installing => 'Opening the Android installer…',
      UpdatePhase.failed => updates.error ?? 'The update check did not finish.',
      UpdatePhase.idle => 'Checks run once per launch and never block startup.',
    };
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
                child: SiftBadge(
                  updates.installedName,
                  background: p.surfaceRaised,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Private search for Android.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: p.muted,
                ),
          ),
          const SizedBox(height: 26),
          Text(
            'Sift searches public sources and keeps a private index on your phone. '
            'There is no account, ad inventory, recommendation feed, or server-side '
            'profile. Requests go only to the sources you enable, and results are '
            'merged on this device.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: p.inkSoft,
                  height: 1.72,
                ),
          ),
          const SizedBox(height: 22),
          _FactRow(
            icon: Icons.memory_rounded,
            title: 'A Rust core',
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
            title: 'Meta-search, not a crawl',
            body:
                'Maintaining a web-scale independent crawl is not possible inside a '
                'phone app. Sift instead combines ${kSourceCatalog.length} public '
                'providers, clearly named, with local ranking and instant answers.',
          ),
          _FactRow(
            icon: Icons.visibility_off_outlined,
            title: 'Privacy controls',
            body:
                'No analytics SDK ships in the app. Tracking parameters are stripped, '
                'known tracker hosts are filtered, and private browsing starts clean. '
                'The privacy screen states what a network can still see.',
          ),
          const SizedBox(height: 12),
          const SiftRule(),
          const SizedBox(height: 18),
          SiftSectionHead(
            title: 'Software updates',
            bottomPadding: 8,
          ),
          Text(
            'You are on Sift ${updates.installedName} '
            '(build ${updates.installedCode}). ${_checkedLabel(updates.lastChecked)}.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: updates.phase == UpdatePhase.failed
                      ? p.danger
                      : p.inkSoft,
                  height: 1.55,
                ),
          ),
          if (updates.phase == UpdatePhase.downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(SiftRadius.pill),
              child: LinearProgressIndicator(
                value: updates.progress > 0 ? updates.progress : null,
                minHeight: 3,
                backgroundColor: p.line,
                valueColor: AlwaysStoppedAnimation<Color>(p.moss),
              ),
            ),
          ],
          if (updates.phase == UpdatePhase.available ||
              updates.phase == UpdatePhase.failed ||
              updates.phase == UpdatePhase.downloaded) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (updates.phase == UpdatePhase.downloaded)
                  SiftButton(
                    label: 'Install update',
                    icon: Icons.system_update_alt_rounded,
                    compact: true,
                    tone: SiftButtonTone.line,
                    onPressed: updates.installDownloaded,
                  )
                else if (updates.manifest != null)
                  SiftButton(
                    label: 'Download update',
                    icon: Icons.download_rounded,
                    compact: true,
                    tone: SiftButtonTone.line,
                    onPressed: updates.downloadAndInstall,
                  ),
                SiftTextAction(
                  label: updates.checking ? 'Checking…' : 'Check for updates',
                  icon: Icons.refresh_rounded,
                  onTap: updates.checking
                      ? null
                      : () => updates.check(manual: true),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            SiftTextAction(
              label: updates.checking ? 'Checking…' : 'Check for updates',
              icon: Icons.refresh_rounded,
              onTap:
                  updates.checking ? null : () => updates.check(manual: true),
            ),
          ],
          if (updates.phase == UpdatePhase.downloading)
            SiftTextAction(
              label: 'Cancel download',
              icon: null,
              onTap: updates.cancelDownload,
            ),
          const SizedBox(height: 4),
          Text(
            remoteUi.version > 0 && _services.settings.remoteUiEnabled
                ? 'Interface bundle ${remoteUi.version} is active.'
                : 'The built-in interface is active.',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.faint,
                  fontSize: 11,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 20),
          const SiftRule(),
          const SizedBox(height: 18),
          SiftSectionHead(
            title: 'Credits and licenses',
            bottomPadding: 8,
          ),
          Text(
            'Built with Flutter and Dart, flutter_inappwebview, shared_preferences, '
            'the html and xml parsers, url_launcher, and FFI. Text is set in Roboto. '
            'The starter shelf links to Wikipedia and other public references; their '
            'text remains under their own licenses. Full notices are bundled with the app.',
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
            'A standalone, ad-free application. No account, no subscription, and no '
            'paid tier. The source is public.',
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
                  fontSize: 11,
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
              color: p.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
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
