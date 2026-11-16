// lib/src/render/thumbnail_renderer.dart — contract 7.2.16 (03-ink 4.9, 6.17).
//
// 6.17: paper (or the still renderer's background, with its null rule) +
// strokes (layer painters: highlighter groups on the paper + fill outlines,
// pencil grain awaited up to 1 s) → Picture.toImage → PNG with the exact size,
// pageId and contentRevision (interop.thumbnailOf). The outlines are made with
// a yield to the event loop every 4 ms (INK T20), so a 3,000-stroke page never
// blocks a frame for long. No cache pool (6.17 step 3).
//
// (m5-7 T41, 6.20) Page objects: before anything is drawn the objects are
// prepared — every image object decoded at its thumbnail size from the image
// cache of the first ImageBackgroundLayerBuilder in the builder list (CP-INK-6;
// pinned while it is drawn; no such builder → the placeholder), NoteSans
// loaded when a text box has text (the implicit load — the web downloads it
// then), every formula that parses rasterized at the thumbnail scale (the
// raster host waits for its SVG glyphs). All of it within
// InkTuning.thumbnailObjectWaitMs (2 s), else — or when an image has no bytes,
// the fonts did not load or a formula raster is null — render returns null
// (callers never cache it and try later). Drawn in L-1 order (K-8,
// page_composite.dart): image objects → highlighter → strokes and shapes z
// mixed → text boxes, formulas, unknown objects → tapes (always covered).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:meta/meta.dart' show internal;
import 'package:note_core/note_core.dart' as core;

import '../background/background_builder.dart';
import '../background/background_spec.dart';
import '../background/builder_choice.dart';
import '../geometry/outline_generator.dart';
import '../geometry/stroke_outline.dart';
import '../image/image_cache.dart';
import '../interop/core_interop.dart' as interop;
import '../math/math_raster_cache.dart'
    show MathRaster, isRenderableMath, mathFormulaOf;
import '../math/math_renderer.dart' show rasterizeFormula;
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../text/fonts.dart';
import '../tuning.dart';
import 'page_composite.dart';
import 'pencil_grain.dart';
import 'pinned_raster_cache.dart';

final class InkPageThumbnailRenderer implements core.PageThumbnailRenderer {
  InkPageThumbnailRenderer({
    required List<PageBackgroundLayerBuilder> backgroundBuilders,
    PencilGrain? pencilGrain,
  }) : _backgroundBuilders = List.unmodifiable(backgroundBuilders),
       // the contract names the parameter pencilGrain; the field stays private
       // ignore: prefer_initializing_formals
       _pencilGrain = pencilGrain;

  final List<PageBackgroundLayerBuilder> _backgroundBuilders;
  final PencilGrain? _pencilGrain;

  /// Event-loop yields of the last render (6.17 step 5; tests).
  int _lastYields = 0;

  /// How long render waits for the pencil grain (6.17 step 3).
  static const Duration _grainWait = Duration(seconds: 1);

  /// Outline work between two yields (6.17 step 5).
  static const int _sliceUs = 4000;

  /// Paper + background (first builder that handles it AND is a PageBackgroundStillRenderer)
  /// + committed strokes → PNG via Picture.toImage + toByteData(png). Web (CanvasKit) safe.
  /// Returns null when the background still renderer returns null (e.g. PDF bytes missing).
  /// (v1.1) Also null for pdf / image backgrounds when no listed builder is a still renderer
  /// that handles them. Callers never cache a null result and retry later (LIBRARY 6.15.3).
  @override
  Future<core.PageThumbnail?> render(
    core.PageContent content, {
    int maxSidePx = 512,
  }) async {
    if (maxSidePx < 1) {
      throw ArgumentError.value(maxSidePx, 'maxSidePx', 'must be >= 1');
    }
    final page = content.page;
    final pw = page.size.width, ph = page.size.height;
    final int w, h;
    if (pw >= ph) {
      w = maxSidePx;
      h = math.max(1, (maxSidePx * ph / pw).round());
    } else {
      h = maxSidePx;
      w = math.max(1, (maxSidePx * pw / ph).round());
    }

    // (T41, 6.20 step 3) the objects first — nothing is drawn when they are not ready
    final strokes = [
      for (final s in content.strokes)
        if (s.deletedAt == null) InkStroke.of(s),
    ]..sort((a, b) => core.Stroke.compareOrder(a.source, b.source));
    final pageObjects = [
      for (final o in content.objects)
        if (o.deletedAt == null) o,
    ]..sort(core.Stroke.compareOrder);
    final objects = await _prepareObjects(pageObjects, w / pw);
    if (objects == null) return null;
    ui.Image? backgroundImage;
    ui.Picture? picture;
    ui.Image? image;
    try {
      // 6.17 step 2: background
      final spec = InkBackgroundSpec.fromCore(page.background);
      final still = stillRendererFor(_backgroundBuilders, spec);
      if (still != null) {
        backgroundImage = await still.renderStill(
          spec,
          pageSize: ui.Size(pw, ph),
          pixelSize: ui.Size(w.toDouble(), h.toDouble()),
        );
        if (backgroundImage == null) return null;
      } else if (spec.kind == InkBackgroundKind.pdf ||
          spec.kind == InkBackgroundKind.image) {
        return null;
      }

      // 6.17 step 3: strokes (highlighter layer below ink)
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final dst = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
      if (backgroundImage != null) {
        canvas.drawImageRect(
          backgroundImage,
          ui.Rect.fromLTWH(
            0,
            0,
            backgroundImage.width.toDouble(),
            backgroundImage.height.toDouble(),
          ),
          dst,
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
      } else {
        canvas.drawRect(
          dst,
          ui.Paint()..color = ui.Color(interop.opaqueArgb(spec.paperColorArgb)),
        );
      }
      canvas.scale(w / pw, h / ph);
      // 6.17 step 5: outlines with a yield every 4 ms
      final outlines = <InkStroke, StrokeOutline>{};
      var yields = 0;
      final watch = Stopwatch()..start();
      for (final s in strokes) {
        // (m5-7 T31) ink strokes and tapes (cover) — the highlighter is a polyline
        if (s.layer == InkLayer.highlighter) continue;
        outlines[s] = OutlineGenerator.outline(s);
        if (watch.elapsedMicroseconds >= _sliceUs) {
          yields++;
          await Future<void>.delayed(Duration.zero);
          watch.reset();
        }
      }
      _lastYields = yields;
      // 6.17 step 3: the pencil grain, waited for up to 1 s
      ui.Image? grain;
      if (strokes.any((s) => s.profile.textured)) grain = await _grain();
      // (T41) 6.20 step 4: L-1 order (K-8)
      paintPageComposite(
        canvas,
        strokes: strokes,
        objects: pageObjects,
        paperColorArgb: spec.paperColorArgb,
        outlineOf: (s) => outlines[s] ?? OutlineGenerator.outline(s),
        onePx: pw / w,
        grain: grain,
        marginPt: pw / w,
        imageOf: objects.imageOf,
        mathRasterOf: objects.mathRasterOf,
      );
      picture = recorder.endRecording();
      image = await picture.toImage(w, h);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      // 6.17 step 4: the result is made by interop.thumbnailOf only.
      return interop.thumbnailOf(
        page,
        width: w,
        height: h,
        png: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image?.dispose();
      picture?.dispose();
      backgroundImage?.dispose();
      objects.release();
    }
  }

  /// (T41, 6.20 step 3) Images, fonts and formula rasters of [objects] at [pxPerPt], all
  /// within InkTuning.thumbnailObjectWaitMs; null when one is missing or late (the
  /// preparations still running then clean up after themselves).
  Future<_ThumbnailObjects?> _prepareObjects(
    List<core.PageObject> objects,
    double pxPerPt,
  ) async {
    final prepared = _ThumbnailObjects();
    if (objects.isEmpty) return prepared;
    final cache = imageCacheOf(_backgroundBuilders);
    final work = <Future<bool>>[];
    var text = false;
    for (final o in objects) {
      switch (o) {
        case core.ImageObject():
          // no image builder in the list → the placeholder (CP-INK-6)
          if (cache != null) work.add(prepared.loadImage(cache, o, pxPerPt));
        case core.TextBoxObject():
          if (o.text.isNotEmpty) text = true;
        case core.MathObject():
          // a formula that does not parse is the 6.13 placeholder — never ready
          if (isRenderableMath(o)) work.add(prepared.rasterMath(o, pxPerPt));
        case core.ShapeObject() || core.UnknownObject():
          break;
      }
    }
    if (text) {
      work.add(
        InkFontsDebug.loadImplicitly().then((_) => InkFontsDebug.isLoaded),
      );
    }
    if (work.isEmpty) return prepared;
    var ready = false;
    try {
      final results = await Future.wait(
        work,
      ).timeout(const Duration(milliseconds: InkTuning.thumbnailObjectWaitMs));
      ready = results.every((r) => r);
    } on Object {
      ready = false;
    }
    if (!ready) {
      prepared.release();
      return null;
    }
    return prepared;
  }

  /// The grain when ready within [_grainWait]; null otherwise (no texture).
  Future<ui.Image?> _grain() async {
    final g = _pencilGrain;
    if (g == null) return null;
    final ready = g.value;
    if (ready != null) return ready;
    try {
      return await g.ready.timeout(_grainWait);
    } on Object {
      return null;
    }
  }
}

/// (T41) What one render draws its objects with: the decoded images (pinned) and the
/// formula rasters (owned — disposed by [release]). A preparation that finishes after
/// [release] (a late one) lets go of its result at once.
final class _ThumbnailObjects {
  final Map<String, ({ui.Image image, InkRasterPin pin})> _images = {};
  final Map<String, MathRaster> _maths = {};
  bool _released = false;

  ui.Image? imageOf(core.ImageObject o) => _images[o.id]?.image;

  MathRaster? mathRasterOf(core.MathObject o) => _maths[o.id];

  /// The decode of [o] at its thumbnail size; false when its bytes are missing
  /// (they may still arrive). (v2.13-thumbs) Bytes that do not decode or no
  /// store are never tried again: true — the placeholder, like the screen.
  Future<bool> loadImage(
    InkImageCache cache,
    core.ImageObject o,
    double pxPerPt,
  ) async {
    final r = o.frame.rect;
    final side = math.max(r.width, r.height) * pxPerPt;
    final entry = await cache.loadEntry(
      o.assetId,
      longSidePx: side.isFinite ? math.max(1, side.ceil()) : 1,
      pixelWidth: o.pixelWidth,
      pixelHeight: o.pixelHeight,
    );
    if (entry == null) {
      if (cache.isDisposed) return false;
      return switch (cache.statusOf(o.assetId)) {
        InkImageStatus.failed || InkImageStatus.storeUnavailable => true,
        InkImageStatus.ok || InkImageStatus.missing => false,
      };
    }
    if (_released || cache.isDisposed) return true;
    _images[o.id]?.pin.release();
    _images[o.id] = (
      image: entry.image,
      pin: cache.pin(o.assetId, entry.bucket),
    );
    return true;
  }

  /// The raster of [o] at [pxPerPt]; false when the raster host gave none.
  Future<bool> rasterMath(core.MathObject o, double pxPerPt) async {
    final r = await rasterizeFormula(
      o.latex,
      colorArgb: o.style.colorArgb,
      fontSizePt: o.style.fontSizePt,
      pixelsPerPt: pxPerPt,
    );
    if (r == null) return false;
    if (_released) {
      r.image.dispose();
      return true;
    }
    _maths.remove(o.id)?.image.dispose();
    _maths[o.id] = MathRaster.detached(mathFormulaOf(o), pxPerPt, r);
    return true;
  }

  void release() {
    _released = true;
    for (final e in _images.values) {
      e.pin.release();
    }
    _images.clear();
    for (final m in _maths.values) {
      m.image.dispose();
    }
    _maths.clear();
  }
}

/// INTERNAL (tests): the event-loop yields of [renderer]'s last render.
@internal
int thumbnailRendererYieldsOf(InkPageThumbnailRenderer renderer) =>
    renderer._lastYields;
