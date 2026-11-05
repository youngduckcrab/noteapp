// lib/src/render/thumbnail_renderer.dart — contract 7.2.16 (03-ink 4.9, 6.17).
//
// 6.17: paper (or the still renderer's background, with its null rule) +
// strokes (layer painters: highlighter groups on the paper + fill outlines,
// pencil grain awaited up to 1 s) → Picture.toImage → PNG with the exact size,
// pageId and contentRevision (interop.thumbnailOf). The outlines are made with
// a yield to the event loop every 4 ms (INK T20), so a 3,000-stroke page never
// blocks a frame for long. No cache pool (6.17 step 3).
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
import '../interop/core_interop.dart' as interop;
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import 'layer_painters.dart';
import 'pencil_grain.dart';

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
  static const Duration grainWait = Duration(seconds: 1);

  /// Outline work between two yields (6.17 step 5).
  static const int sliceUs = 4000;

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

    // 6.17 step 2: background
    final spec = InkBackgroundSpec.fromCore(page.background);
    final still = stillRendererFor(_backgroundBuilders, spec);
    ui.Image? backgroundImage;
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
    final strokes = [
      for (final s in content.strokes)
        if (s.deletedAt == null) InkStroke.of(s),
    ]..sort((a, b) => core.Stroke.compareOrder(a.source, b.source));
    // 6.17 step 5: outlines with a yield every 4 ms
    final outlines = <InkStroke, StrokeOutline>{};
    var yields = 0;
    final watch = Stopwatch()..start();
    for (final s in strokes) {
      if (s.layer != InkLayer.ink) continue;
      outlines[s] = OutlineGenerator.outline(s);
      if (watch.elapsedMicroseconds >= sliceUs) {
        yields++;
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
    _lastYields = yields;
    // 6.17 step 3: the pencil grain, waited for up to 1 s
    ui.Image? grain;
    if (strokes.any((s) => s.profile.textured)) grain = await _grain();
    paintStrokeLayers(
      canvas,
      strokes,
      paperColorArgb: spec.paperColorArgb,
      outlineOf: (s) => outlines[s] ?? OutlineGenerator.outline(s),
      grain: grain,
      marginPt: pw / w,
    );
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
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
      picture.dispose();
      backgroundImage?.dispose();
    }
  }

  /// The grain when ready within [grainWait]; null otherwise (no texture).
  Future<ui.Image?> _grain() async {
    final g = _pencilGrain;
    if (g == null) return null;
    final ready = g.value;
    if (ready != null) return ready;
    try {
      return await g.ready.timeout(grainWait);
    } on Object {
      return null;
    }
  }
}

/// INTERNAL (tests): the event-loop yields of [renderer]'s last render.
@internal
int thumbnailRendererYieldsOf(InkPageThumbnailRenderer renderer) =>
    renderer._lastYields;
