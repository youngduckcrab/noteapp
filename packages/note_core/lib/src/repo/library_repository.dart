// lib/src/repo/library_repository.dart — contract 00-overview 7.2.9 / CORE 4.5.
import '../common/ids.dart';
import '../edit/page_draft.dart';
import '../model/folder.dart';
import '../model/note.dart';
import 'folder_tree.dart';
import 'library_types.dart';

/// Behaviour contract C-1..C-10 (05-library 5.1.1, approved in 7.2.9):
/// C-1 every watch* stream emits the current value on listen and again after every commit
///     (local or remote) that affects the result.
/// C-2 watchListing: folders first, then notes, ordered exactly as the LibraryQuery says;
///     an unknown folderId yields an empty listing, not an error.
/// C-3 getFolder / getNote also return trashed items (deletedAt != null); null = purged/unknown.
/// C-4 moveItems ignores items already in the target folder; a cycle throws
///     FolderCycleException and changes nothing (atomic).
/// C-5 copyItems: when name + nameSuffix is longer than 200, the ORIGINAL name is cut
///     (never splitting a surrogate pair).
/// C-6 names / titles: trimmed, String.length 1..200, else ArgumentError.
/// C-7 watchRecentNotes / watchFavoriteNotes / searchLibrary exclude trashed items;
///     an empty query returns an empty result.
/// C-8 after restore, getNote / getFolder return the new location (6.8).
/// C-9 Note.firstPageId = first active page; a content change of that page bumps its
///     contentRevision and the note's updatedAt. (v1.1) This is the LOCAL edit rule: a remote
///     apply sets Note.updatedAt = max(current, applied updatedAt) (7.2.10), so it may stay
///     unchanged after remote stroke changes — watch NoteStore.changes for
///     ChangeBatch(origin: remote) and EntityChange.noteId instead.
/// C-10 mutations may be separate transactions; consecutive reorderItem calls apply in
///     call order.
/// Mutation Futures complete after the DB commit (not while the write is being retried, 6.9);
/// ArgumentError completes them before enqueue; FolderCycleException / EntityNotFoundException
/// inside the transaction (after earlier queued writes) — never retried, nothing changed
/// (4.5 head, 7.2.9 v1.2).
abstract interface class LibraryRepository {
  // Queries
  Stream<FolderTree> watchFolderTree();
  Stream<LibraryListing> watchListing(LibraryQuery query);
  Stream<Note?> watchNote(NoteId id);
  Future<Note?> getNote(NoteId id);
  Future<Folder?> getFolder(FolderId id);
  Stream<List<Note>> watchRecentNotes({int limit = 20});
  Stream<List<Note>> watchFavoriteNotes();
  Future<LibrarySearchResult> searchLibrary(String query, {int limit = 50});

  // Folders
  Future<Folder> createFolder({
    FolderId? parentId,
    required String name,
    int? colorArgb,
    String? icon,
  });
  Future<void> renameFolder(FolderId id, String name);
  Future<void> setFolderAppearance(
    FolderId id, {
    int? colorArgb,
    String? icon,
    bool clearColor = false,
    bool clearIcon = false,
  });

  // Notes
  /// [pages]: 1..2000 drafts written in ONE transaction (PDF C-3), else ArgumentError.
  Future<Note> createNote({
    FolderId? folderId,
    required String title,
    List<PageDraft> pages = const [PageDraft.blankA4],
    NoteCover cover = const FirstPageCover(),
  });
  Future<void> renameNote(NoteId id, String title);
  Future<void> setFavorite(List<NoteId> ids, bool favorite);
  Future<void> setCover(NoteId id, NoteCover cover);
  Future<void> setTags(NoteId id, List<String> tags);

  /// Called by NoteStore.openSession only (7.2.8 N-6). LIBRARY and EDITOR do not call it.
  Future<void> markOpened(NoteId id);

  // Mixed (multi-select)
  /// Throws FolderCycleException when a folder would move into itself/descendant (C-4).
  Future<void> moveItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
  });

  /// Custom order within the same parent and the same kind (folders vs notes).
  Future<void> reorderItem(
    LibraryItemRef item, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  });

  /// Custom order for several items of the same parent and kind, ONE commit, keeps their
  /// relative order. Throws ArgumentError for mixed parents/kinds.
  Future<void> reorderItems(
    List<LibraryItemRef> items, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  });

  /// Deep copy (folders recursively, notes with pages and strokes). Assets are shared.
  Future<List<LibraryItemRef>> copyItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
    String nameSuffix = '',
  });
  Future<void> trashItems(List<LibraryItemRef> items);
}
