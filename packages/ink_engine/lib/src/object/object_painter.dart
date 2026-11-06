// lib/src/object/object_painter.dart — INTERNAL (m5-7/03-ink 4.13, 6.8.4).
//
// Foundation step R2-B3: the simple drawing of every page object in its L-1
// layer. Shapes: (m5-7 T33) the final drawing of shape_path.dart — fill, line
// styles, arrow heads (6.9); text boxes: background, the NoteSans paragraph (the system
// font until NoteSans is loaded), clipped to the frame, rotated (T34);
// images: a gray placeholder box (T35); formulas: a light box (no raster —
// T36); unknown objects: a hatched box. Every object is drawn inside its CORE
// bounds (K-6). Colors come from the object or the paper (7.4.10 — no color
// literals). The render path never throws (4.0): a failing object is skipped
// and reported.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../text/fonts.dart';
import '../text/text_layout.dart';
import '../tuning.dart';
import 'shape_path.dart';

/// Paints [o] in page pt. [onePx] = one logical px in pt (hairlines). Returns false when
/// painting failed (the caller warns).
bool paintObjectSimple(
  ui.Canvas canvas,
  core.PageObject o, {
  required int paperArgb,
  required double onePx,
}) {
  try {
    switch (o) {
      case core.ShapeObject():
        paintShape(canvas, o);
      case core.TextBoxObject():
        _inFrame(canvas, o.frame, (w, h) => _paintText(canvas, o, w, h));
      case core.ImageObject():
        _inFrame(
          canvas,
          o.frame,
          (w, h) => _paintImagePlaceholder(canvas, w, h, paperArgb, onePx),
        );
      case core.MathObject():
        _inFrame(
          canvas,
          o.frame,
          (w, h) => _paintMathBox(canvas, w, h, paperArgb),
        );
      case core.UnknownObject():
        _inFrame(
          canvas,
          o.frame,
          (w, h) => _paintUnknown(canvas, w, h, paperArgb, onePx),
        );
    }
    return true;
  } on Object catch (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'ink_engine',
        context: ErrorDescription('while painting page object ${o.id}'),
      ),
    );
    return false;
  }
}

/// The paper-contrast tint of placeholders (6.11.5): light paper [amount] darker, dark
/// paper [amount] lighter. Arithmetic only (7.4.3).
int placeholderArgb(
  int paperArgb, {
  double amount = InkTuning.placeholderTint,
}) {
  final dark = core.PaperColors.isDark(paperArgb);
  int ch(int c) => dark
      ? (c + (255 - c) * amount).round().clamp(0, 255)
      : (c * (1 - amount)).round().clamp(0, 255);
  final r = ch((paperArgb ~/ 0x10000) % 256);
  final g = ch((paperArgb ~/ 0x100) % 256);
  final b = ch(paperArgb % 256);
  return 0xFF000000 + r * 0x10000 + g * 0x100 + b;
}

/// The frame coordinate system (6.8.4): translate(center) · rotate · translate(−w/2, −h/2),
/// clipped to the frame rectangle.
void _inFrame(
  ui.Canvas canvas,
  core.ElementFrame frame,
  void Function(double w, double h) paint,
) {
  final r = frame.rect;
  final w = r.width, h = r.height;
  if (!(w > 0) || !(h > 0) || !w.isFinite || !h.isFinite) return;
  final c = frame.center;
  canvas
    ..save()
    ..translate(c.x, c.y)
    ..rotate(frame.rotation.isFinite ? frame.rotation : 0)
    ..translate(-w / 2, -h / 2)
    ..clipRect(ui.Rect.fromLTWH(0, 0, w, h));
  try {
    paint(w, h);
  } finally {
    canvas.restore();
  }
}

/// (paragraph, laid out with NoteSans loaded?) per text box instance — rebuilt when the
/// fonts arrive.
final Expando<(bool, ui.Paragraph)> _paragraphs = Expando('textBoxParagraph');

void _paintText(ui.Canvas canvas, core.TextBoxObject o, double w, double h) {
  final background = o.style.backgroundArgb;
  if (background != null) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()..color = ui.Color(background),
    );
  }
  if (o.text.isEmpty) return;
  final size = o.style.fontSizePt, line = o.style.lineHeight;
  if (!(size > 0) || !size.isFinite || !(line > 0) || !line.isFinite) return;
  final loaded = InkFontsDebug.isLoaded;
  final cached = _paragraphs[o];
  final ui.Paragraph paragraph;
  if (cached != null && cached.$1 == loaded) {
    paragraph = cached.$2;
  } else {
    paragraph = buildTextBoxParagraph(o.text, o.style, w);
    _paragraphs[o] = (loaded, paragraph);
  }
  canvas.drawParagraph(paragraph, ui.Offset.zero);
}

void _paintImagePlaceholder(
  ui.Canvas canvas,
  double w,
  double h,
  int paperArgb,
  double onePx,
) {
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = ui.Color(placeholderArgb(paperArgb)),
  );
  final line = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = onePx
    ..color = ui.Color(
      placeholderArgb(paperArgb, amount: 3 * InkTuning.placeholderTint),
    );
  canvas
    ..drawLine(ui.Offset.zero, ui.Offset(w, h), line)
    ..drawLine(ui.Offset(w, 0), ui.Offset(0, h), line);
}

void _paintMathBox(ui.Canvas canvas, double w, double h, int paperArgb) {
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()
      ..color = ui.Color(
        placeholderArgb(paperArgb, amount: InkTuning.placeholderTint / 2),
      ),
  );
}

void _paintUnknown(
  ui.Canvas canvas,
  double w,
  double h,
  int paperArgb,
  double onePx,
) {
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w, h),
    ui.Paint()..color = ui.Color(placeholderArgb(paperArgb)),
  );
  final hatch = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = onePx
    ..color = ui.Color(
      placeholderArgb(paperArgb, amount: 3 * InkTuning.placeholderTint),
    );
  // 45° hatching every 8 logical px, clipped to the frame by _inFrame
  final step = math.max(8 * onePx, (w + h) / 512);
  for (var x = -h; x < w; x += step) {
    canvas.drawLine(ui.Offset(x, h), ui.Offset(x + h, 0), hatch);
  }
  final inset = onePx / 2;
  canvas.drawRect(
    ui.Rect.fromLTWH(
      inset,
      inset,
      math.max(0, w - onePx),
      math.max(0, h - onePx),
    ),
    hatch,
  );
}
