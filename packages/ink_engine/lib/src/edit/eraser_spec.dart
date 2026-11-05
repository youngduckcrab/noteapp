// lib/src/edit/eraser_spec.dart — contract 7.2.15 (03-ink 4.7).
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

enum EraserMode { stroke, partial }

/// Filter: all = every stroke, highlighterOnly = tool == highlighter, exceptHighlighter =
/// no highlighter. [radius] must be > 0 (InkPageController.beginErase throws ArgumentError).
@immutable
final class EraserSpec {
  const EraserSpec({
    required this.mode,
    required this.radius,
    this.filter = core.StrokeFilter.all,
  });
  final EraserMode mode;

  /// pt (EDITOR stores the eraser size in pt)
  final double radius;
  final core.StrokeFilter filter;

  @override
  bool operator ==(Object other) =>
      other is EraserSpec &&
      other.mode == mode &&
      other.radius == radius &&
      other.filter == filter;

  @override
  int get hashCode => Object.hash(mode, radius, filter);

  @override
  String toString() => 'EraserSpec(${mode.name}, $radius pt, ${filter.name})';
}
