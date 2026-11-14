import 'package:flutter/material.dart';

import '../core/models/search_models.dart';
import '../core/services/sift_scope.dart';
import '../core/theme/sift_theme.dart';
import '../core/utils/formatters.dart';
import '../core/utils/navigation.dart';
import '../screens/search/image_viewer_screen.dart';
import 'sift_ui.dart';

class _SourceMark extends StatelessWidget {
  const _SourceMark({required this.label, this.size = 26});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    final clean = label.trim();
    final initial = clean.isEmpty ? '?' : clean.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.mossWash,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: p.mossDeep,
              fontSize: size * 0.5,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
      ),
    );
  }
}

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
    final saved =
        SiftScope.maybeServicesOf(context)?.library.isSaved(result.url) ?? false;
    final host = result.host;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SourceMark(label: host),
                const SizedBox(width: 9),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: host,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: p.inkSoft,
                                fontSize: 12.5,
                                height: 1.2,
                              ),
                        ),
                        if (result.sourceName.isNotEmpty &&
                            result.sourceName.toLowerCase() !=
                                host.toLowerCase())
                          TextSpan(
                            text: '  ·  ${result.sourceName}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: p.faint,
                                      fontSize: 11.5,
                                      height: 1.2,
                                    ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (saved)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.bookmark_rounded, size: 15, color: p.moss),
                  ),
                IconButton(
                  tooltip: 'More actions',
                  onPressed: () => showResultActions(context, result),
                  icon: const Icon(Icons.more_vert_rounded, size: 19),
                  color: p.faint,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 30,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.title.isEmpty ? result.displayUrl : result.title,
                        maxLines: dense ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: dense ? 16.5 : 18,
                              height: 1.3,
                              fontWeight: FontWeight.w400,
                              color: p.mossDeep,
                            ),
                      ),
                      if (result.snippet.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          result.snippet,
                          maxLines: dense ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: p.muted,
                                    height: 1.48,
                                    fontSize: 14,
                                  ),
                        ),
                      ],
                      if (_metaLine(result).isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          _metaLine(result),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: p.faint,
                                    fontSize: 11,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (result.thumbnailUrl != null &&
                    result.thumbnailUrl!.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  _Thumb(
                    url: result.thumbnailUrl!,
                    width: dense ? 76 : 88,
                    height: dense ? 66 : 76,
                    radius: SiftRadius.md,
                  ),
                ],
              ],
            ),
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
    final source = publisher == null || publisher.isEmpty
        ? result.host
        : publisher;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: lead ? 14 : 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SourceMark(label: source),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.inkSoft,
                          fontSize: 12.5,
                        ),
                  ),
                ),
                if (result.publishedAt != null)
                  Text(
                    relativeDate(result.publishedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.faint,
                          fontSize: 11.5,
                        ),
                  ),
                IconButton(
                  tooltip: 'More actions',
                  onPressed: () => showResultActions(context, result),
                  icon: const Icon(Icons.more_vert_rounded, size: 19),
                  color: p.faint,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 32, height: 30),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    result.title,
                    maxLines: lead ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: lead ? 20 : 16.5,
                          height: 1.3,
                          fontWeight: FontWeight.w400,
                          color: p.ink,
                        ),
                  ),
                ),
                if (result.thumbnailUrl != null &&
                    result.thumbnailUrl!.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  _Thumb(
                    url: result.thumbnailUrl!,
                    width: lead ? 104 : 86,
                    height: lead ? 78 : 64,
                    radius: SiftRadius.md,
                  ),
                ],
              ],
            ),
            if (lead && result.snippet.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                result.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: p.muted,
                      height: 1.45,
                      fontSize: 13.5,
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
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SourceMark(
                  label: result.sourceName,
                  size: 24,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${result.sourceName}  ·  ${result.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.muted,
                          fontSize: 12,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'More actions',
                  onPressed: () => showResultActions(context, result),
                  icon: const Icon(Icons.more_vert_rounded, size: 19),
                  color: p.faint,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 32, height: 30),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              result.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: p.mossDeep,
                    fontSize: 16.5,
                    height: 1.34,
                    fontWeight: FontWeight.w400,
                  ),
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                stats.join('   ·   '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: p.faint,
                      fontSize: 11.5,
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
    this.compact = false,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Compact rows keep the All tab dense; the Videos tab uses full-width
  /// cards so the thumbnail and creator details carry the result.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: compact ? _compact(context) : _card(context),
    );
  }

  Widget _compact(BuildContext context) {
    final p = context.sift;
    final thumb = result.thumbnailUrl ?? result.imageUrl;
    final meta = [
      if (result.author != null && result.author!.isNotEmpty) result.author!,
      result.sourceName,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            height: 78,
            child: _Poster(
              url: thumb,
              duration: result.duration,
              playSize: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: p.ink,
                        fontSize: 15.5,
                        height: 1.32,
                        fontWeight: FontWeight.w500,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.muted,
                        fontSize: 12,
                      ),
                ),
                if (result.publishedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    relativeDate(result.publishedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: p.faint,
                          fontSize: 11.5,
                        ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'More actions',
            onPressed: () => showResultActions(context, result),
            icon: const Icon(Icons.more_vert_rounded, size: 19),
            color: p.faint,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final p = context.sift;
    final thumb = result.thumbnailUrl ?? result.imageUrl;
    final source = [
      result.author ?? '',
      result.sourceName,
      if (result.publishedAt != null) relativeDate(result.publishedAt),
    ].where((part) => part.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _Poster(
              url: thumb,
              duration: result.duration,
              playSize: 46,
              radius: SiftRadius.md,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  result.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: p.ink,
                        fontSize: 17,
                        height: 1.32,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'More actions',
                onPressed: () => showResultActions(context, result),
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                color: p.faint,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: p.muted,
                  fontSize: 12,
                ),
          ),
          if (result.snippet.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              result.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: p.inkSoft,
                    fontSize: 13,
                    height: 1.45,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared 16:9 poster used by video rows and cards.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.url,
    required this.playSize,
    this.duration,
    this.radius = SiftRadius.sm,
  });

  final String? url;
  final double playSize;
  final String? duration;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Thumb(
          url: url ?? '',
          width: double.infinity,
          height: double.infinity,
          radius: radius,
        ),
        Center(
          child: Container(
            width: playSize,
            height: playSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xCC000000),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: playSize * 0.66,
            ),
          ),
        ),
        if (duration != null && duration!.isNotEmpty)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xCC000000),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                duration!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ImageResultTile extends StatelessWidget {
  const ImageResultTile({
    required this.result,
    this.onTap,
    this.aspectRatio = 1,
    this.caption = true,
    super.key,
  });

  final SearchResult result;
  final VoidCallback? onTap;

  /// Height divided by width, clamped by the caller so a portrait poster does
  /// not turn a result column into a single tile.
  final double aspectRatio;

  /// The horizontal strip on the All tab shows images only; the Images tab
  /// adds the attribution caption under every tile.
  final bool caption;

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
            aspectRatio: aspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: p.surfaceRaised,
                borderRadius: BorderRadius.circular(SiftRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: image == null || image.isEmpty
                  ? const _ImageFallback()
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) => const _ImageFallback(),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: p.surfaceRaised);
                      },
                    ),
            ),
          ),
          if (caption) ...[
            const SizedBox(height: 6),
            Text(
              result.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: p.inkSoft,
                    height: 1.35,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              result.meta['license']?.toString() ?? result.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: p.faint,
                    fontSize: 11,
                  ),
            ),
          ],
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
        _ => Icons.auto_awesome_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.sift;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(SiftRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, size: 17, color: p.moss),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    answer.subtitle ?? 'Overview',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: p.moss,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                if (answer.isLive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: p.clayWash,
                      borderRadius: BorderRadius.circular(SiftRadius.pill),
                    ),
                    child: Text(
                      'Live',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.clay,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    answer.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          height: 1.25,
                          fontSize: 21,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                if (answer.imageUrl != null) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SiftRadius.sm),
                    child: Image.network(
                      answer.imageUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: p.surfaceRaised,
                        child: Icon(_icon, size: 22, color: p.muted),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (answer.body != null && answer.body!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                answer.body!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: p.inkSoft,
                      height: 1.5,
                    ),
              ),
            ],
            if (answer.facts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fact in answer.facts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: p.surfaceRaised,
                        borderRadius: BorderRadius.circular(SiftRadius.sm),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fact.label,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: p.muted,
                                      fontSize: 10.5,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fact.value,
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontSize: 13,
                                      color: p.ink,
                                    ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            if (answer.link != null && onOpenLink != null) ...[
              const SizedBox(height: 8),
              SiftTextAction(
                label: answer.linkLabel ?? 'Open source',
                onTap: () => onOpenLink!(answer.link!),
              ),
            ],
            if (answer.source != null && answer.source!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                answer.source!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: p.faint,
                      fontSize: 10.5,
                    ),
              ),
            ],
          ],
        ),
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
    final seconds = (elapsedMs / 1000).toStringAsFixed(elapsedMs < 1000 ? 2 : 1);
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(SiftRadius.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SiftRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  failed == 0
                      ? Icons.verified_outlined
                      : Icons.info_outline_rounded,
                  size: 14,
                  color: failed == 0 ? p.moss : p.gold,
                ),
                const SizedBox(width: 7),
                Text(
                  failed == 0
                      ? '$ok ${pluralize(ok, 'source')} · $seconds s'
                      : '$ok of ${statuses.length} sources · $seconds s',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: p.muted,
                        fontSize: 11.5,
                      ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 3),
                  Icon(Icons.expand_more_rounded, size: 15, color: p.faint),
                ],
              ],
            ),
          ),
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
                    fontSize: 11.5,
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
) {
  return showImageViewer(context, [result]);
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
            ? const _ImageFallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => const _ImageFallback(),
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
  const _ImageFallback();

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
