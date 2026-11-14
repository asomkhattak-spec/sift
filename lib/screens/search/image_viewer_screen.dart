import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/search_models.dart';
import '../../core/services/sift_scope.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/navigation.dart';
import '../../widgets/sift_ui.dart';

/// Opens the full-screen media viewer at [initialIndex]. The viewer keeps the
/// whole result set so a swipe moves through the same search without going
/// back to the grid first.
Future<void> showImageViewer(
  BuildContext context,
  List<SearchResult> results, {
  int initialIndex = 0,
}) {
  if (results.isEmpty) return Future<void>.value();
  final start = initialIndex.clamp(0, results.length - 1).toInt();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ImageViewerScreen(results: results, initialIndex: start),
    ),
  );
}

class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    required this.results,
    this.initialIndex = 0,
    super.key,
  });

  final List<SearchResult> results;
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pages;
  late int _index;
  bool _chrome = true;
  bool _downloading = false;
  bool _zoomed = false;

  SearchResult get _current => widget.results[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  void _open() {
    final result = _current;
    // Keep the viewer underneath the browser so Back returns to the image.
    openSiftUrl(context, result.url, title: result.title);
  }

  Future<void> _download() async {
    if (_downloading) return;
    final result = _current;
    final url = result.imageUrl ?? result.thumbnailUrl;
    if (url == null || url.isEmpty) {
      showSiftToast(context, 'This image has no downloadable file.', error: true);
      return;
    }
    setState(() => _downloading = true);
    final name = _filenameFor(result, url);
    final ok = await SiftScope.servicesOf(context).native.download(
          url: url,
          filename: name,
          mime: _mimeFor(name),
        );
    if (!mounted) return;
    setState(() => _downloading = false);
    showSiftToast(
      context,
      ok
          ? 'Downloading $name'
          : 'Could not start the download. Open the source page instead.',
      error: !ok,
    );
  }

  Future<void> _save() async {
    await SiftScope.servicesOf(context).library.saveResult(_current);
    if (!mounted) return;
    showSiftToast(context, 'Saved to library');
  }

  Future<void> _share() async {
    final result = _current;
    await shareSiftText(
      context,
      text: result.title,
      title: result.title,
      url: result.url,
    );
  }

  static String _filenameFor(SearchResult result, String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    var extension = dot >= 0 ? path.substring(dot + 1).toLowerCase() : 'jpg';
    if (!RegExp(r'^(jpe?g|png|gif|webp|avif|bmp)$').hasMatch(extension)) {
      extension = 'jpg';
    }
    var base = result.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (base.isEmpty) base = 'sift-image';
    if (base.length > 60) base = base.substring(0, 60);
    return '$base.$extension';
  }

  static String _mimeFor(String filename) {
    final extension = filename.split('.').last;
    return switch (extension) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'avif' => 'image/avif',
      'bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
  }

  @override
  Widget build(BuildContext context) {
    final result = _current;
    final attribution = [
      result.meta['author']?.toString() ?? result.author ?? '',
      licenseLabel(result.meta['license']?.toString() ?? ''),
      result.sourceName,
    ].where((part) => part.isNotEmpty).join(' · ');

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: widget.results.length,
                onPageChanged: (value) => setState(() {
                  _index = value;
                  _zoomed = false;
                }),
                itemBuilder: (context, index) {
                  final item = widget.results[index];
                  final source = item.imageUrl ?? item.thumbnailUrl ?? '';
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleChrome,
                    child: _ZoomableImage(
                      url: source,
                      onZoomChanged: (zoomed) {
                        if (index == _index && zoomed != _zoomed) {
                          setState(() => _zoomed = zoomed);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: _TopBar(
                    position: '${_index + 1} / ${widget.results.length}',
                    onClose: () => Navigator.of(context).pop(),
                    onDownload: _downloading ? null : _download,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_chrome,
                child: AnimatedOpacity(
                  opacity: _chrome ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: _BottomPanel(
                    title: result.title,
                    attribution: attribution,
                    onOpen: _open,
                    onDownload: _downloading ? null : _download,
                    onShare: _share,
                    onSave: _save,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.url, required this.onZoomChanged});

  final String url;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transform = TransformationController();
  bool _zoomed = false;
  Offset? _doubleTapAt;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _setZoomed(bool zoomed) {
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoomChanged(zoomed);
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    _setZoomed(_transform.value.getMaxScaleOnAxis() > 1.02);
  }

  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
      _setZoomed(false);
      return;
    }
    final at = _doubleTapAt ?? Offset.zero;
    const scale = 2.4;
    _transform.value = Matrix4.identity()
      ..translate(-at.dx * (scale - 1), -at.dy * (scale - 1))
      ..scale(scale);
    _setZoomed(true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) {
      return const Center(
        child: Icon(Icons.hide_image_outlined, color: Colors.white54, size: 40),
      );
    }
    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 4,
      panEnabled: _zoomed,
      onInteractionEnd: _onInteractionEnd,
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
        onDoubleTap: _toggleZoom,
        child: Image.network(
          widget.url,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined,
                    color: Colors.white54, size: 40),
                SizedBox(height: 10),
                Text(
                  'Image unavailable',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.position,
    required this.onClose,
    required this.onDownload,
  });

  final String position;
  final VoidCallback onClose;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.paddingOf(context).top + 8,
        8,
        22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onPressed: onClose,
          ),
          const Spacer(),
          Text(
            position,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          _CircleButton(
            icon: Icons.download_rounded,
            tooltip: 'Download',
            onPressed: onDownload,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 22),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.12),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.title,
    required this.attribution,
    required this.onOpen,
    required this.onDownload,
    required this.onShare,
    required this.onSave,
  });

  final String title;
  final String attribution;
  final VoidCallback onOpen;
  final VoidCallback? onDownload;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        44,
        20,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xE6000000)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          if (attribution.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              attribution,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ViewerAction(
                icon: Icons.open_in_new_rounded,
                label: 'Open',
                onTap: onOpen,
              ),
              _ViewerAction(
                icon: Icons.download_rounded,
                label: 'Download',
                onTap: onDownload,
              ),
              _ViewerAction(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: onShare,
              ),
              _ViewerAction(
                icon: Icons.bookmark_border_rounded,
                label: 'Save',
                onTap: onSave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewerAction extends StatelessWidget {
  const _ViewerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? Colors.white : Colors.white38;
    return InkResponse(
      onTap: onTap,
      radius: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}