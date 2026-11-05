// lib/src/model/item_key.dart — 05-library 6.3.3.
import 'package:note_core/note_core.dart'
    show FolderId, FolderRef, LibraryItemRef, NoteId, NoteRef;

enum LibraryItemKind { folder, note }

/// Value-equal key (Dart record) used for selection, drag payloads and
/// receipts.
typedef LibraryItemKey = ({LibraryItemKind kind, String id});

LibraryItemKey folderKey(FolderId id) => (kind: LibraryItemKind.folder, id: id);

LibraryItemKey noteKey(NoteId id) => (kind: LibraryItemKind.note, id: id);

/// The key of a CORE item reference.
LibraryItemKey keyOfRef(LibraryItemRef ref) => switch (ref) {
  FolderRef(:final id) => folderKey(id),
  NoteRef(:final id) => noteKey(id),
};

extension LibraryItemKeyX on LibraryItemKey {
  /// FolderRef / NoteRef.
  LibraryItemRef toRef() => isFolder ? FolderRef(id) : NoteRef(id);

  bool get isFolder => kind == LibraryItemKind.folder;
}
