// lib/src/render/thumbnail.dart — contract 7.2.16 (v1.1): the CALLER passes the provider values.
//
// Foundation step B3 (03-ink 4.15): background builder (isThumbnail: true,
// ancestorScale 1) + polylines painted directly. The one-time raster of 6.17
// comes with INK T20 (same signature; still no pageId-wide cache).
import 'package:flutter/widgets.dart';

import '../background/background_builder.dart';
import '../background/builder_choice.dart';
import '../model/ink_layer.dart';
import 'ink_page_content.dart';
import 'pencil_grain.dart';
import 'stroke_painter.dart';

/// (v1.1) INK 4.9. ink_engine does not depend on flutter_riverpod, so the widget reads no
/// provider: the CALLER passes ref.watch(pageBackgroundBuildersProvider) and
/// ref.watch(pencilGrainProvider).
class InkPageThumbnail extends StatefulWidget {
  const InkPageThumbnail({
    super.key,
    required this.content,
    required this.width,
    required this.backgroundBuilders,
    this.pencilGrain,
  });
  final InkPageContent content;

  /// logical px; height = page aspect
  final double width;
  final List<PageBackgroundLayerBuilder> backgroundBuilders;
  final PencilGrain? pencilGrain;

  /// StatefulWidget member (not in the block)
  @override
  State<InkPageThumbnail> createState() => _InkPageThumbnailState();
}

class _InkPageThumbnailState extends State<InkPageThumbnail> {
  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final pageSize = content.pageSize;
    final viewScale = widget.width / pageSize.width;
    final height = pageSize.height * viewScale;
    final background = content.background;
    final ctx = PageBackgroundContext(
      pageId: content.pageId,
      pageSize: pageSize,
      background: background,
      viewScale: viewScale,
      ancestorScale: 1,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
      isScaling: false,
      isThumbnail: true,
    );
    return SizedBox(
      width: widget.width,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: backgroundBuilderFor(
                  widget.backgroundBuilders,
                  background,
                ).build(context, ctx),
              ),
            ),
            if (content.strokes.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: _ThumbnailStrokesPainter(content, viewScale),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailStrokesPainter extends CustomPainter {
  _ThumbnailStrokesPainter(this.content, this.viewScale);

  final InkPageContent content;
  final double viewScale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(viewScale);
    for (final layer in InkLayer.values) {
      for (final s in content.strokes) {
        if (s.layer == layer) paintStrokePolyline(canvas, s.source);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbnailStrokesPainter oldDelegate) =>
      oldDelegate.viewScale != viewScale ||
      oldDelegate.content.pageId != content.pageId ||
      oldDelegate.content.revision != content.revision ||
      oldDelegate.content.pageSize != content.pageSize ||
      !identical(oldDelegate.content.strokes, content.strokes);
}
