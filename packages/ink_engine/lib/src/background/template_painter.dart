// lib/src/background/template_painter.dart — INTERNAL (not exported): paints
// paper + TemplateVectors (03-ink 6.16, 6.17).
//
// Screen: the items are recorded once per (template, page size, paper color,
// line-width bucket) into a Picture in page pt and reused (small LRU); the
// painter fills the opaque paper, scales by ctx.viewScale (never by
// ancestorScale — contract 7.2.16 v1.1) and draws the Picture. Lines thinner
// than one device pixel are drawn max(width, 1 / deviceScale) wide, where
// deviceScale = ctx.deviceScale (ancestorScale included); the bucket rounds
// that minimum to quarter steps of log2 so a pinch does not re-record every
// frame. renderStill / thumbnails use the same paint routine on pixelSize.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../interop/core_interop.dart' as interop;
import 'background_spec.dart';
import 'template_vectors.dart';

/// Quarter steps of log2(deviceScale) (floor), so the minimum width
/// 1 / 2^(bucket / 4) pt is never below one device pixel.
@visibleForTesting
int lineWidthBucketOf(double deviceScale) {
  if (!(deviceScale > 0) || !deviceScale.isFinite) return 0;
  return (4 * math.log(deviceScale) / math.ln2).floor();
}

/// The minimum on-screen line width (pt) of [bucket].
@visibleForTesting
double minLineWidthPtOf(int bucket) => 1 / math.pow(2, bucket / 4);

/// Paints [items] (page pt) on [canvas]; lines at least [minWidthPt] wide,
/// dots at least [minWidthPt] across.
void paintTemplateItems(
  ui.Canvas canvas,
  List<TemplateVectorItem> items, {
  required double minWidthPt,
}) {
  final line = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.butt
    ..isAntiAlias = true;
  // dots: one drawRawPoints per (color, diameter) with round caps
  final dots = <(int, double), List<double>>{};
  for (final item in items) {
    switch (item) {
      case TemplateLine(:final p0, :final p1, :final width, :final colorArgb):
        line
          ..color = ui.Color(colorArgb)
          ..strokeWidth = math.max(width, minWidthPt);
        canvas.drawLine(p0, p1, line);
      case TemplateDot(:final center, :final radius, :final colorArgb):
        (dots[(colorArgb, math.max(2 * radius, minWidthPt))] ??= []).addAll([
          center.dx,
          center.dy,
        ]);
    }
  }
  dots.forEach((key, xy) {
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(xy),
      ui.Paint()
        ..color = ui.Color(key.$1)
        ..strokeWidth = key.$2
        ..strokeCap = ui.StrokeCap.round
        ..isAntiAlias = true,
    );
  });
}

/// Paper + template of [spec] on a [pageSize] page, scaled by (sx, sy).
void paintPaperAndTemplate(
  ui.Canvas canvas,
  InkBackgroundSpec spec,
  Size pageSize, {
  required double sx,
  required double sy,
  required double minWidthPt,
}) {
  canvas.drawRect(
    Rect.fromLTWH(0, 0, pageSize.width * sx, pageSize.height * sy),
    ui.Paint()..color = ui.Color(interop.opaqueArgb(spec.paperColorArgb)),
  );
  final template = spec.template;
  if (spec.kind != InkBackgroundKind.template || template == null) return;
  canvas
    ..save()
    ..scale(sx, sy);
  paintTemplateItems(
    canvas,
    TemplateVectors.build(
      template,
      pageSize: pageSize,
      paperColorArgb: spec.paperColorArgb,
    ),
    minWidthPt: minWidthPt,
  );
  canvas.restore();
}

/// Recorded template Pictures (page pt), least recently used first.
abstract final class TemplatePictureCache {
  static const int maxEntries = 16;
  static final LinkedHashMap<Object, ui.Picture> _pictures = LinkedHashMap();

  /// Number of recordings so far (tests).
  @visibleForTesting
  static int recordings = 0;

  @visibleForTesting
  static int get length => _pictures.length;

  /// The Picture of [spec]'s template lines (no paper) at [bucket].
  static ui.Picture pictureOf(
    InkBackgroundSpec spec,
    Size pageSize,
    int bucket,
  ) {
    final key = (spec.template, pageSize, spec.paperColorArgb, bucket);
    final hit = _pictures.remove(key);
    if (hit != null) return _pictures[key] = hit;
    final recorder = ui.PictureRecorder();
    paintTemplateItems(
      ui.Canvas(recorder),
      TemplateVectors.build(
        spec.template!,
        pageSize: pageSize,
        paperColorArgb: spec.paperColorArgb,
      ),
      minWidthPt: minLineWidthPtOf(bucket),
    );
    recordings++;
    final picture = recorder.endRecording();
    _pictures[key] = picture;
    while (_pictures.length > maxEntries) {
      final oldest = _pictures.keys.first;
      _pictures.remove(oldest)!.dispose();
    }
    return picture;
  }

  @visibleForTesting
  static void clear() {
    for (final p in _pictures.values) {
      p.dispose();
    }
    _pictures.clear();
    recordings = 0;
  }
}

/// The screen painter of TemplateBackgroundLayerBuilder.build.
final class TemplatePainter extends CustomPainter {
  TemplatePainter({
    required this.spec,
    required this.pageSize,
    required this.viewScale,
    required this.deviceScale,
  }) : bucket = lineWidthBucketOf(deviceScale);

  final InkBackgroundSpec spec;
  final Size pageSize;

  /// logical px per pt (layout)
  final double viewScale;

  /// ctx.deviceScale — line minimum and Picture bucket only
  final double deviceScale;
  final int bucket;

  /// The minimum line width in pt (one device pixel or a little more).
  double get minLineWidthPt => minLineWidthPtOf(bucket);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(interop.opaqueArgb(spec.paperColorArgb)),
    );
    if (spec.kind != InkBackgroundKind.template || spec.template == null) {
      return;
    }
    canvas
      ..save()
      ..scale(viewScale)
      ..drawPicture(TemplatePictureCache.pictureOf(spec, pageSize, bucket))
      ..restore();
  }

  @override
  bool shouldRepaint(TemplatePainter old) =>
      old.spec != spec ||
      old.pageSize != pageSize ||
      old.viewScale != viewScale ||
      old.bucket != bucket;
}
