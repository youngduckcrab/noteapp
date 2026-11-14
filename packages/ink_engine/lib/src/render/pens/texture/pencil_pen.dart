// lib/src/render/pens/texture/pencil_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. Foundation state: no override — the plain fill
// of PenRenderer (looks like the base pen everywhere). See pen_renderer.dart
// for the rules (static, deterministic, inside core.Stroke.bounds).
import '../pen_renderer.dart';

const PenRenderer pencilPen = _PencilPen();

final class _PencilPen extends PenRenderer {
  const _PencilPen();
}
