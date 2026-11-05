// lib/src/dnd/drop_decision.dart — 05-library 6.10.2: drop targets and the
// pure decision every DragTarget uses (onMove for the highlight, onAccept for
// the action).
import 'package:flutter/foundation.dart' show immutable;
import 'package:material_ui/material_ui.dart' show Axis, Offset, Size;
import 'package:note_core/note_core.dart' show FolderId, FolderTree;

import '../model/item_key.dart';
import 'drag_payload.dart';

sealed class LibraryDropTarget {
  const LibraryDropTarget();
}

/// Sidebar folder row, sidebar '홈' row, breadcrumb crumb / overflow item,
/// folder picker is not a drop target.
@immutable
final class FolderDropTarget extends LibraryDropTarget {
  const FolderDropTarget(this.folderId);

  /// null = 홈.
  final FolderId? folderId;

  @override
  bool operator ==(Object other) =>
      other is FolderDropTarget && other.folderId == folderId;

  @override
  int get hashCode => Object.hash(FolderDropTarget, folderId);

  @override
  String toString() => 'FolderDropTarget(${folderId ?? 'home'})';
}

@immutable
final class TrashDropTarget extends LibraryDropTarget {
  const TrashDropTarget();

  @override
  bool operator ==(Object other) => other is TrashDropTarget;

  @override
  int get hashCode => (TrashDropTarget).hashCode;

  @override
  String toString() => 'TrashDropTarget()';
}

/// A tile/row in the content pane.
@immutable
final class TileDropTarget extends LibraryDropTarget {
  const TileDropTarget({required this.key, required this.axis});

  final LibraryItemKey key;

  /// grid: horizontal, list: vertical.
  final Axis axis;

  @override
  bool operator ==(Object other) =>
      other is TileDropTarget && other.key == key && other.axis == axis;

  @override
  int get hashCode => Object.hash(key, axis);

  @override
  String toString() => 'TileDropTarget($key, ${axis.name})';
}

sealed class DropDecision {
  const DropDecision();
}

@immutable
final class DropInto extends DropDecision {
  const DropInto(this.folderId);

  /// null = 홈.
  final FolderId? folderId;

  @override
  bool operator ==(Object other) =>
      other is DropInto && other.folderId == folderId;

  @override
  int get hashCode => Object.hash(DropInto, folderId);

  @override
  String toString() => 'DropInto(${folderId ?? 'home'})';
}

@immutable
final class DropReorder extends DropDecision {
  const DropReorder({required this.anchor, required this.after});

  final LibraryItemKey anchor;
  final bool after;

  @override
  bool operator ==(Object other) =>
      other is DropReorder && other.anchor == anchor && other.after == after;

  @override
  int get hashCode => Object.hash(anchor, after);

  @override
  String toString() => 'DropReorder(${after ? 'after' : 'before'} $anchor)';
}

@immutable
final class DropTrash extends DropDecision {
  const DropTrash();

  @override
  bool operator ==(Object other) => other is DropTrash;

  @override
  int get hashCode => (DropTrash).hashCode;

  @override
  String toString() => 'DropTrash()';
}

/// Into-zone of a folder tile: reorder only in the outer quarters.
const double _reorderEdge = 0.25;

/// false if any dragged folder F satisfies target != null &&
/// tree.isSelfOrDescendant(target, of: F), or if every item's parent == target.
bool canMoveInto(
  LibraryDragPayload payload,
  FolderId? target,
  FolderTree tree,
) {
  if (target != null) {
    for (final f in payload.folderIds) {
      if (tree.isSelfOrDescendant(target, of: f)) return false;
    }
  }
  return !payload.items.every((k) => payload.parents[k] == target);
}

/// Pure decision used by every DragTarget's onMove / onAccept.
/// [localPosition] and [targetSize] are required for TileDropTarget (without
/// them, or with an empty size, the decision is null).
DropDecision? decideDrop({
  required LibraryDragPayload payload,
  required LibraryDropTarget target,
  required FolderTree tree,
  required bool customSort, // content is FolderSection with sort == custom
  Offset? localPosition,
  Size? targetSize,
}) {
  switch (target) {
    case FolderDropTarget(:final folderId):
      return canMoveInto(payload, folderId, tree) ? DropInto(folderId) : null;
    case TrashDropTarget():
      return const DropTrash();
    case TileDropTarget(:final key, :final axis):
      if (payload.items.contains(key)) return null;
      if (localPosition == null || targetSize == null) return null;
      final extent = axis == Axis.horizontal
          ? targetSize.width
          : targetSize.height;
      if (extent <= 0) return null;
      final along = axis == Axis.horizontal
          ? localPosition.dx
          : localPosition.dy;
      final t = (along / extent).clamp(0.0, 1.0);
      final reorderable =
          customSort &&
          payload.source == LibraryDragSource.content &&
          payload.isSingleKind &&
          payload.items.first.kind == key.kind;
      if (key.isFolder) {
        if (reorderable && (t < _reorderEdge || t > 1 - _reorderEdge)) {
          return DropReorder(anchor: key, after: t > 1 - _reorderEdge);
        }
        return canMoveInto(payload, key.id, tree) ? DropInto(key.id) : null;
      }
      return reorderable ? DropReorder(anchor: key, after: t >= 0.5) : null;
  }
}
