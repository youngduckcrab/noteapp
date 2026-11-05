// lib/src/ink_adapter/ink_background_builder.dart — 06-pdf 4.7, 6.8 (contract 7.2.16 /
// 7.2.19). One of the files allowed to import package:ink_engine (always `as ink`, 3).
//
// Foundation step B4 (T0): the paperOnly placeholder is real (handles, opaque paper,
// renderStill → null) — it is the first entry of ink.pageBackgroundBuildersProvider through
// pdfIoOverrides(). The renderer-backed builder (renderStill, the PdfPageBackgroundView
// body) comes with PDF T9.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

import '../render/page_background_view.dart';
import '../render/render_service.dart';
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
            color: Color(_opaqueArgb(ctx.background.paperColorArgb)),
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
  }) {
    if (_renderer == null) return Future<ui.Image?>.value();
    throw UnimplementedError('PdfBackgroundLayerBuilder.renderStill (PDF T9)');
  }

  /// The paper color with alpha forced to 0xFF, without bit operations (contract 7.4.3).
  static int _opaqueArgb(int argb) => 0xFF000000 + argb % 0x1000000;
}
