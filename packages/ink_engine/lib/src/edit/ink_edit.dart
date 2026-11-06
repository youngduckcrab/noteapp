// lib/src/edit/ink_edit.dart — contract 7.2.15 (03-ink 4.6), 2nd round contract 7.2.9 v2.1
// (m5-7/03-ink 4.6, 4.10 'InkEdit v2.1'). Final implementation (T24).
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
  addShape,
}

/// One gesture = one InkEdit = one CORE command (toCommand, table 4.6 / contract 7.2.9 v2.1).
/// Invariants: every stroke of [added] has version == null, pageId == [pageId] and a
/// normalized style. [removedIds] / [targetIds] are filled in z-order (insertion-ordered
/// sets), so toCommand() is deterministic. Sessions and selections never return an edit
/// that [isEmpty] (they return null instead) — except InkSelection.recolor when nothing
/// can be recolored (images / unknown objects only, 03-ink 4.10 S-14).
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
    this.addedObjects = const [],
    this.updatedObjects = const [],
    this.removedObjectIds = const {},
  });
  final String pageId;
  final InkEditKind kind;

  /// new strokes / fragments / duplicates (version == null)
  final List<core.Stroke> added;

  /// erased / deleted / split originals — strokes AND objects (every removed id)
  final Set<String> removedIds;

  /// transformStrokes / recolorStrokes — strokes AND objects
  final Set<String> targetIds;

  /// transformStrokes
  final core.Affine2? transform;

  /// recolorStrokes
  final int? colorArgb;

  /// addShape, duplicateStrokes
  final List<core.PageObject> addedObjects;

  /// recolorStrokes on objects
  final List<core.PageObject> updatedObjects;

  /// (v2.1, INK C-3) Which of removedIds are objects — public optional constructor argument
  /// (default const {}); removedIds keeps every removed id; part of ==. A public-constructed
  /// eraseStrokes with a shape id therefore removes the shape instead of being ignored.
  final Set<String> removedObjectIds;

  /// The fields the kind needs are empty.
  bool get isEmpty => switch (kind) {
    InkEditKind.addStroke => added.isEmpty,
    InkEditKind.duplicateStrokes => added.isEmpty && addedObjects.isEmpty,
    InkEditKind.addShape => addedObjects.isEmpty,
    InkEditKind.eraseStrokes ||
    InkEditKind.deleteStrokes ||
    InkEditKind.splitStrokes => removedIds.isEmpty,
    InkEditKind.transformStrokes => targetIds.isEmpty || transform == null,
    InkEditKind.recolorStrokes => targetIds.isEmpty || colorArgb == null,
  };

  /// Table 4.6 / contract 7.2.9 v2.1. StateError when [isEmpty]; ArgumentError when
  /// [removedObjectIds] is not a subset of [removedIds]. Commands use the v2.1 shape
  /// (named arguments; id lists are Lists). When 'the empty side is left out' leaves one
  /// command, that command is returned without a CompositeCommand around it.
  core.EditCommand toCommand() {
    if (isEmpty) {
      throw StateError('InkEdit(${kind.name}) is empty; no command to make');
    }
    if (!removedIds.containsAll(removedObjectIds)) {
      throw ArgumentError.value(
        removedObjectIds,
        'removedObjectIds',
        'must be a subset of removedIds',
      );
    }
    return switch (kind) {
      InkEditKind.addStroke => core.AddStrokes(
        pageId: pageId,
        strokes: List.unmodifiable(added),
      ),
      InkEditKind.addShape => core.AddObjects(
        pageId: pageId,
        objects: List.unmodifiable(addedObjects),
      ),
      InkEditKind.duplicateStrokes => _oneOrComposite([
        if (added.isNotEmpty)
          core.AddStrokes(pageId: pageId, strokes: List.unmodifiable(added)),
        if (addedObjects.isNotEmpty)
          core.AddObjects(
            pageId: pageId,
            objects: List.unmodifiable(addedObjects),
          ),
      ]),
      InkEditKind.eraseStrokes || InkEditKind.deleteStrokes =>
        removedObjectIds.isEmpty
            ? core.RemoveStrokes(
                pageId: pageId,
                strokeIds: removedIds.toList(growable: false),
              )
            : core.RemoveElements(
                pageId: pageId,
                elementIds: removedIds.toList(growable: false),
              ),
      InkEditKind.splitStrokes => _split(),
      InkEditKind.transformStrokes => core.TransformElements(
        pageId: pageId,
        elementIds: targetIds.toList(growable: false),
        transform: transform!,
        scaleStrokeWidth: true,
      ),
      InkEditKind.recolorStrokes => _recolor(),
    };
  }

  /// v1.4 (SplitStrokes, or RemoveStrokes without pieces) when no object was removed;
  /// otherwise (CP-INK-2) Composite[SplitStrokes | RemoveStrokes, RemoveElements(objects)]
  /// with the empty side left out.
  core.EditCommand _split() {
    final strokeIds = removedObjectIds.isEmpty
        ? removedIds.toList(growable: false)
        : [
            for (final id in removedIds)
              if (!removedObjectIds.contains(id)) id,
          ];
    final strokesCommand = strokeIds.isEmpty
        ? null
        : added.isEmpty
        ? core.RemoveStrokes(pageId: pageId, strokeIds: strokeIds)
        : core.SplitStrokes(
            pageId: pageId,
            removedIds: strokeIds,
            added: List.unmodifiable(added),
          );
    return _oneOrComposite([
      ?strokesCommand,
      if (removedObjectIds.isNotEmpty)
        core.RemoveElements(
          pageId: pageId,
          elementIds: removedObjectIds.toList(growable: false),
        ),
    ]);
  }

  /// Composite[RestyleStrokes(targetIds − updatedObjects ids), UpdateObjects(updatedObjects)]
  /// with the empty side left out.
  core.EditCommand _recolor() {
    final objectIds = {for (final o in updatedObjects) o.id};
    final strokeIds = [
      for (final id in targetIds)
        if (!objectIds.contains(id)) id,
    ];
    return _oneOrComposite([
      if (strokeIds.isNotEmpty)
        core.RestyleStrokes(
          pageId: pageId,
          strokeIds: strokeIds,
          patch: core.StrokeStylePatch(colorArgb: colorArgb),
        ),
      if (updatedObjects.isNotEmpty)
        core.UpdateObjects(
          pageId: pageId,
          objects: List.unmodifiable(updatedObjects),
        ),
    ]);
  }

  static core.EditCommand _oneOrComposite(List<core.EditCommand> commands) =>
      commands.length == 1
      ? commands.single
      : core.CompositeCommand(List.unmodifiable(commands));

  @override
  bool operator ==(Object other) =>
      other is InkEdit &&
      other.pageId == pageId &&
      other.kind == kind &&
      other.transform == transform &&
      other.colorArgb == colorArgb &&
      _listEquals(other.added, added) &&
      _setEquals(other.removedIds, removedIds) &&
      _setEquals(other.targetIds, targetIds) &&
      _listEquals(other.addedObjects, addedObjects) &&
      _listEquals(other.updatedObjects, updatedObjects) &&
      _setEquals(other.removedObjectIds, removedObjectIds);

  @override
  int get hashCode => Object.hash(
    pageId,
    kind,
    transform,
    colorArgb,
    Object.hashAll(added.map(identityHashCode)),
    Object.hashAllUnordered(removedIds),
    Object.hashAllUnordered(targetIds),
    Object.hashAll(addedObjects.map(identityHashCode)),
    Object.hashAll(updatedObjects.map(identityHashCode)),
    Object.hashAllUnordered(removedObjectIds),
  );

  @override
  String toString() =>
      'InkEdit(${kind.name}, $pageId, +${added.length + addedObjects.length} '
      '-${removedIds.length} ~${targetIds.length})';

  /// Element identity (strokes and objects are compared as instances, K-4).
  static bool _listEquals(List<Object> a, List<Object> b) {
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
