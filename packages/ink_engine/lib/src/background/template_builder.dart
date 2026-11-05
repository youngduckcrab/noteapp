// lib/src/background/template_builder.dart — contract 7.2.16 (03-ink 4.10,
// 6.16, 6.17): paper + the six page templates, also the fallback that paints
// the paper only for backgrounds no builder handles (image / unknown, pdf
// without a PDF builder).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'background_builder.dart';
import 'background_spec.dart';
import 'template_painter.dart';

final class TemplateBackgroundLayerBuilder
    implements PageBackgroundLayerBuilder, PageBackgroundStillRenderer {
  /// blank + all six template kinds; fallback = paper
  const TemplateBackgroundLayerBuilder();

  /// kind == blank || kind == template
  @override
  bool handles(InkBackgroundSpec background) =>
      background.kind == InkBackgroundKind.blank ||
      background.kind == InkBackgroundKind.template;

  /// paper + TemplateVectors (6.16). Size = pageSize × ctx.viewScale (never ×
  /// ancestorScale); the painter scales by ctx.viewScale; ctx.deviceScale only
  /// sets the minimum line width (1 device px) and the Picture bucket.
  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) => SizedBox(
    width: ctx.pageSize.width * ctx.viewScale,
    height: ctx.pageSize.height * ctx.viewScale,
    child: CustomPaint(
      painter: TemplatePainter(
        spec: ctx.background,
        pageSize: ctx.pageSize,
        viewScale: ctx.viewScale,
        deviceScale: ctx.deviceScale,
      ),
    ),
  );

  /// paper + template lines on a pixelSize image (lines at least 1 px).
  @override
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) {
    final w = pixelSize.width.round().clamp(1, 16384);
    final h = pixelSize.height.round().clamp(1, 16384);
    final pw = pageSize.width > 0 ? pageSize.width : w.toDouble();
    final ph = pageSize.height > 0 ? pageSize.height : h.toDouble();
    final sx = w / pw, sy = h / ph;
    final recorder = ui.PictureRecorder();
    paintPaperAndTemplate(
      ui.Canvas(recorder),
      background,
      Size(pw, ph),
      sx: sx,
      sy: sy,
      minWidthPt: 1 / math.min(sx, sy),
    );
    final picture = recorder.endRecording();
    return picture.toImage(w, h).whenComplete(picture.dispose);
  }
}
