// lib/src/text/text_layout.dart — contract 7.2.9 (m5-7/03-ink 4.9, rules 4.10, 6.10.2).
// Final (T26a).
//
// One paragraph builder for everything that lays out a text box: the
// annotation layer, measure / measureSync (EDITOR's frame height), the PDF
// raster fallback (rasterize) and — through textStyleOf / strutStyleOf —
// EDITOR's EditableText (zero inner padding, CP-INK-3), so the text never
// jumps when an edit session ends (E-6).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../interop/core_interop.dart' as interop;
import '../tuning.dart';
import 'fonts.dart';

abstract final class InkTextLayout {
  /// Height EDITOR writes into TextBoxObject.frame for the given width (same metrics INK paints with).
  /// Size(widthPt, max(paragraph height, one line)); waits for a running or new NoteSans load
  /// (≤ 5 s; after a failure, a timeout or a failure in the last 30 s → measured with the
  /// fallback font, no exception). No inner padding.
  static Future<Size> measure(
    String text,
    core.TextBoxStyle style, {
    required double widthPt,
  }) async {
    await InkFontsDebug.loadImplicitly();
    return _measure(text, style, widthPt);
  }

  /// (v2.1) Same value as measure once InkFonts is loaded; null before (EDITOR live drafts).
  /// Also the fallback-font value once a load has failed; null before the first attempt and
  /// while one runs (and starts one).
  static Size? measureSync(
    String text,
    core.TextBoxStyle style, {
    required double widthPt,
  }) {
    if (!InkFontsDebug.isSettled) {
      unawaited(InkFontsDebug.loadImplicitly());
      if (!InkFontsDebug.isSettled) return null;
    }
    return _measure(text, style, widthPt);
  }

  /// (v2.1, CP-INK-3) The paragraph style INK paints with. EDITOR's text editor uses exactly these
  /// with zero inner padding, so the text does not jump when the session ends (E-6).
  /// TextStyle(fontFamily: 'NoteSans', fontSize: fontSizePt, height: lineHeight,
  /// color: colorArgb (alpha 0xFF), fontWeight: bold ? w700 : w400). The same value before the
  /// fonts are loaded (the engine draws a fallback font for the family then).
  static TextStyle textStyleOf(core.TextBoxStyle style) => TextStyle(
    fontFamily: InkFonts.noteSans,
    fontSize: style.fontSizePt,
    height: style.lineHeight,
    color: Color(interop.opaqueArgb(style.colorArgb)),
    fontWeight: style.bold ? FontWeight.w700 : FontWeight.w400,
  );

  /// forceStrutHeight: true, height = lineHeight
  static StrutStyle strutStyleOf(core.TextBoxStyle style) => StrutStyle(
    fontFamily: InkFonts.noteSans,
    fontSize: style.fontSizePt,
    height: style.lineHeight,
    forceStrutHeight: true,
  );

  /// (v2.1, CP-PDF-7) Frame-size raster on a transparent background (box background not drawn),
  /// same 4 Mpx cap as InkMathRenderer.rasterize — PDF raster fallback.
  /// ⌈w·k⌉ × ⌈h·k⌉ px of the unrotated frame, k = pixelsPerPt lowered to InkTuning.maxRasterPixels
  /// and InkTuning.maxRasterSidePx; the text clipped to the frame. Waits for the fonts (fallback
  /// font after a failure). A zero frame side → null; any other failure → null (never throws).
  static Future<ui.Image?> rasterize(
    core.TextBoxObject object, {
    required double pixelsPerPt,
  }) async {
    final rect = object.frame.rect;
    final w = rect.width, h = rect.height;
    if (!(w > 0) || !(h > 0) || !(pixelsPerPt > 0)) return null;
    final k = rasterScaleFor(w, h, pixelsPerPt);
    final pw = (w * k).ceil(), ph = (h * k).ceil();
    if (pw < 1 || ph < 1) return null;
    await InkFontsDebug.loadImplicitly();
    ui.Picture? picture;
    try {
      final paragraph = buildTextBoxParagraph(object.text, object.style, w);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..scale(k)
        ..clipRect(Rect.fromLTWH(0, 0, w, h))
        ..drawParagraph(paragraph, Offset.zero);
      picture = recorder.endRecording();
      return await picture.toImage(pw, ph);
    } on Object {
      return null;
    } finally {
      picture?.dispose();
    }
  }

  static Size _measure(String text, core.TextBoxStyle style, double widthPt) {
    final width = widthPt.isFinite && widthPt > 0 ? widthPt : 0.0;
    final p = buildTextBoxParagraph(text, style, width);
    final line = style.fontSizePt * style.lineHeight;
    final height = math.max(p.height, line.isFinite ? line : 0.0);
    p.dispose();
    return Size(widthPt, height);
  }
}

/// INTERNAL: the one paragraph of a text box (6.10.2) — ParagraphStyle(align start → left,
/// center, end → right (LTR)) + strutStyleOf + textStyleOf, laid out at [widthPt].
@internal
ui.Paragraph buildTextBoxParagraph(
  String text,
  core.TextBoxStyle style,
  double widthPt,
) {
  final textStyle = InkTextLayout.textStyleOf(style);
  final builder =
      ui.ParagraphBuilder(
          textStyle.getParagraphStyle(
            textAlign: textAlignOf(style.align),
            textDirection: TextDirection.ltr,
            strutStyle: InkTextLayout.strutStyleOf(style),
          ),
        )
        ..pushStyle(textStyle.getTextStyle())
        ..addText(text);
  return builder.build()
    ..layout(ui.ParagraphConstraints(width: math.max(0, widthPt)));
}

/// INTERNAL: TextAlignKind → TextAlign (LTR: start → left, end → right).
@internal
TextAlign textAlignOf(core.TextAlignKind align) => switch (align) {
  core.TextAlignKind.start => TextAlign.left,
  core.TextAlignKind.center => TextAlign.center,
  core.TextAlignKind.end => TextAlign.right,
};

/// INTERNAL: the raster scale k for a w × h pt box (7.4.5): min(pixelsPerPt,
/// √(maxRasterPixels / (w·h)), maxRasterSidePx / max(w, h)).
@internal
double rasterScaleFor(double w, double h, double pixelsPerPt) {
  var k = pixelsPerPt;
  final area = w * h;
  if (area > 0) {
    k = math.min(k, math.sqrt(InkTuning.maxRasterPixels / area));
  }
  final side = math.max(w, h);
  if (side > 0) k = math.min(k, InkTuning.maxRasterSidePx / side);
  // ⌈w·k⌉·⌈h·k⌉ may still be a little above the cap: shrink until it fits
  while (k > 0 && (w * k).ceil() * (h * k).ceil() > InkTuning.maxRasterPixels) {
    k *= 0.999;
  }
  return k;
}
