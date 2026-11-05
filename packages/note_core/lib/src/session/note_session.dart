// lib/src/session/note_session.dart — contract 00-overview 7.2.8 / CORE 4.4.
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../edit/applied_edit.dart';
import '../edit/commands.dart';
import '../model/note.dart';
import '../model/page.dart';
import 'page_content.dart';

@immutable
final class NoteSessionOptions {
  const NoteSessionOptions({
    this.maxCachedPages = 8,
    this.history = HistoryLimits.platformDefault,
  });

  final int maxCachedPages; // unpinned pages kept in memory (LRU)
  final HistoryLimits history;

  @override
  bool operator ==(Object other) =>
      other is NoteSessionOptions &&
      other.maxCachedPages == maxCachedPages &&
      other.history == history;

  @override
  int get hashCode => Object.hash(maxCachedPages, history);
}

/// Guarantees of contract 7.2.8 v1.1 (tests: test/shared/note_session_contract.dart, run
/// against createFakeNoteStore() — N-1..N-6 — AND openTestNoteStore() — N-1..N-7):
/// N-1 execute(command) changes the in-memory state SYNCHRONOUSLY and, inside that call,
///     delivers the pageChanges / pagesStream / historyStream / noteStream events through
///     SYNCHRONOUS broadcast controllers, then returns. On return pageIfLoaded, pages and
///     history are the new state. Persistence is asynchronous (receipt.persisted).
///     (v1.1) pagesStream emits whenever the active page list OR a Page value in it changes
///     (local contentRevision included); layout-only consumers filter by id / size / background.
/// N-2 Commands apply in call order (single isolate, no queueing). (v1.1) No re-entrancy:
///     execute() from inside a listener of these streams throws StateError (a synchronous
///     broadcast cannot fire while it is delivering) — defer with scheduleMicrotask.
///     executeAsync / undo / redo apply after their first await. (7.2.8 N-2)
/// N-3 A stroke command whose page is not loaded throws PageNotOpenException. Page commands
///     that need page content (DuplicatePages) go through executeAsync, which opens it first.
/// N-4 isReadOnly (trashed note, note from a newer schema) → execute, executeAsync, undo and
///     redo throw ReadOnlyNoteException and nothing is written (v1.1: undo / redo added).
///     EDITOR shows a read-only notice and disables tools. (7.2.8 N-4)
/// N-5 One session per note, reference-counted: NoteStore.openSession twice = the same
///     instance, close() once = one reference released. EDITOR uses noteSessionProvider,
///     PDF uses openSession / close.
/// N-6 openSession calls markOpened(noteId) — CORE is the only writer of 'recent'. A missing
///     or purged note throws EntityNotFoundException.
/// N-7 Remote changes reach loaded pages of an open session as PageContentChange(origin: remote).
abstract interface class NoteSession {
  NoteId get noteId;
  Note get note;
  Stream<Note>
  get noteStream; // sync broadcast, changes only (providers seed current)

  /// True if note.requiresNewerApp or the note is trashed (N-4).
  bool get isReadOnly;

  /// Active pages, ordered by (sortKey, id). Always fully loaded (metadata only).
  List<Page> get pages;

  /// Sync broadcast, changes only: emits whenever the active page list OR a Page value in it
  /// (local contentRevision included, e.g. after AddStrokes) changes (7.2.8 N-1 v1.1).
  Stream<List<Page>> get pagesStream;

  /// Loads strokes of one page and pins it (ref-counted). Pinned pages are never evicted.
  Future<PageContent> openPage(PageId pageId);

  /// Unpins. The page stays cached until LRU eviction (maxCachedPages).
  void closePage(PageId pageId);
  PageContent? pageIfLoaded(PageId pageId);

  /// Sync broadcast. Emits a `load` change first if loaded (or when it gets loaded), then
  /// every change of that page.
  Stream<PageContentChange> pageChanges(PageId pageId);

  /// N-1..N-4. Also throws LastPageDeletionException, ArgumentError for invalid input,
  /// SessionClosedException after close(), StateError when re-entered from a listener (N-2).
  CommandReceipt execute(EditCommand command);

  /// Loads the pages the command needs (N-3), then execute() — after the first await (N-2).
  Future<CommandReceipt> executeAsync(EditCommand command);

  HistoryState get history;
  Stream<HistoryState> get historyStream; // sync broadcast, changes only

  /// Both apply after their first await (N-2); ReadOnlyNoteException when isReadOnly (N-4).
  Future<UndoRedoResult> undo();
  Future<UndoRedoResult> redo();
  void clearHistory();

  /// All writes of this session committed; pending (no error) while a commit is retried
  /// (4.5 head, 7.2.9 v1.2).
  Future<void> flush();
  Future<void>
  close(); // releases one reference (N-5); last one flushes and frees memory
  bool get isClosed;
}
