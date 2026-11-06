// lib/src/math/math_preview.dart — contract 7.2.9 (m5-7/03-ink 4.9, parameter types 4.10,
// 6.12.5). Final (T26b): the real Math.tex widget from the foundation step on.
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'math_renderer.dart';

/// flutter_math_fork Math.tex with explicit textStyle (fontSize, color) — never SelectableMath.
/// A widget tree, not a raster: it stays sharp when the pad resizes it. Without a
/// Directionality ancestor it lays out LTR.
class MathPreview extends StatelessWidget {
  const MathPreview({
    super.key,
    required this.latex,
    required this.fontSize,
    required this.color,
    this.onError,
  });

  final String latex;

  /// logical px (the pad's display size)
  final double fontSize;
  final Color color;

  /// Called once per distinct (latex, message) after the frame (never during build) with
  /// InkMathRenderer.validate's message. The widget then shows nothing (size 0).
  final ValueChanged<String>? onError;

  @override
  Widget build(BuildContext context) {
    final error = InkMathRenderer.validate(latex);
    if (error != null) {
      _reportError(context, error);
      return const SizedBox.shrink();
    }
    _reported[context] = null;
    return mathWidget(latex, fontSize: fontSize, colorArgb: color.toARGB32());
  }

  void _reportError(BuildContext context, String message) {
    final callback = onError;
    if (callback == null) return;
    final key = (latex, message);
    if (_reported[context] == key) return;
    _reported[context] = key;
    SchedulerBinding.instance.addPostFrameCallback((_) => callback(message));
  }
}

/// The last (latex, message) reported by each MathPreview element (one call per distinct
/// pair, however often the widget rebuilds).
final Expando<(String, String)> _reported = Expando('mathPreviewError');
