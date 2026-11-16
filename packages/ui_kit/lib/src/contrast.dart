/// WCAG contrast ratio (01-infra 14.5: text ≥ 4.5:1, icons ≥ 3:1).
library;

import 'package:material_ui/material_ui.dart';

/// The WCAG 2 contrast ratio of [a] and [b] (1 … 21). Translucent colours
/// are first blended over [over] (default: [b] when [b] is opaque, else
/// white).
double contrastRatio(Color a, Color b, {Color? over}) {
  final base = over ?? (b.a >= 1 ? b : const Color(0xFFFFFFFF));
  final fg = a.a >= 1 ? a : Color.alphaBlend(a, base);
  final bg = b.a >= 1 ? b : Color.alphaBlend(b, base);
  final l1 = fg.computeLuminance();
  final l2 = bg.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}
