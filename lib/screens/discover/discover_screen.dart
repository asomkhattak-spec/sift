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
                      title: 'Discover',
                      subtitle:
                          'Top stories and images for ${longDate(DateTime.now())}, '
                          'gathered from the sources you keep enabled.',
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
                          title: 'Top stories',
                          action: 'Search news',
                          onAction: () => startSiftSearch(
                            context,
                            'world news today',
                          ),
                        ),
                        for (var i = 0; i < feed.stories.length; i++) ...[
                          _StoryRow(
                            result: feed.stories[i],
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
                          title: 'In pictures',
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
                        const SiftSectionHead(
                          title: 'From My Search',
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
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final source = result.host.isEmpty ? 'Sift' : result.host;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.surfaceRaised,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                firstLetter(source),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: p.mossDeep,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: p.ink,
                          height: 1.35,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
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
                            height: 1.5,
                            fontSize: 13,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: p.muted,
                                fontSize: 12,
                              ),
                        ),
                      ),
                      if (result.publishedAt != null) ...[
                        Text(
                          '  ·  ',
                          style: TextStyle(color: p.faint, fontSize: 11),
                        ),
                        Text(
                          relativeDate(result.publishedAt),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: p.faint,
                                    fontSize: 12,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
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
                        borderRadius: BorderRadius.circular(12),
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
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: p.inkSoft,
                          height: 1.35,
                          fontSize: 12,
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
                color: p.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                firstLetter(document.title),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: p.mossDeep,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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
            ? 'One source could not be reached. Showing the rest of this edition.'
            : '${errors.length} sources could not be reached. Showing the rest of this edition.',
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
        Icon(Icons.lock_outline_rounded, size: 14, color: p.faint),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Built on this phone from ${pluralize(active, 'enabled source')}. '
            '${loadedAt == null ? 'Pull down to refresh.' : 'Updated at ${timeOfDayLabel(loadedAt!)}.'} '
            'No ads or sponsored placement.',
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
