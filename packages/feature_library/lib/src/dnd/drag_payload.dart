// lib/src/dnd/drag_payload.dart — 05-library 6.10.1: what a drag carries.
import 'package:collection/collection.dart' show ListEquality, MapEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart' show FolderId;

import '../model/content.dart';
import '../model/item_key.dart';
import '../model/selection.dart';

const ListEquality<LibraryItemKey> _keysEq = ListEquality<LibraryItemKey>();
const MapEquality<LibraryItemKey, FolderId?> _parentsEq =
    MapEquality<LibraryItemKey, FolderId?>();

enum LibraryDragSource { content, sidebar }

@immutable
final class LibraryDragPayload {
  const LibraryDragPayload({
    required this.items,
    required this.parents,
    required this.source,
  });

  /// Non-empty, display order.
  final List<LibraryItemKey> items;

  /// Current parent of every item (null = 홈).
  final Map<LibraryItemKey, FolderId?> parents;
  final LibraryDragSource source;

  bool get hasFolders => items.any((k) => k.isFolder);
  bool get hasNotes => items.any((k) => !k.isFolder);

  /// Only folders or only notes.
  bool get isSingleKind => !(hasFolders && hasNotes);

  List<FolderId> get folderIds => [
    for (final k in items)
      if (k.isFolder) k.id,
  ];

  @override
  bool operator ==(Object other) =>
      other is LibraryDragPayload &&
      other.source == source &&
      _keysEq.equals(other.items, items) &&
      _parentsEq.equals(other.parents, parents);

  @override
  int get hashCode =>
      Object.hash(source, _keysEq.hash(items), _parentsEq.hash(parents));

  @override
  String toString() => 'LibraryDragPayload(${source.name}, $items, $parents)';
}

/// Draggable.data is fixed when the widget is built; building a full payload
/// for every visible tile on every selection change is wasteful. So the
/// Draggable carries this handle and the payload is built lazily, once, on
/// first access.
///
/// Ordering (verified in Flutter 3.47.9 drag_target.dart): the _DragAvatar
/// constructor runs updateDrag() — which can call didEnter/didMove on targets
/// under the start point, e.g. the pressed folder tile itself — BEFORE
/// Draggable.onDragStarted. Therefore the builder must not depend on
/// onDragStarted having run: it always returns
/// inDisplayOrder((selection.active ? selection.keys : []) ∪ {pressedKey}).
/// onDragStarted only updates the UI selection (selection.add(pressedKey)).
final class LibraryDragHandle {
  LibraryDragHandle(this._build);

  final LibraryDragPayload Function() _build;
  LibraryDragPayload? _payload;
  bool _dropped = false;

  /// Built on first access, then cached for the rest of the drag.
  LibraryDragPayload get payload => _payload ??= _build();

  /// A drop target ran a decision with this drag (LibraryDraggable then does
  /// not treat the release as a long press released in place).
  bool get dropped => _dropped;

  void markDropped() => _dropped = true;
}

/// 6.10.1 content tiles: the selected items (in selection mode) plus the
/// pressed one, in the display order of [content] (folders, then notes) —
/// the same result whether or not onDragStarted has run. Selected keys that
/// the content no longer shows are left out; the pressed item is always in
/// (at the end if the content does not show it either). [parents] come from
/// the content's items (folder.parentId / note.folderId), the pressed item's
/// from [pressedParent].
LibraryDragPayload contentDragPayload({
  required LibraryItemKey pressed,
  required FolderId? pressedParent,
  required LibrarySelection selection,
  required LibraryContent? content,
}) {
  final wanted = <LibraryItemKey>{if (selection.active) ...selection.keys};
  wanted.add(pressed);
  final parents = <LibraryItemKey, FolderId?>{};
  final items = <LibraryItemKey>[];
  if (content != null) {
    for (final f in content.folders) {
      final k = folderKey(f.id);
      if (!wanted.contains(k)) continue;
      items.add(k);
      parents[k] = f.parentId;
    }
    for (final n in content.notes) {
      final k = noteKey(n.id);
      if (!wanted.contains(k)) continue;
      items.add(k);
      parents[k] = n.folderId;
    }
  }
  if (!parents.containsKey(pressed)) items.add(pressed);
  parents[pressed] = pressedParent;
  return LibraryDragPayload(
    items: List.unmodifiable(items),
    parents: Map.unmodifiable(parents),
    source: LibraryDragSource.content,
  );
}
