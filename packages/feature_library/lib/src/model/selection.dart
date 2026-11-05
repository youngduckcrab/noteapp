// lib/src/model/selection.dart — 05-library 6.3.3 / 6.9.
import 'package:collection/collection.dart' show ListEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart' show FolderId, NoteId;

import 'item_key.dart';

const ListEquality<LibraryItemKey> _keysEq = ListEquality<LibraryItemKey>();

@immutable
final class LibrarySelection {
  const LibrarySelection._(this.active, this._keys, this._set);

  /// Selection mode on with [keys] (duplicates dropped, first one kept).
  factory LibrarySelection.activeWith(Iterable<LibraryItemKey> keys) {
    final set = <LibraryItemKey>{};
    final list = [
      for (final k in keys)
        if (set.add(k)) k,
    ];
    return LibrarySelection._(
      true,
      List.unmodifiable(list),
      Set.unmodifiable(set),
    );
  }

  static const LibrarySelection none = LibrarySelection._(
    false,
    <LibraryItemKey>[],
    <LibraryItemKey>{},
  );

  /// Selection mode on (even with 0 items).
  final bool active;
  final List<LibraryItemKey> _keys;
  final Set<LibraryItemKey> _set;

  /// Insertion order.
  List<LibraryItemKey> get keys => _keys;
  int get count => _keys.length;
  bool get isEmpty => _keys.isEmpty;
  bool contains(LibraryItemKey key) => _set.contains(key);
  bool get hasFolders => _keys.any((k) => k.isFolder);
  bool get hasNotes => _keys.any((k) => !k.isFolder);
  List<FolderId> get folderIds => [
    for (final k in _keys)
      if (k.isFolder) k.id,
  ];
  List<NoteId> get noteIds => [
    for (final k in _keys)
      if (!k.isFolder) k.id,
  ];

  /// [displayOrder] filtered to selected keys (batch actions use display
  /// order).
  List<LibraryItemKey> inDisplayOrder(List<LibraryItemKey> displayOrder) => [
    for (final k in displayOrder)
      if (_set.contains(k)) k,
  ];

  @override
  bool operator ==(Object other) =>
      other is LibrarySelection &&
      other.active == active &&
      _keysEq.equals(other._keys, _keys);

  @override
  int get hashCode => Object.hash(active, _keysEq.hash(_keys));

  @override
  String toString() => active
      ? 'LibrarySelection(${_keys.length}: $_keys)'
      : 'LibrarySelection.none';
}
