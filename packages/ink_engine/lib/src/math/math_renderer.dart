// lib/src/math/math_renderer.dart — contract 7.2.9 (m5-7/03-ink 4.9, rules 4.10, 6.12).
//
// validate and layout are final (T26b); rasterize (T36) runs on the raster
// host of offscreen_host.dart: queued one at a time, waiting for the SVG glyph
// pictures, ≤ 4 Mpx (6.12.2).
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;
import 'package:flutter_math_fork/tex.dart' as tex;
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import 'offscreen_host.dart';

// --- math, fonts, text layout: 추가 ---
abstract final class InkMathRenderer {
  /// null = renderable; else a short English error (unknown command …) for the LaTeX editor.
  /// 'Empty formula', 'Formula is too long' (> PageObjectLimits.maxLatexLength), the parser's
  /// ParseException.message (e.g. "Expected '}', got 'EOF'", 'Undefined control sequence:
  /// \foo'), the builder's BuildException.message, else 'Unsupported formula'.
  static String? validate(String latex) => switch (_parse(latex)) {
    (_, final String error) => error,
    (final tex.SyntaxTree ast, _) => _buildError(ast),
    _ => _unsupported,
  };

  /// size in pt. fontSizePt = logical px (page pt are drawn as logical units). null for an
  /// invalid formula. Synchronous and only OUTSIDE the frame phases (build / layout / paint
  /// → StateError — S-9); EDITOR and recog call it from events and Futures.
  static InkMathLayout? layout(String latex, {required double fontSizePt}) {
    if (OffscreenMathHost.inFramePhase) {
      throw StateError(
        'InkMathRenderer.layout cannot run during a build, layout or paint phase',
      );
    }
    if (!(fontSizePt > 0) || !fontSizePt.isFinite) {
      throw ArgumentError.value(fontSizePt, 'fontSizePt', 'must be > 0');
    }
    if (validate(latex) != null) return null;
    final result = OffscreenMathHost.layoutHost.layout(
      mathWidget(latex, fontSize: fontSizePt, colorArgb: 0xFF000000),
    );
    if (result == null) return null;
    return InkMathLayout._(sizePt: result.size, baselinePt: result.baseline);
  }

  /// Offscreen raster (thumbnails, PDF at 300 dpi, screen cache buckets). Web (CanvasKit) safe.
  /// (v2.1) Waits for asynchronously loaded glyph pictures (\sqrt, stretchy arrows / braces —
  /// flutter_svg) before capturing, bounded in count and time; returns null rather than an
  /// incomplete image. Requests are served one at a time. Output ≤ 4 Mpx (7.4.5): pixelsPerPt is
  /// lowered to fit.
  /// The caller owns the image (dispose it). null also for an invalid formula and a
  /// fontSizePt / pixelsPerPt that is not a positive finite number. Never throws.
  static Future<ui.Image?> rasterize(
    String latex, {
    required int colorArgb,
    required double fontSizePt,
    required double pixelsPerPt,
  }) async {
    final r = await rasterizeFormula(
      latex,
      colorArgb: colorArgb,
      fontSizePt: fontSizePt,
      pixelsPerPt: pixelsPerPt,
    );
    return r?.image;
  }

  static const String _unsupported = 'Unsupported formula';

  /// (ast, null) or (null, error).
  static (tex.SyntaxTree?, String?) _parse(String latex) {
    if (latex.trim().isEmpty) return (null, 'Empty formula');
    if (latex.length > core.PageObjectLimits.maxLatexLength) {
      return (null, 'Formula is too long');
    }
    try {
      final root = tex.TexParser(latex, const fm.TexParserSettings()).parse();
      return (tex.SyntaxTree(greenRoot: root), null);
    } on fm.ParseException catch (e) {
      return (null, e.message);
    } on Object {
      return (null, _unsupported);
    }
  }

  static String? _buildError(tex.SyntaxTree ast) {
    try {
      ast.buildWidget(
        fm.MathOptions(
          style: fm.MathStyle.display,
          fontSize: 18,
          color: const ui.Color(0xFF000000),
        ),
      );
      return null;
    } on fm.BuildException catch (e) {
      return e.message;
    } on Object {
      return _unsupported;
    }
  }
}

@immutable
final class InkMathLayout {
  const InkMathLayout._({required this.sizePt, required this.baselinePt});
  final Size sizePt;
  final double baselinePt;

  @override
  bool operator ==(Object other) =>
      other is InkMathLayout &&
      other.sizePt == sizePt &&
      other.baselinePt == baselinePt;

  @override
  int get hashCode => Object.hash(sizePt, baselinePt);

  @override
  String toString() => 'InkMathLayout($sizePt, baseline $baselinePt)';
}

/// INTERNAL (T36): [InkMathRenderer.rasterize] with the laid-out size the raster was
/// captured from (pt) — the screen cache keeps it for the contain fit (6.12.3).
@internal
Future<OffscreenRaster?> rasterizeFormula(
  String latex, {
  required int colorArgb,
  required double fontSizePt,
  required double pixelsPerPt,
}) {
  if (!(fontSizePt > 0) ||
      !fontSizePt.isFinite ||
      !(pixelsPerPt > 0) ||
      !pixelsPerPt.isFinite ||
      latex.trim().isEmpty ||
      latex.length > core.PageObjectLimits.maxLatexLength) {
    return Future<OffscreenRaster?>.value();
  }
  return OffscreenMathHost.rasterHost.raster(
    (
      latex: latex,
      colorArgb: colorArgb,
      fontSizePt: fontSizePt,
      pixelsPerPt: pixelsPerPt,
    ),
    // built on the job's timer turn: an invalid formula builds nothing (→ null)
    () => InkMathRenderer.validate(latex) == null
        ? mathWidget(latex, fontSize: fontSizePt, colorArgb: colorArgb)
        : const SizedBox.shrink(),
  );
}

/// INTERNAL: the formula widget INK lays out and previews — flutter_math_fork Math.tex with
/// explicit options (display style, fontSize, color) and textStyle, never SelectableMath,
/// LTR. Errors → nothing (size 0).
@internal
Widget mathWidget(
  String latex, {
  required double fontSize,
  required int colorArgb,
  fm.OnErrorFallback? onErrorFallback,
}) {
  final color = ui.Color(colorArgb);
  return Directionality(
    textDirection: TextDirection.ltr,
    child: fm.Math.tex(
      latex,
      options: fm.MathOptions(
        style: fm.MathStyle.display,
        fontSize: fontSize,
        color: color,
      ),
      textStyle: TextStyle(fontSize: fontSize, color: color),
      onErrorFallback: onErrorFallback ?? (_) => const SizedBox.shrink(),
    ),
  );
}
