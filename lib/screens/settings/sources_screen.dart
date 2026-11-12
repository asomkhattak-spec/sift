import 'package:flutter/material.dart';

import '../../core/models/search_models.dart';
import '../../core/search/source_catalog.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../widgets/sift_ui.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  late final SiftServices _services;
  late final TextEditingController _searx;
  bool _savingSearx = false;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    _services.settings.addListener(_changed);
    _searx = TextEditingController(text: _services.settings.searxUrl);
  }

  @override
  void dispose() {
    _services.settings.removeListener(_changed);
    _searx.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _verticalLabel(SearchVertical vertical) => switch (vertical) {
        SearchVertical.all => 'All',
        SearchVertical.web => 'Web',
        SearchVertical.images => 'Images',
        SearchVertical.news => 'News',
        SearchVertical.videos => 'Videos',
        SearchVertical.discuss => 'Discuss',
      };

  Future<void> _saveSearx() async {
    final value = _searx.text.trim();
    if (value.isEmpty) {
      _services.settings.searxUrl = '';
      await _services.settings.setSourceEnabled('searx', false);
      if (mounted) showSiftToast(context, 'SearXNG source removed.');
      return;
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      showSiftToast(context, 'Enter a full http(s) address.', error: true);
      return;
    }
    setState(() => _savingSearx = true);
    _services.settings.searxUrl = value.replaceAll(RegExp(r'/+$'), '');
    await _services.settings.setSourceEnabled('searx', true);
    if (mounted) {
      setState(() => _savingSearx = false);
      showSiftToast(context, 'SearXNG instance saved.');
    }
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
          'Search sources',
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
            'Sift is a meta-search: it asks providers you choose, then merges and '
            'ranks their answers on the phone. No single company sees the whole '
            'result set, but each enabled source does receive the query.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.65,
                ),
          ),
          const SizedBox(height: 22),
          for (final source in kSourceCatalog) ...[
            _SourceCard(
              source: source,
              enabled: settings.isSourceEnabled(source.id),
              onChanged: (value) =>
                  settings.setSourceEnabled(source.id, value),
              verticalLabel: _verticalLabel,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          const SiftRule(),
          const SizedBox(height: 20),
          const SiftSectionHead(
            kicker: 'CUSTOM ENDPOINT',
            title: 'Connect your own SearXNG',
            bottomPadding: 8,
          ),
          Text(
            'Sift never ships a public SearXNG instance. Add one you run or '
            'trust; it will receive your queries and can see your network address.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searx,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'https://search.example.org',
              prefixIcon: Icon(Icons.dns_outlined, size: 18),
            ),
            onSubmitted: (_) => _saveSearx(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SiftButton(
                label: 'Save instance',
                icon: Icons.check_rounded,
                compact: true,
                busy: _savingSearx,
                onPressed: _savingSearx ? null : _saveSearx,
              ),
              const SizedBox(width: 10),
              if (settings.searxUrl.isNotEmpty)
                SiftTextAction(
                  label: 'Remove',
                  icon: null,
                  onTap: () {
                    _searx.clear();
                    _saveSearx();
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          _CoverageNote(settings: settings, verticalLabel: _verticalLabel),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.enabled,
    required this.onChanged,
    required this.verticalLabel,
  });

  final SourceDefinition source;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String Function(SearchVertical) verticalLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: enabled ? p.lineStrong : p.line),
        borderRadius: BorderRadius.circular(SiftRadius.sm),
      ),
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            source.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontSize: 14),
                          ),
                        ),
                        if (source.isCustom) ...[
                          const SizedBox(width: 7),
                          SiftBadge(
                            'CUSTOM',
                            background: p.surfaceRaised,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      source.host,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.faint,
                            fontSize: 8.5,
                          ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(value: enabled, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            source.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.55,
                  fontSize: 11.5,
                ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final vertical in source.verticals)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: p.line),
                    borderRadius: BorderRadius.circular(SiftRadius.xs),
                  ),
                  child: Text(
                    verticalLabel(vertical).toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 7.5,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            source.privacyNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.faint,
                  height: 1.5,
                  fontSize: 10.5,
                ),
          ),
        ],
      ),
    );
  }
}

class _CoverageNote extends StatelessWidget {
  const _CoverageNote({required this.settings, required this.verticalLabel});

  final SettingsService settings;
  final String Function(SearchVertical) verticalLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final missing = <SearchVertical>[];
    for (final vertical in [
      SearchVertical.web,
      SearchVertical.images,
      SearchVertical.news,
      SearchVertical.videos,
      SearchVertical.discuss,
    ]) {
      final covered = kSourceCatalog.any(
        (source) =>
            source.verticals.contains(vertical) &&
            settings.isSourceEnabled(source.id),
      );
      if (!covered) missing.add(vertical);
    }
    if (missing.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 16, color: p.moss),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Every vertical currently has at least one source. Fewer sources '
              'means more privacy and less coverage; that is the trade you are making.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.muted,
                    height: 1.55,
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: p.clay),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'No enabled source covers ${missing.map(verticalLabel).join(', ')}. '
            'Those tabs will fall back to local results or an empty state until '
            'you enable a provider or add SearXNG.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.55,
                  fontSize: 11,
                ),
          ),
        ),
      ],
    );
  }
}
