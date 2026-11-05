// lib/src/edit/ink_edit.dart — contract 7.2.15 (03-ink 4.6). Final implementation.
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

// --- edit result: one gesture = one InkEdit = one CORE command ---
enum InkEditKind {
  addStroke,
  eraseStrokes,
  splitStrokes,
  transformStrokes,
  recolorStrokes,
  deleteStrokes,
  duplicateStrokes,
}

/// One gesture = one InkEdit = one CORE command (toCommand, table 4.6 / contract 7.2.15).
/// Invariants: every stroke of [added] has version == null, pageId == [pageId] and a
/// normalized style. [removedIds] / [targetIds] are filled in z-order (insertion-ordered
/// sets), so toCommand() is deterministic. Sessions and selections never return an edit
/// that [isEmpty] (they return null instead).
@immutable
final class InkEdit {
  const InkEdit({
    required this.pageId,
    required this.kind,
    this.added = const [],
    this.removedIds = const {},
    this.targetIds = const {},
    this.transform,
    this.colorArgb,
  });
  final String pageId;
  final InkEditKind kind;

  /// new strokes / fragments / duplicates (version == null)
  final List<core.Stroke> added;

  /// erased / deleted / split originals
  final Set<String> removedIds;

  /// transformStrokes / recolorStrokes
  final Set<String> targetIds;

  /// transformStrokes
  final core.Affine2? transform;

  /// recolorStrokes
  final int? colorArgb;

  /// The fields the kind needs are empty.
  bool get isEmpty => switch (kind) {
    InkEditKind.addStroke || InkEditKind.duplicateStrokes => added.isEmpty,
    InkEditKind.eraseStrokes ||
    InkEditKind.deleteStrokes ||
    InkEditKind.splitStrokes => removedIds.isEmpty,
    InkEditKind.transformStrokes => targetIds.isEmpty || transform == null,
    InkEditKind.recolorStrokes => targetIds.isEmpty || colorArgb == null,
  };

  /// Table 4.6 / contract 7.2.15. StateError when [isEmpty].
  core.EditCommand toCommand() {
    if (isEmpty) {
      throw StateError('InkEdit(${kind.name}) is empty; no command to make');
    }
    return switch (kind) {
      InkEditKind.addStroke || InkEditKind.duplicateStrokes => core.AddStrokes(
        pageId: pageId,
        strokes: List.unmodifiable(added),
      ),
      InkEditKind.eraseStrokes ||
      InkEditKind.deleteStrokes => core.RemoveStrokes(
        pageId: pageId,
        strokeIds: removedIds.toList(growable: false),
      ),
      InkEditKind.splitStrokes =>
        added.isEmpty
            ? core.RemoveStrokes(
                pageId: pageId,
                strokeIds: removedIds.toList(growable: false),
              )
            : core.SplitStrokes(
                pageId: pageId,
                removedIds: removedIds.toList(growable: false),
                added: List.unmodifiable(added),
              ),
      InkEditKind.transformStrokes => core.TransformElements(
        pageId: pageId,
        elementIds: targetIds.toList(growable: false),
        transform: transform!,
        scaleStrokeWidth: true,
      ),
      InkEditKind.recolorStrokes => core.RestyleStrokes(
        pageId: pageId,
        strokeIds: targetIds.toList(growable: false),
        patch: core.StrokeStylePatch(colorArgb: colorArgb),
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is InkEdit &&
      other.pageId == pageId &&
      other.kind == kind &&
      other.transform == transform &&
      other.colorArgb == colorArgb &&
      _listEquals(other.added, added) &&
      _setEquals(other.removedIds, removedIds) &&
      _setEquals(other.targetIds, targetIds);

  @override
  int get hashCode => Object.hash(
    pageId,
    kind,
    transform,
    colorArgb,
    Object.hashAll(added.map(identityHashCode)),
    Object.hashAllUnordered(removedIds),
    Object.hashAllUnordered(targetIds),
  );

  @override
  String toString() =>
      'InkEdit(${kind.name}, $pageId, +${added.length} '
      '-${removedIds.length} ~${targetIds.length})';

  static bool _listEquals(List<core.Stroke> a, List<core.Stroke> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _setEquals(Set<String> a, Set<String> b) =>
      identical(a, b) || (a.length == b.length && a.containsAll(b));
}
