// lib/src/background/template_builder.dart — contract 7.2.16 (03-ink 4.10).
//
// Foundation step B3 (03-ink 4.15): paper color only (build and renderStill).
// Template lines (TemplateVectors, 6.16) come with INK T13 / T13b.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../interop/core_interop.dart' as interop;
import 'background_builder.dart';
import 'background_spec.dart';

final class TemplateBackgroundLayerBuilder
    implements PageBackgroundLayerBuilder, PageBackgroundStillRenderer {
  /// blank + all six template kinds; fallback = paper
  const TemplateBackgroundLayerBuilder();

  /// kind == blank || kind == template
  @override
  bool handles(InkBackgroundSpec background) =>
      background.kind == InkBackgroundKind.blank ||
      background.kind == InkBackgroundKind.template;

  /// paper + TemplateVectors (6.16). Size = pageSize × ctx.viewScale (never × ancestorScale).
  @override
  Widget build(BuildContext context, PageBackgroundContext ctx) => SizedBox(
    width: ctx.pageSize.width * ctx.viewScale,
    height: ctx.pageSize.height * ctx.viewScale,
    child: ColoredBox(
      color: Color(interop.opaqueArgb(ctx.background.paperColorArgb)),
    ),
  );

  /// paper + template lines
  @override
  Future<ui.Image?> renderStill(
    InkBackgroundSpec background, {
    required Size pageSize,
    required Size pixelSize,
  }) {
    final w = pixelSize.width.round().clamp(1, 16384);
    final h = pixelSize.height.round().clamp(1, 16384);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Color(interop.opaqueArgb(background.paperColorArgb)),
    );
    final picture = recorder.endRecording();
    return picture.toImage(w, h).whenComplete(picture.dispose);
  }
}
