// lib/src/ink_adapter/ink_background_builder.dart — 06-pdf 4.7, 6.8 (contract 7.2.16 /
// 7.2.19). One of the files allowed to import package:ink_engine (always `as ink`, 3).
//
// The paperOnly placeholder (B4, T0) stays for tests; from PDF T9 the provider builds the
// renderer-backed builder: PdfPageBackgroundView for the editor / page panel and renderStill
// (renderer.renderThumbnail placed with PdfPageFit) for INK's thumbnail renderer.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

import '../common/error_report.dart';
import '../model/page_size_policy.dart';
import '../render/page_background_view.dart';
import '../render/render_service.dart';
import '../render/tile_math.dart';
import '../text/search_types.dart';

/// INK extension point implementation for InkBackgroundKind.pdf (contract 7.2.16, 6.8, 6.9).
final class PdfBackgroundLayerBuilder
    implements ink.PageBackgroundLayerBuilder, ink.PageBackgroundStillRenderer {
  /// [renderer] is called on the first build / renderStill, NOT when the builder list is read:
  /// reading ink.pageBackgroundBuildersProvider never creates the render chain (4.1, 4.12).
  /// (The contract's initializer list is kept: an initializing formal would make
  /// [renderer] nullable like the field.)
  PdfBackgroundLayerBuilder({
    required PdfPageRenderer Function() renderer,
    this.highlights,
  })
    // ignore: prefer_initializing_formals
    : _renderer = renderer;

  /// B4 placeholder (T0) and tests: opaque paper only, renderStill → null, no renderer.
  const PdfBackgroundLayerBuilder.paperOnly()
    : _renderer = null,
      highlights = null;
  final PdfPageRenderer Function()? _renderer;
  final ValueListenable<PdfSearchState>? highlights;

  /// _renderer == null
  bool get isPaperOnly => _renderer == null;

  /// background.kind == ink.InkBackgroundKind.pdf && assetId != null && pdfPageIndex != null
  /// (paperOnly too, so the B4 list order is the final one).
  @override
  bool handles(ink.InkBackgroundSpec background) =>
      background.kind == ink.InkBackgroundKind.pdf &&
      background.assetId != null &&
      background.pdfPageIndex != null;

  /// (contract 7.2.16 v1.1) Layout size / painter scale use ctx.viewScale ONLY; ancestorScale
  /// enters only through ctx.deviceScale (resolution / bucket choice):
  ///   PdfPageBackgroundView(params: paramsFrom(ctx), renderer: _renderer!(),
  ///       highlights: highlights, viewScale: ctx.viewScale)
  /// paperOnly: IgnorePointer(SizedBox(ctx.pageSize * ctx.viewScale, opaque paper color)).
  @override
  Widget build(BuildContext context, ink.PageBackgroundContext ctx) {
    final renderer = _renderer;
    if (renderer == null) {
      return IgnorePointer(
        child: SizedBox(
          width: ctx.pageSize.width * ctx.viewScale,
          height: ctx.pageSize.height * ctx.viewScale,
          child: ColoredBox(
            color: Color(opaquePaperArgb(ctx.background.paperColorArgb)),
          ),
        ),
      );
    }
    return PdfPageBackgroundView(
      params: paramsFrom(ctx),
      renderer: renderer(),
      highlights: highlights,
      viewScale: ctx.viewScale,
    );
  }

  /// Pure mapping (unit-tested), incl. isThumbnail = ctx.isThumbnail and
  /// deviceScale = ctx.deviceScale (6.8).
  static PdfBackgroundParams paramsFrom(ink.PageBackgroundContext ctx) =>
      PdfBackgroundParams(
        assetId: ctx.background.assetId!,
        pdfPageIndex: ctx.background.pdfPageIndex!,
        pageSize: ctx.pageSize,
        deviceScale: ctx.deviceScale,
        paperColorArgb: ctx.background.paperColorArgb,
        visiblePageRect: ctx.visiblePageRect,
        isScaling: ctx.isScaling,
        isThumbnail: ctx.isThumbnail,
        pageId: ctx.pageId,
      );

  /// Offscreen still image for ink.InkPageThumbnailRenderer: an OPAQUE image of [pixelSize]
  /// (paper color + the PDF page placed with PdfPageFit, 6.5.1).
  /// (contract 7.2.16 v1.1) null → cannot render now (InkPageThumbnailRenderer returns null):
  /// bytes missing, password needed, rendering failed, or paperOnly. Callers never cache a
  /// null result and retry later (LIBRARY 6.15.3). Never requests a remote download (6.9).
  @override
  Future<ui.Image?> renderStill(
    ink.InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) async {
    final renderer = _renderer;
    final assetId = background.assetId;
    final pdfPageIndex = background.pdfPageIndex;
    if (renderer == null || assetId == null || pdfPageIndex == null) {
      return null;
    }
    final width = pixelSize.width.ceil();
    final height = pixelSize.height.ceil();
    if (width <= 0 || height <= 0 || pageSize.isEmpty) return null;
    final paper = opaquePaperArgb(background.paperColorArgb);
    ui.Image? pdf;
    try {
      // Never asks for a download (6.9): renderThumbnail only reads local bytes.
      pdf = await renderer().renderThumbnail(
        assetId: assetId,
        pdfPageIndex: pdfPageIndex,
        longSidePx: math.max(width, height),
        backgroundArgb: paper,
      );
      if (pdf == null) return null;
      // The image has the PDF page's aspect, which is all PdfPageFit's box depends on.
      final box = PdfPageFit(
        notePageSize: pageSize,
        pdfPageSize: Size(pdf.width.toDouble(), pdf.height.toDouble()),
      ).pdfBoxInNote;
      final sx = width / pageSize.width;
      final sy = height / pageSize.height;
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..drawRect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..color = Color(paper),
        )
        ..drawImageRect(
          pdf,
          Rect.fromLTWH(0, 0, pdf.width.toDouble(), pdf.height.toDouble()),
          Rect.fromLTRB(
            box.left * sx,
            box.top * sy,
            box.right * sx,
            box.bottom * sy,
          ),
          Paint()..filterQuality = FilterQuality.medium,
        );
      final picture = recorder.endRecording();
      try {
        return picture.toImageSync(width, height);
      } finally {
        picture.dispose();
      }
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf renderStill $assetId #$pdfPageIndex');
      return null;
    } finally {
      pdf?.dispose();
    }
  }
}
