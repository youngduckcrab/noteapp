// lib/src/edit/eraser_spec.dart — contract 7.2.15 (03-ink 4.7); (v2.0) eraseShapes
// (m5-7/03-ink 4.6, 6.15).
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

enum EraserMode { stroke, partial }

/// Filter: all = every stroke, highlighterOnly = tool == highlighter, exceptHighlighter =
/// no highlighter. [radius] must be > 0 (InkPageController.beginErase throws ArgumentError).
/// (v2.0) [eraseShapes] (default true): touching a ShapeObject removes it whole (both modes;
/// never with highlighterOnly). Text boxes, images, formulas and unknown objects are never
/// erased (select → delete only).
@immutable
final class EraserSpec {
  const EraserSpec({
    required this.mode,
    required this.radius,
    this.filter = core.StrokeFilter.all,
    this.eraseShapes = true,
  });
  final EraserMode mode;

  /// pt (EDITOR stores the eraser size in pt)
  final double radius;
  final core.StrokeFilter filter;

  /// default true: touching a shape removes it whole
  final bool eraseShapes;

  @override
  bool operator ==(Object other) =>
      other is EraserSpec &&
      other.mode == mode &&
      other.radius == radius &&
      other.filter == filter &&
      other.eraseShapes == eraseShapes;

  @override
  int get hashCode => Object.hash(mode, radius, filter, eraseShapes);

  @override
  String toString() => 'EraserSpec(${mode.name}, $radius pt, ${filter.name})';
}
