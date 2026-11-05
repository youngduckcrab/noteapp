// lib/src/state/library_actions.dart — 05-library 6.11. The one place where
// the screen changes CORE data (6.3.1): every call goes to LibraryRepository
// / TrashRepository and comes back as an ActionOutcome. Results reach the
// screen through the CORE streams (no optimistic update).
import 'package:collection/collection.dart' show MapEquality;
import 'package:flutter/foundation.dart' show immutable;
import 'package:note_core/note_core.dart'
    show
        EntityNotFoundException,
        Folder,
        FolderCycleException,
        FolderId,
        FolderTree,
        LibraryItemRef,
        LibraryQuery,
        LibraryRepository,
        LibrarySortField,
        Note,
        NoteCover,
        NoteId,
        TrashRepository;

import '../l10n/library_strings.dart';
import '../model/folder_appearance_value.dart';
import '../model/item_key.dart';
import '../model/names.dart';
import '../model/new_note_spec.dart';

@immutable
sealed class ActionOutcome<T> {
  const ActionOutcome();
}

final class ActionSuccess<T> extends ActionOutcome<T> {
  const ActionSuccess(this.value);
  final T value;

  @override
  String toString() => 'ActionSuccess($value)';
}

final class ActionFailure<T> extends ActionOutcome<T> {
  const ActionFailure(this.kind, this.error);
  final LibraryFailureKind kind;
  final Object error;

  @override
  String toString() => 'ActionFailure(${kind.name}, $error)';
}

enum LibraryFailureKind { folderCycle, notFound, invalidName, unknown }

/// FolderCycleException → folderCycle, EntityNotFoundException → notFound,
/// ArgumentError (name rule C-6) → invalidName, anything else → unknown.
/// Storage failures are not per-action errors: CORE retries writes and
/// reports them through PersistenceStatus → StorageWarningBanner (6.16,
/// storageWarningOf).
LibraryFailureKind classifyLibraryError(Object error) => switch (error) {
  FolderCycleException() => LibraryFailureKind.folderCycle,
  EntityNotFoundException() => LibraryFailureKind.notFound,
  ArgumentError() => LibraryFailureKind.invalidName,
  _ => LibraryFailureKind.unknown,
};

/// What a move needs to be undone: the parent of every item that really
/// moved (items already in the target are left out — CORE ignores them, C-4).
@immutable
final class MoveReceipt {
  const MoveReceipt(this.originalParents);
  final Map<LibraryItemKey, FolderId?> originalParents;

  bool get isEmpty => originalParents.isEmpty;

  static const MapEquality<LibraryItemKey, FolderId?> _eq =
      MapEquality<LibraryItemKey, FolderId?>();

  @override
  bool operator ==(Object other) =>
      other is MoveReceipt &&
      _eq.equals(other.originalParents, originalParents);

  @override
  int get hashCode => _eq.hash(originalParents);

  @override
  String toString() => 'MoveReceipt($originalParents)';
}

final class LibraryActions {
  LibraryActions({
    required this._library,
    required this._trash,
    required this._report,
  });

  final LibraryRepository _library;
  final TrashRepository _trash;
  final void Function(Object error, StackTrace stack, String context) _report;

  Future<ActionOutcome<Note>> createNote(
    NewNoteSpec spec, {
    required FolderId? folderId,
  }) => _run(
    'createNote',
    () => _library.createNote(
      folderId: folderId,
      title: spec.title,
      pages: [spec.toPageDraft()],
      cover: spec.cover,
    ),
  );

  Future<ActionOutcome<Folder>> createFolder(
    NewFolderSpec spec, {
    required FolderId? parentId,
  }) => _run(
    'createFolder',
    () => _library.createFolder(
      parentId: parentId,
      name: spec.name,
      colorArgb: spec.appearance.colorArgb,
      icon: spec.appearance.icon,
    ),
  );

  Future<ActionOutcome<void>> rename(LibraryItemKey item, String newName) =>
      _run(
        'rename',
        () => item.isFolder
            ? _library.renameFolder(item.id, newName)
            : _library.renameNote(item.id, newName),
      );

  /// No color → clearColor, default icon → clearIcon.
  Future<ActionOutcome<void>> setFolderAppearance(
    FolderId id,
    FolderAppearance appearance,
  ) => _run(
    'setFolderAppearance',
    () => _library.setFolderAppearance(
      id,
      colorArgb: appearance.colorArgb,
      icon: appearance.icon,
      clearColor: appearance.colorArgb == null,
      clearIcon: appearance.icon == null,
    ),
  );

  Future<ActionOutcome<void>> setCover(NoteId id, NoteCover cover) =>
      _run('setCover', () => _library.setCover(id, cover));

  Future<ActionOutcome<void>> setFavorite(List<NoteId> ids, bool favorite) =>
      _run('setFavorite', () => _library.setFavorite(ids, favorite));

  /// One moveItems call. The receipt keeps the original parent of every item
  /// of [originalParents] that is not already in [target].
  Future<ActionOutcome<MoveReceipt>> move(
    List<LibraryItemKey> items, {
    required FolderId? target,
    required Map<LibraryItemKey, FolderId?> originalParents,
  }) => _run('move', () async {
    await _library.moveItems(_refs(items), targetFolderId: target);
    return MoveReceipt(
      Map.unmodifiable({
        for (final k in items)
          if (originalParents.containsKey(k) && originalParents[k] != target)
            k: originalParents[k],
      }),
    );
  });

  /// Moves every item back to its original parent (grouped by parent: one
  /// moveItems per parent, in the receipt's order). Stops at the first
  /// failure.
  Future<ActionOutcome<void>> undoMove(MoveReceipt receipt) =>
      _run('undoMove', () async {
        final groups = <FolderId?, List<LibraryItemKey>>{};
        receipt.originalParents.forEach((key, parent) {
          (groups[parent] ??= []).add(key);
        });
        for (final MapEntry(key: parent, value: keys) in groups.entries) {
          await _library.moveItems(_refs(keys), targetFolderId: parent);
        }
      });

  Future<ActionOutcome<List<LibraryItemRef>>> copy(
    List<LibraryItemKey> items, {
    required FolderId? target,
    required String nameSuffix,
  }) => _run(
    'copy',
    () => _library.copyItems(
      _refs(items),
      targetFolderId: target,
      nameSuffix: nameSuffix,
    ),
  );

  /// Custom order: one item → reorderItem, several → ONE reorderItems call
  /// (6.10.3). [after] = place them right after [anchor], else right before.
  Future<ActionOutcome<void>> reorder(
    List<LibraryItemKey> items, {
    required LibraryItemKey anchor,
    required bool after,
  }) => _run('reorder', () async {
    if (items.isEmpty) return;
    final anchorRef = anchor.toRef();
    if (items.length == 1) {
      await _library.reorderItem(
        items.single.toRef(),
        after: after ? anchorRef : null,
        before: after ? null : anchorRef,
      );
    } else {
      await _library.reorderItems(
        _refs(items),
        after: after ? anchorRef : null,
        before: after ? null : anchorRef,
      );
    }
  });

  Future<ActionOutcome<void>> trash(List<LibraryItemKey> items) =>
      _run('trash', () => _library.trashItems(_refs(items)));

  /// Also the undo of [trash].
  Future<ActionOutcome<void>> restore(List<LibraryItemKey> items) =>
      _run('restore', () => _trash.restore(_refs(items)));

  Future<ActionOutcome<void>> purge(List<LibraryItemKey> items) =>
      _run('purge', () => _trash.purge(_refs(items)));

  Future<ActionOutcome<void>> emptyTrash() =>
      _run('emptyTrash', _trash.emptyTrash);

  // No markOpened: CORE openSession records '최근' (contract 7.2.8 N-6,
  // LIBRARY-S1).

  /// Parent of an item after restore (null = 홈); null result = item gone
  /// (purged / unknown, C-3). A failed read is reported and gives null.
  Future<({FolderId? parentId})?> locate(LibraryItemKey item) async {
    try {
      if (item.isFolder) {
        final folder = await _library.getFolder(item.id);
        return folder == null ? null : (parentId: folder.parentId);
      }
      final note = await _library.getNote(item.id);
      return note == null ? null : (parentId: note.folderId);
    } on Object catch (error, stack) {
      _report(error, stack, 'library action: locate');
      return null;
    }
  }

  /// Unique default note title for the target folder (6.12):
  /// uniqueName('제목 없는 노트', titles of the notes in [folderId]). A failed
  /// read is reported and gives the base name.
  Future<String> uniqueNoteTitle(FolderId? folderId) async {
    try {
      final listing = await _library
          .watchListing(
            LibraryQuery(
              folderId: folderId,
              sort: LibrarySortField.name,
              descending: false,
            ),
          )
          .first;
      return uniqueName(
        LibraryStrings.defaultNoteTitle,
        listing.notes.map((n) => n.title),
      );
    } on Object catch (error, stack) {
      _report(error, stack, 'library action: uniqueNoteTitle');
      return LibraryStrings.defaultNoteTitle;
    }
  }

  /// uniqueName('새 폴더', names of the sub-folders of [parentId] in [tree]).
  String uniqueFolderName(FolderId? parentId, FolderTree tree) => uniqueName(
    LibraryStrings.defaultFolderName,
    tree.childrenOf(parentId).map((f) => f.name),
  );

  /// Classifies a failure; reports everything except folderCycle and
  /// invalidName (errors the user can fix, 6.11 / 6.19).
  Future<ActionOutcome<T>> _run<T>(
    String action,
    Future<T> Function() body,
  ) async {
    try {
      return ActionSuccess<T>(await body());
    } on Object catch (error, stack) {
      final kind = classifyLibraryError(error);
      if (kind == LibraryFailureKind.notFound ||
          kind == LibraryFailureKind.unknown) {
        _report(error, stack, 'library action: $action');
      }
      return ActionFailure<T>(kind, error);
    }
  }
}

List<LibraryItemRef> _refs(List<LibraryItemKey> keys) => [
  for (final k in keys) k.toRef(),
];
