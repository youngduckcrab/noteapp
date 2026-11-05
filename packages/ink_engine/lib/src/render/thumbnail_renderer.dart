// lib/src/render/thumbnail_renderer.dart — contract 7.2.16 (03-ink 4.9, 6.17).
//
// Foundation step B3 (03-ink 4.15): paper (or the still renderer's background)
// + strokes (layer painters: highlighter groups + fill outlines, INK T08) → PNG
// with the exact size, pageId and contentRevision; pdf / image backgrounds
// follow the still-renderer null rule already. Grain and time slicing come with
// INK T20.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;

import '../background/background_builder.dart';
import '../background/background_spec.dart';
import '../background/builder_choice.dart';
import '../geometry/outline_generator.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';
import 'layer_painters.dart';
import 'pencil_grain.dart';

final class InkPageThumbnailRenderer implements core.PageThumbnailRenderer {
  InkPageThumbnailRenderer({
    required List<PageBackgroundLayerBuilder> backgroundBuilders,
    PencilGrain? pencilGrain,
  }) : _backgroundBuilders = List.unmodifiable(backgroundBuilders);

  // [pencilGrain] is used for the pencil texture from INK T20 (no grain yet).
  final List<PageBackgroundLayerBuilder> _backgroundBuilders;

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
        if (s.deletedAt == null) s,
    ]..sort(core.Stroke.compareOrder);
    paintStrokeLayers(
      canvas,
      strokes.map(InkStroke.of),
      paperColorArgb: spec.paperColorArgb,
      outlineOf: OutlineGenerator.outline,
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
}
