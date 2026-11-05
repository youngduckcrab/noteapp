// lib/src/render/page_background_view.dart — 06-pdf 4.7, 6.8.
//
// Foundation step B4 (T0): signature only; the widget comes with PDF T9. During the
// foundation stage the INK builder list holds PdfBackgroundLayerBuilder.paperOnly(), which
// never builds this widget.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../text/search_types.dart';
import 'render_service.dart';

/// Fills the page box (params.pageSize * viewScale logical px), paints opaque paper,
/// never handles pointer events (wrapped in IgnorePointer).
class PdfPageBackgroundView extends StatefulWidget {
  const PdfPageBackgroundView({
    super.key,
    required this.params,
    required this.renderer,
    this.highlights,
    required this.viewScale,
  });
  final PdfBackgroundParams params;
  final PdfPageRenderer renderer;

  /// Active search state for highlight rects (null = no highlights).
  final ValueListenable<PdfSearchState>? highlights;

  /// Logical px per NOTE pt = ink.PageBackgroundContext.viewScale. Widget size and painter
  /// scale use THIS ONLY (contract 7.2.16 v1.1). ancestorScale is never multiplied in: an
  /// ancestor Transform already applies it on screen; it reaches the render resolution only
  /// through params.deviceScale (= ctx.deviceScale).
  final double viewScale;

  @override
  State<PdfPageBackgroundView> createState() => _PdfPageBackgroundViewState();
}

class _PdfPageBackgroundViewState extends State<PdfPageBackgroundView> {
  @override
  Widget build(BuildContext context) =>
      throw UnimplementedError('PdfPageBackgroundView (PDF T9)');
}
