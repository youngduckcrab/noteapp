// lib/src/ui/content/note_cover_view.dart — 05-library 6.15.1. The cover box
// of a note tile / row: first page thumbnail, color card or asset image, and
// a placeholder whenever there is nothing (yet) to show. A FirstPageCover
// asks the cover thumbnail scheduler (6.15.3) for a thumbnail while it is
// visible.
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show AssetCover, ColorCover, FirstPageCover, Note, pageThumbnailProvider;

import '../../appearance/cover_palette.dart';
import '../../state/providers.dart';
import '../../thumbnails/cover_thumbnail_scheduler.dart';
import '../layout/library_metrics.dart';

class NoteCoverView extends ConsumerStatefulWidget {
  const NoteCoverView({
    super.key,
    required this.note,
    required this.width,
    required this.height,
  });
  final Note note;
  final double width, height; // logical px of the cover box

  @override
  ConsumerState<NoteCoverView> createState() => _NoteCoverViewState();
}

class _NoteCoverViewState extends ConsumerState<NoteCoverView> {
  CoverThumbnailScheduler? _scheduler;

  @override
  void initState() {
    super.initState();
    // fireImmediately: the current scheduler right away; a new one (renderer
    // slot changed, the old one is disposed) gets the request again.
    ref.listenManual<CoverThumbnailScheduler>(coverThumbnailSchedulerProvider, (
      _,
      next,
    ) {
      _scheduler = next;
      next.request(widget.note);
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(NoteCoverView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.note, now = widget.note;
    if (before.id != now.id) {
      _scheduler?.cancel(before.id);
      _scheduler?.request(now);
    } else if (before.updatedAt != now.updatedAt ||
        before.firstPageId != now.firstPageId ||
        before.cover != now.cover) {
      _scheduler?.request(now);
    }
  }

  @override
  void dispose() {
    _scheduler?.cancel(widget.note.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width, height = widget.height;
    final placeholder = CoverPlaceholder(width: width, height: height);
    switch (widget.note.cover) {
      case FirstPageCover():
        final pageId = widget.note.firstPageId;
        if (pageId == null) return placeholder;
        // A stale thumbnail stays until the new one is written.
        final thumb = ref.watch(pageThumbnailProvider(pageId)).value;
        if (thumb == null) return placeholder;
        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: _CoverImage(
              bytes: thumb.bytes,
              width: width,
              fit: BoxFit.contain,
              placeholder: placeholder,
            ),
          ),
        );
      case ColorCover(:final colorArgb):
        return ColorCoverCard(
          title: widget.note.title,
          colorArgb: colorArgb,
          width: width,
          height: height,
        );
      case AssetCover(:final assetId):
        final bytes = ref.watch(assetCoverBytesProvider(assetId)).value;
        if (bytes == null) return placeholder;
        return SizedBox(
          width: width,
          height: height,
          child: _CoverImage(
            bytes: bytes,
            width: width,
            fit: BoxFit.cover,
            placeholder: placeholder,
          ),
        );
    }
  }
}

/// Image.memory decoded at the box width in device pixels; bytes that do not
/// decode show [placeholder].
class _CoverImage extends StatelessWidget {
  const _CoverImage({
    required this.bytes,
    required this.width,
    required this.fit,
    required this.placeholder,
  });

  final Uint8List bytes;
  final double width;
  final BoxFit fit;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.memory(
      bytes,
      cacheWidth: math.max(1, (width * dpr).round()),
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// A ColorCover: the color, an 8 px spine (the color with 20 % black) on the
/// left and the title (2 lines, 16/22 w600, coverForegroundFor) at 24 % of
/// the height. Boxes narrower than LibraryMetrics.coverTitleMinWidth (list
/// row thumbnails — the title is next to them) show no title.
class ColorCoverCard extends StatelessWidget {
  const ColorCoverCard({
    super.key,
    required this.title,
    required this.colorArgb,
    required this.width,
    required this.height,
  });

  final String title;
  final int colorArgb;
  final double width, height;

  static const double spineWidth = 8;

  @override
  Widget build(BuildContext context) {
    final showTitle = width >= LibraryMetrics.coverTitleMinWidth;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Color(colorArgb),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: spineWidth,
              child: ColoredBox(color: coverSpineColorFor(colorArgb)),
            ),
            if (showTitle)
              Positioned(
                left: spineWidth + 12,
                right: 12,
                top: height * 0.24,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: LibraryMetrics.maxTileTextScale,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w600,
                      color: coverForegroundFor(colorArgb),
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

/// surfaceContainerHigh + Icons.description_outlined (onSurfaceVariant 60%),
/// 40 px (smaller boxes scale it down).
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.width,
    required this.height,
  });

  final double width, height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shortest = width < height ? width : height;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: Center(
          child: Icon(
            Icons.description_outlined,
            size: shortest < 64 ? shortest * 0.6 : 40,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
