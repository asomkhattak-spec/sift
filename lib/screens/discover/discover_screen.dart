import 'package:flutter/material.dart';

import '../../core/models/search_models.dart';
import '../../core/search/local_index.dart';
import '../../core/search/search_engine.dart';
import '../../core/services/sift_scope.dart';
import '../../core/theme/sift_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/navigation.dart';
import '../../core/utils/text_utils.dart';
import '../../widgets/result_widgets.dart';
import '../../widgets/sift_ui.dart';

/// A deliberately small daily edition: a handful of stories, a visual pause,
/// and a route back into the local shelf. It is not an algorithmic feed.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => DiscoverScreenState();
}

class DiscoverScreenState extends State<DiscoverScreen> {
  late final SiftServices _services;
  DiscoverFeed? _feed;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _services = SiftScope.readServicesOf(context);
    refresh();
  }

  Future<void> refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final feed = await _services.engine.discover();
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _error = feed.isEmpty && feed.errors.isNotEmpty ? feed.errors.first : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _open(SearchResult result) async {
    await _services.library.recordQuery(result.title, openedUrl: result.url);
    if (!mounted) return;
    await openSiftUrl(context, result.url, title: result.title);
  }

  Future<void> _openShelf(LocalDocument document) async {
    if (document.url.isEmpty) {
      startSiftSearch(context, document.title);
      return;
    }
    await openSiftUrl(context, document.url, title: document.title);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final feed = _feed;
    return Scaffold(
      backgroundColor: p.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: p.moss,
          backgroundColor: p.surface,
          onRefresh: refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  SiftSpace.page,
                  20,
                  SiftSpace.page,
                  0,
                ),
                sliver: SliverList.list(
                  children: [
                    SiftPageTitle(
                      kicker: 'THE OPEN WEB, EDITED',
                      title: greetingFor(DateTime.now()),
                      subtitle:
                          'A short, human-scale edition for ${longDate(DateTime.now())}. '
                          'No feed algorithm, no autoplay, no advertising.',
                      actions: [
                        SiftIconButton(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Refresh edition',
                          onPressed: _loading ? null : refresh,
                        ),
                      ],
                      bottom: 18,
                    ),
                    if (_loading && feed == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: SiftSkeletonRows(rows: 5),
                      )
                    else ...[
                      if (_error != null)
                        SiftErrorNote(message: _error!, onRetry: refresh),
                      if (feed != null && feed.errors.isNotEmpty && _error == null)
                        _PartialNote(errors: feed.errors),
                    ],
                  ],
                ),
              ),
              if (!_loading || feed != null) ...[
                if (feed != null && feed.stories.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SiftSpace.page,
                      18,
                      SiftSpace.page,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        SiftSectionHead(
                          kicker: 'CURRENT',
                          title: 'Worth your attention',
                          action: 'Search news',
                          onAction: () => startSiftSearch(
                            context,
                            'world news today',
                          ),
                        ),
                        for (var i = 0; i < feed.stories.length; i++) ...[
                          _StoryRow(
                            result: feed.stories[i],
                            index: i + 1,
                            onTap: () => _open(feed.stories[i]),
                          ),
                          if (i != feed.stories.length - 1) const SiftRule(),
                        ],
                      ],
                    ),
                  ),
                if (feed != null && feed.images.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SiftSpace.page,
                      34,
                      SiftSpace.page,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        SiftSectionHead(
                          kicker: 'A MOMENT OF LOOKING',
                          title: 'The visual world',
                          action: 'Open images',
                          onAction: () => startSiftSearch(
                            context,
                            'architecture in morning light',
                          ),
                        ),
                        _ImageBand(results: feed.images),
                      ],
                    ),
                  ),
                if (feed != null && feed.shelf.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      SiftSpace.page,
                      34,
                      SiftSpace.page,
                      0,
                    ),
                    sliver: SliverList.list(
                      children: [
                        SiftSectionHead(
                          kicker: 'FROM MY SEARCH',
                          title: 'A shelf of starting points',
                          action: 'Open My Search',
                          onAction: () => startSiftSearch(
                            context,
                            feed.shelf.first.title,
                          ),
                        ),
                        for (final document
                            in feed.shelf.take(4).toList()) ...[
                          _ShelfRow(
                            document: document,
                            onTap: () => _openShelf(document),
                          ),
                          const SiftRule(),
                        ],
                      ],
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    SiftSpace.page,
                    34,
                    SiftSpace.page,
                    36,
                  ),
                  sliver: SliverList.list(
                    children: [
                      const SiftRule(),
                      const SizedBox(height: 18),
                      _Colophon(
                        loadedAt: feed?.loadedAt,
                        sources: _services.settings.isSourceEnabled,
                      ),
                    ],
                  ),
                ),
              ] else
                const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.result,
    required this.index,
    required this.onTap,
  });

  final SearchResult result;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 27,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.clay,
                      fontSize: 9.5,
                    ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          height: 1.3,
                          fontSize: 16.5,
                        ),
                  ),
                  if (result.snippet.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      truncateText(result.snippet, 190),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.muted,
                            height: 1.55,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        result.host.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: p.mossDeep,
                              fontSize: 9,
                            ),
                      ),
                      if (result.publishedAt != null) ...[
                        Text(
                          '  ·  ',
                          style: TextStyle(color: p.faint, fontSize: 9),
                        ),
                        Text(
                          relativeDate(result.publishedAt),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: p.faint,
                                    fontSize: 9,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.north_east_rounded, size: 15, color: p.faint),
          ],
        ),
      ),
    );
  }
}

class _ImageBand extends StatelessWidget {
  const _ImageBand({required this.results});

  final List<SearchResult> results;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final items = results.take(4).toList();
    return SizedBox(
      height: 174,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final result = items[index];
          final image = result.thumbnailUrl ?? result.imageUrl;
          return SizedBox(
            width: index == 0 ? 196 : 144,
            child: InkWell(
              onTap: () => showImagePreview(context, result),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: p.surfaceRaised,
                        border: Border.all(color: p.line),
                        borderRadius: BorderRadius.circular(SiftRadius.xs),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: image == null
                          ? Center(
                              child: Icon(
                                Icons.landscape_outlined,
                                color: p.faint,
                                size: 26,
                              ),
                            )
                          : Image.network(
                              image,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: p.faint,
                                  size: 24,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    truncateText(result.title, 54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.inkSoft,
                          height: 1.35,
                          letterSpacing: 0.1,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.document, required this.onTap});

  final LocalDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: p.lineStrong),
                borderRadius: BorderRadius.circular(SiftRadius.xs),
              ),
              child: Text(
                firstLetter(document.title),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: p.clay,
                      height: 1,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    truncateText(document.snippet, 90),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SiftBadge(document.section, background: p.surfaceRaised),
          ],
        ),
      ),
    );
  }
}

class _PartialNote extends StatelessWidget {
  const _PartialNote({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SiftErrorNote(
        message: errors.length == 1
            ? 'One source was unavailable. The rest of this edition is intact.'
            : '${errors.length} sources were unavailable. The rest of this edition is intact.',
      ),
    );
  }
}

class _Colophon extends StatelessWidget {
  const _Colophon({
    required this.loadedAt,
    required this.sources,
  });

  final DateTime? loadedAt;
  final bool Function(String) sources;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final active = ['wikipedia', 'openverse', 'gnews', 'bing']
        .where(sources)
        .length;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.eco_outlined, size: 15, color: p.moss),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Assembled on your phone from ${pluralize(active, 'chosen source')}. '
            '${loadedAt == null ? 'Pull down to refresh.' : 'Last edited ${timeOfDayLabel(loadedAt!)}.'} '
            'Nothing here is sponsored or ranked by an advertiser.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.faint,
                  height: 1.55,
                  fontSize: 11,
                ),
          ),
        ),
      ],
    );
  }
}
