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
import 'package:ui_kit/ui_kit.dart';

import '../../appearance/cover_palette.dart';
import '../../l10n/library_strings.dart';
import '../../state/markdown_preview.dart';
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
    // (v2.17-md, C217M-11) an MD 문서: a text page with its preview and the 'MD' mark.
    if (widget.note.isMarkdown) {
      return MarkdownCoverCard(note: widget.note, width: width, height: height);
    }
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
            // (v2.14-ui) a page thumbnail sits on paper in every style.
            color: StyleTokens.of(context).inkSwatch,
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

/// A faintly ruled paper sheet (the paper swatch with a 2.5 % ink tint, 6 %
/// in a dark style) + the 노트 line icon (AppIconKind.note, paper ink 35 %),
/// 40 px (smaller boxes scale it down, without the rules). (v2.14-ui review,
/// owner review) Real first-page thumbnails stay paper-white, so a grey
/// placeholder would mix with them and flash grey → white while a thumbnail
/// loads.
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.width,
    required this.height,
  });

  final double width, height;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final shortest = width < height ? width : height;
    final dark = tokens.isDark;
    // (owner review) Paper in every brightness, faintly ruled: a sheet
    // waiting for its thumbnail (which is paper-white too), not a grey box.
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Color.alphaBlend(
          tokens.paperInk.withValues(alpha: dark ? 0.06 : 0.025),
          tokens.inkSwatch,
        ),
        child: CustomPaint(
          painter: shortest < 64
              ? null
              : _RuledPaperPainter(tokens.paperInk.withValues(alpha: 0.07)),
          child: Center(
            child: AppIcon(
              AppIconKind.note,
              size: shortest < 64 ? shortest * 0.6 : 40,
              strokeWidth: 1.2,
              color: tokens.paperInk.withValues(alpha: 0.35),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint rules across a placeholder sheet (behind the icon).
class _RuledPaperPainter extends CustomPainter {
  const _RuledPaperPainter(this.line);

  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    final step = math.max(10.0, size.height / 14);
    for (var y = step * 2; y < size.height - step / 2; y += step) {
      canvas.drawLine(
        Offset(size.width * .1, y),
        Offset(size.width * .9, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RuledPaperPainter oldDelegate) =>
      oldDelegate.line != line;
}

/// (v2.17-md, C217M-11 — 08-markdown 9) The cover of an MD 문서: a paper page
/// ([StyleTokens.inkSwatch], paper in every style and brightness) with the first line of
/// the preview in bold and the next lines in [StyleTokens.paperInk], and the 'MD' mark at
/// the bottom right. The preview is keyed by the note's updatedAt (never stale).
class MarkdownCoverCard extends ConsumerWidget {
  const MarkdownCoverCard({
    super.key,
    required this.note,
    required this.width,
    required this.height,
  });

  final Note note;
  final double width, height;

  static const Key previewKey = Key('library.tile.mdPreview');
  static const Key badgeKey = Key('library.tile.mdBadge');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final preview = ref
        .watch(
          libraryMarkdownPreviewProvider((
            noteId: note.id,
            updatedAt: note.updatedAt,
          )),
        )
        .value;
    final lines = (preview ?? '').split('\n');
    final first = lines.first;
    final rest = lines.skip(1).join('\n');
    final small = width < 120;
    final base = TextStyle(
      color: tokens.paperInk,
      fontSize: small ? 8 : 10,
      height: 1.35,
    );
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: tokens.inkSwatch,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.all(small ? 8 : 12),
              child: Text.rich(
                key: previewKey,
                TextSpan(
                  children: [
                    if (first.isNotEmpty)
                      TextSpan(
                        text: first,
                        style: base.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: (small ? 8 : 10) + 2,
                        ),
                      ),
                    if (rest.isNotEmpty) TextSpan(text: '\n$rest'),
                  ],
                ),
                style: base,
                overflow: TextOverflow.fade,
              ),
            ),
            Positioned(
              right: 6,
              bottom: 6,
              child: DecoratedBox(
                key: badgeKey,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(tokens.radiusSmall),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        AppIconKind.markdownDoc,
                        size: 12,
                        color: tokens.onAccentSoft,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        LibraryStrings.markdownBadge,
                        style: TextStyle(
                          color: tokens.onAccentSoft,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
