// lib/src/render/pens/decor/glitter_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE DECOR TRACK. Foundation state: no override — the plain fill
// of PenRenderer (looks like the base pen everywhere). See pen_renderer.dart
// for the rules (static, deterministic, inside core.Stroke.bounds).
import '../pen_renderer.dart';

const PenRenderer glitterPen = _GlitterPen();

final class _GlitterPen extends PenRenderer {
  const _GlitterPen();
}
