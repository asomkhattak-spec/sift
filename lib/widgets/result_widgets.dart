import 'package:flutter/material.dart';

import '../core/models/search_models.dart';
import '../core/services/sift_scope.dart';
import '../core/theme/sift_theme.dart';
import '../core/utils/formatters.dart';
import '../core/utils/navigation.dart';
import 'sift_ui.dart';

class WebResultTile extends StatelessWidget {
  const WebResultTile({
    required this.result,
    this.onTap,
    this.onLongPress,
    this.dense = false,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final saved = SiftScope.maybeServicesOf(context)?.library.isSaved(result.url) ??
        false;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 13 : 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: p.mossDeep,
                                    fontSize: 9.5,
                                    letterSpacing: 0.5,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        width: 2,
                        height: 2,
                        color: p.faint,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        result.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: p.faint,
                                  fontSize: 9,
                                  letterSpacing: 0.25,
                                ),
                      ),
                      if (saved) ...[
                        const SizedBox(width: 7),
                        Icon(
                          Icons.bookmark_rounded,
                          size: 11,
                          color: p.clay,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.title.isEmpty ? result.displayUrl : result.title,
                    maxLines: dense ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: dense ? 16 : 17,
                          height: 1.28,
                          color: p.ink,
                        ),
                  ),
                  if (result.snippet.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      result.snippet,
                      maxLines: dense ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.muted,
                            height: 1.52,
                            fontSize: 12.5,
                          ),
                    ),
                  ],
                  if (_metaLine(result).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _metaLine(result),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.faint,
                            fontSize: 9,
                            letterSpacing: 0.25,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (result.thumbnailUrl != null &&
                result.thumbnailUrl!.isNotEmpty) ...[
              const SizedBox(width: 14),
              _Thumb(url: result.thumbnailUrl!, width: 82, height: 66),
            ],
          ],
        ),
      ),
    );
  }
}

class NewsResultTile extends StatelessWidget {
  const NewsResultTile({
    required this.result,
    this.onTap,
    this.onLongPress,
    this.lead = false,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool lead;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final publisher = result.meta['publisher']?.toString();
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  (publisher == null || publisher.isEmpty
                          ? result.host
                          : publisher)
                      .toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.clay,
                        fontSize: 9,
                        letterSpacing: 0.7,
                      ),
                ),
                if (result.publishedAt != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    relativeDate(result.publishedAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 9,
                        ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    result.title,
                    maxLines: lead ? 4 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: lead ? 22 : 16.5,
                          height: 1.26,
                          color: p.ink,
                        ),
                  ),
                ),
                if (result.thumbnailUrl != null &&
                    result.thumbnailUrl!.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  _Thumb(url: result.thumbnailUrl!, width: 86, height: 66),
                ],
              ],
            ),
            if (lead && result.snippet.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                result.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.muted,
                      height: 1.52,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DiscussionResultTile extends StatelessWidget {
  const DiscussionResultTile({
    required this.result,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final points = result.meta['points'];
    final comments = result.meta['comments'];
    final answers = result.meta['answers'];
    final stats = <String>[
      if (points != null) '$points points',
      if (comments != null) '$comments comments',
      if (answers != null) '$answers answers',
      if (result.meta['tags'] != null) result.meta['tags'].toString(),
    ];
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.sourceId == 'stackexchange'
                      ? Icons.forum_outlined
                      : Icons.chat_bubble_outline_rounded,
                  size: 13,
                  color: p.moss,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${result.sourceName}  ·  ${result.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.muted,
                          fontSize: 9.5,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              result.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: p.ink,
                    fontSize: 16.5,
                    height: 1.32,
                  ),
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                stats.join('   ·   '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.faint,
                      fontSize: 9,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class VideoResultTile extends StatelessWidget {
  const VideoResultTile({
    required this.result,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final thumb = result.thumbnailUrl ?? result.imageUrl;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              height: 76,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Thumb(
                    url: thumb ?? '',
                    width: 128,
                    height: 76,
                    radius: SiftRadius.sm,
                  ),
                  if (result.duration != null)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        color: const Color(0xCC1D211B),
                        child: Text(
                          result.duration!,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: const Color(0xFFF8F4EA),
                                fontSize: 8,
                                height: 1.2,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.sourceName.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.clay,
                          fontSize: 8.5,
                          letterSpacing: 0.6,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: p.ink,
                          height: 1.35,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      if (result.meta['views'] != null)
                        '${result.meta['views']} views',
                      if (result.author != null) result.author!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 9,
                        ),
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

class ImageResultTile extends StatelessWidget {
  const ImageResultTile({
    required this.result,
    this.onTap,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final image = result.thumbnailUrl ?? result.imageUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SiftRadius.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.12,
            child: Container(
              decoration: BoxDecoration(
                color: p.surfaceRaised,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(SiftRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: image == null || image.isEmpty
                  ? _ImageFallback(dark: p.isDark)
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) =>
                          _ImageFallback(dark: p.isDark),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: p.surfaceRaised);
                      },
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.inkSoft,
                  height: 1.35,
                  fontSize: 11.5,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            result.meta['license']?.toString() ?? result.host,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.faint,
                  fontSize: 8.5,
                  letterSpacing: 0.2,
                ),
          ),
        ],
      ),
    );
  }
}

class AnswerCard extends StatelessWidget {
  const AnswerCard({
    required this.answer,
    this.onOpenLink,
    super.key,
  });

  final InstantAnswer answer;
  final ValueChanged<String>? onOpenLink;

  IconData get _icon => switch (answer.kind) {
        'calculator' => Icons.calculate_outlined,
        'unit' => Icons.straighten_rounded,
        'currency' => Icons.currency_exchange_rounded,
        'weather' => Icons.wb_sunny_outlined,
        'dictionary' => Icons.menu_book_outlined,
        _ => Icons.bolt_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: p.mossWash,
        border: Border.all(color: p.moss.withOpacity(0.26)),
        borderRadius: BorderRadius.circular(SiftRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: p.clay,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SiftRadius.md),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon, size: 15, color: p.mossDeep),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        (answer.subtitle ?? answer.kind).toUpperCase(),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: p.mossDeep,
                              fontSize: 9,
                              letterSpacing: 0.8,
                            ),
                      ),
                    ),
                    if (answer.isLive)
                      SiftBadge(
                        'Live',
                        color: p.clay,
                        background: p.clayWash,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        answer.title,
                        style:
                            Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  height: 1.1,
                                  fontSize: 29,
                                ),
                      ),
                    ),
                    if (answer.imageUrl != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(color: p.line),
                          borderRadius: BorderRadius.circular(SiftRadius.sm),
                          color: p.surface,
                        ),
                        child: Icon(_icon, color: p.gold, size: 25),
                      ),
                    ],
                  ],
                ),
                if (answer.body != null) ...[
                  const SizedBox(height: 9),
                  Text(
                    answer.body!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: p.inkSoft,
                          height: 1.5,
                        ),
                  ),
                ],
                if (answer.facts.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 20,
                    runSpacing: 9,
                    children: [
                      for (final fact in answer.facts)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fact.label.toUpperCase(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: p.muted,
                                      fontSize: 8,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fact.value,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (answer.link != null && onOpenLink != null) ...[
                  const SizedBox(height: 9),
                  SiftTextAction(
                    label: answer.linkLabel ?? 'Open source',
                    onTap: () => onOpenLink!(answer.link!),
                  ),
                ],
                if (answer.source != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    answer.source!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: p.faint,
                          fontSize: 8.5,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderStrip extends StatelessWidget {
  const ProviderStrip({
    required this.statuses,
    required this.elapsedMs,
    this.onTap,
    super.key,
  });

  final List<ProviderStatus> statuses;
  final int elapsedMs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final ok = statuses.where((status) => status.ok).length;
    final failed = statuses.length - ok;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SiftRadius.xs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: failed == 0 ? p.moss : p.gold,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failed == 0
                    ? '$ok ${pluralize(ok, 'source')} answered'
                    : '$ok answered · $failed unavailable',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.muted,
                      fontSize: 9,
                    ),
              ),
            ),
            Text(
              '${(elapsedMs / 1000).toStringAsFixed(elapsedMs < 1000 ? 2 : 1)}s',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: p.faint,
                    fontSize: 9,
                  ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: p.faint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showResultActions(BuildContext context, SearchResult result) async {
  final services = SiftScope.servicesOf(context);
  final p = context.sift;
  await showSiftSheet<void>(
    context,
    builder: (sheetContext) {
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          SiftSpace.page,
          0,
          SiftSpace.page,
          MediaQuery.paddingOf(sheetContext).bottom + 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SiftSheetTitle(
              title: 'Result',
              subtitle: result.title,
              trailing: SiftIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              result.displayUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                    color: p.faint,
                    fontSize: 9,
                  ),
            ),
            const SizedBox(height: 16),
            _ActionResult(
              icon: Icons.open_in_new_rounded,
              label: 'Open in Sift',
              onTap: () {
                Navigator.of(sheetContext).pop();
                openSiftUrl(context, result.url, title: result.title);
              },
            ),
            _ActionResult(
              icon: Icons.bookmark_add_outlined,
              label: services.library.isSaved(result.url)
                  ? 'Remove from saved'
                  : 'Save to library',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                if (services.library.isSaved(result.url)) {
                  final saved = services.library.savedFor(result.url);
                  if (saved != null) await services.library.deleteSaved(saved.id);
                  if (context.mounted) showSiftToast(context, 'Removed from saved');
                } else {
                  await services.library.saveResult(result);
                  if (context.mounted) showSiftToast(context, 'Saved to library');
                }
              },
            ),
            _ActionResult(
              icon: Icons.travel_explore_rounded,
              label: 'Index this page in My Search',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _indexResult(context, result);
              },
            ),
            _ActionResult(
              icon: Icons.content_copy_rounded,
              label: 'Copy link',
              onTap: () {
                Navigator.of(sheetContext).pop();
                copyText(context, result.url);
              },
            ),
            _ActionResult(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: () {
                Navigator.of(sheetContext).pop();
                shareSiftText(
                  context,
                  text: result.title,
                  title: result.title,
                  url: result.url,
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Sift never sends a saved page anywhere. Library entries live in '
              'app storage until you delete them.',
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: p.muted,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _indexResult(BuildContext context, SearchResult result) async {
  final services = SiftScope.servicesOf(context);
  final body = [
    result.title,
    result.snippet,
    if (result.snippet.length < 80) result.displayUrl,
  ].join('. ');
  try {
    await services.localIndex.indexText(
      url: result.url,
      title: result.title,
      text: body,
    );
    if (context.mounted) {
      showSiftToast(context, 'Indexed on this device');
    }
  } catch (error) {
    if (context.mounted) {
      showSiftToast(context, '$error', error: true);
    }
  }
}

Future<void> showImagePreview(
  BuildContext context,
  SearchResult result,
) async {
  final p = context.sift;
  final imageUrl = result.imageUrl ?? result.thumbnailUrl;
  await showSiftSheet<void>(
    context,
    builder: (sheetContext) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SiftSpace.page,
        0,
        SiftSpace.page,
        MediaQuery.paddingOf(sheetContext).bottom + 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftSheetTitle(
            title: 'Image',
            subtitle: result.title,
            trailing: SiftIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            width: double.infinity,
            decoration: BoxDecoration(
              color: p.surfaceRaised,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SiftRadius.sm),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl == null || imageUrl.isEmpty
                ? const SizedBox(height: 220, child: _ImageFallback(dark: false))
                : Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox(height: 220, child: _ImageFallback(dark: false)),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            [
              result.meta['license']?.toString(),
              result.meta['author']?.toString() ?? result.author,
              result.sourceName,
            ].whereType<String>().where((part) => part.isNotEmpty).join('  ·  '),
            style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                  color: p.faint,
                  fontSize: 9,
                ),
          ),
          const SizedBox(height: 18),
          SiftButton(
            label: 'Open source page',
            icon: Icons.open_in_new_rounded,
            expand: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              openSiftUrl(context, result.url, title: result.title);
            },
          ),
          const SizedBox(height: 6),
          Center(
            child: SiftTextAction(
              label: 'Save to library',
              icon: null,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await SiftScope.servicesOf(context).library.saveResult(result);
                if (context.mounted) {
                  showSiftToast(context, 'Saved to library');
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActionResult extends StatelessWidget {
  const _ActionResult({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: p.muted),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: p.ink,
                    ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: p.faint),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.width,
    required this.height,
    this.radius = SiftRadius.sm,
  });

  final String url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(radius),
        ),
        clipBehavior: Clip.antiAlias,
        child: url.isEmpty
            ? _ImageFallback(dark: p.isDark)
            : Image.network(
                url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => _ImageFallback(dark: p.isDark),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(color: p.surfaceRaised);
                },
              ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      color: p.surfaceRaised,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 18,
        color: p.faint,
      ),
    );
  }
}

String _metaLine(SearchResult result) {
  return [
    if (result.author != null && result.author!.isNotEmpty) result.author!,
    if (result.publishedAt != null) relativeDate(result.publishedAt),
    if (result.meta['answers'] != null)
      '${result.meta['answers']} answers',
    if (result.meta['points'] != null) '${result.meta['points']} points',
  ].where((part) => part.isNotEmpty).join('  ·  ');
}

class EmptyResults extends StatelessWidget {
  const EmptyResults({
    required this.query,
    this.onTryLocal,
    this.onChangeSources,
    super.key,
  });

  final String query;
  final VoidCallback? onTryLocal;
  final VoidCallback? onChangeSources;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SiftKicker('Nothing came back', color: p.clay),
          const SizedBox(height: 12),
          Text(
            'No results for “$query”.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Try fewer words, a different spelling, or search the local '
            'reference shelf instead.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  height: 1.55,
                ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (onTryLocal != null)
                SiftButton(
                  label: 'Search My Search',
                  tone: SiftButtonTone.quiet,
                  onPressed: onTryLocal,
                  compact: true,
                ),
              if (onChangeSources != null)
                SiftButton(
                  label: 'Choose sources',
                  tone: SiftButtonTone.line,
                  onPressed: onChangeSources,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
