// lib/src/object/object_painter.dart — INTERNAL (m5-7/03-ink 4.13, 6.8.4).
//
// Foundation step R2-B3: the simple drawing of every page object in its L-1
// layer. Shapes: (m5-7 T33) the final drawing of shape_path.dart — fill, line
// styles, arrow heads (6.9); text boxes: (m5-7 T34) the final drawing of 6.10.3 — in the
// frame coordinate system ① the background over the whole frame ② clipped to the frame
// ③ the paragraph of InkTextLayout (the system font until NoteSans is loaded: the
// paragraph cache is keyed by the instance and the loaded flag); an empty text without a
// background draws nothing;
// images: (m5-7 T35, 6.11.5) the decoded bucket stretched over the frame
// (drawImageRect, FilterQuality.medium — an unlocked aspect is drawn stretched), the
// paper-contrast box with two diagonals until it is there; formulas: (m5-7 T36, 6.12.3–6.12.4) the
// cached raster contain-fitted (centred, uniform scale) into the frame, a light box
// until it is there, the hatched box of 6.13 for a formula that does not parse
// (mathInvalid — the caller warns); unknown objects: a hatched box. Every object is drawn inside its CORE
// bounds (K-6). Colors come from the object or the paper (7.4.10 — no color
// literals). The render path never throws (4.0): a failing object is skipped
// and reported.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../math/math_raster_cache.dart';
import '../text/fonts.dart';
import '../text/text_layout.dart';
import '../tuning.dart';
import 'shape_path.dart';

/// Paints [o] in page pt. [onePx] = one logical px in pt (hairlines). Returns false when
/// painting failed (the caller warns). (T36) [mathRasterOf] gives the raster of a formula
/// to draw now (null → the placeholder; not given → always the placeholder). (T35)
/// [imageOf] gives the decoded image of an image object the same way.
bool paintObjectSimple(
  ui.Canvas canvas,
  core.PageObject o, {
  required int paperArgb,
  required double onePx,
  MathRaster? Function(core.MathObject o)? mathRasterOf,
  ui.Image? Function(core.ImageObject o)? imageOf,
}) {
  try {
    switch (o) {
      case core.ShapeObject():
        paintShape(canvas, o);
      case core.TextBoxObject():
        _inFrame(canvas, o.frame, (w, h) => _paintText(canvas, o, w, h));
      case core.ImageObject():
        final image = imageOf?.call(o);
        _inFrame(
          canvas,
          o.frame,
          (w, h) => image == null
              ? _paintImagePlaceholder(canvas, w, h, paperArgb, onePx)
              : paintImageStretched(
                  canvas,
                  image,
                  ui.Rect.fromLTWH(0, 0, w, h),
                ),
        );
      case core.MathObject():
        final raster = mathRasterOf?.call(o); // (also warns mathInvalid)
        if (!isRenderableMath(o)) {
          _inFrame(
            canvas,
            o.frame,
            (w, h) => _paintUnknown(canvas, w, h, paperArgb, onePx),
          );
          break;
        }
        _inFrame(
          canvas,
          o.frame,
          (w, h) => raster == null
              ? _paintMathBox(canvas, w, h, paperArgb)
              : paintMathRaster(canvas, raster, w, h),
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
/// fonts arrive. Moving or rotating a box is a new instance with the same frame width; its
/// paragraph is laid out again (cheap next to recording the chunk).
final Expando<(bool, ui.Paragraph)> _paragraphs = Expando('textBoxParagraph');

/// 6.10.3 inside the frame coordinate system (clipped to 0..w × 0..h by _inFrame — K-6).
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

/// (T35, 6.11.5) The whole [image] stretched over [dst] (an image object's frame: the
/// aspect differs only when the user unlocked it).
@internal
void paintImageStretched(ui.Canvas canvas, ui.Image image, ui.Rect dst) {
  if (dst.isEmpty) return;
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
}

/// (T36, 6.12.4 K-6) [raster] contain-fitted into the w × h frame (frame coordinates):
/// s = min(w / lw, h / lh) of its laid-out size (lw, lh), centred. The source is the
/// laid-out part of the image (lw·k × lh·k px — the image is rounded up).
@internal
void paintMathRaster(ui.Canvas canvas, MathRaster raster, double w, double h) {
  final lw = raster.sizePt.width, lh = raster.sizePt.height;
  if (!(lw > 0) || !(lh > 0)) return;
  final s = math.min(w / lw, h / lh);
  final dw = lw * s, dh = lh * s;
  final k = raster.pixelsPerPt;
  final image = raster.image;
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(
      0,
      0,
      math.min(lw * k, image.width.toDouble()),
      math.min(lh * k, image.height.toDouble()),
    ),
    ui.Rect.fromLTWH((w - dw) / 2, (h - dh) / 2, dw, dh),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
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
