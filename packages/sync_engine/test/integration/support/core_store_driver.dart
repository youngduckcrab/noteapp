// Real CORE for the T16 integration tests (integration stage): openTestNoteStore on a
// temporary SQLite file (so it can be reopened), wrapped by CoreSyncLocalStore, and the
// SyncStore contract driver doing local edits the way the app does them (5.1.4): library
// and trash repositories, a session's AddStrokes, assets.put, markOpened through
// openSession (N-6) and reopening the same file. Commit failures for S-20 (5.1.2) come from
// moving the database file away (CoreTestStore.failCommits): openTestNoteStore takes no
// fault hook, and the write queue's own hook (WriteQueue.failNextCommits) is CORE src/.
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../contract/sync_store_contract.dart';

/// A real CORE store on a temporary file of its own.
final class CoreTestStore {
  CoreTestStore._(this.store, this.directory, this._reopen);

  static const String _fileName = 'core.sqlite';

  static Future<CoreTestStore> open({
    required String deviceNodeId,
    Clock? clock,
    bool seedDefaultPenPresets = true,
  }) async {
    final directory = Directory.systemTemp.createTempSync('sync_core_');
    Future<NoteStore> openStore() => openTestNoteStore(
      clock: clock,
      deviceNodeId: deviceNodeId,
      filePath: '${directory.path}/$_fileName',
      seedDefaultPenPresets: seedDefaultPenPresets,
    );
    return CoreTestStore._(await openStore(), directory, openStore);
  }

  final NoteStore store;
  final Directory directory;
  final Future<NoteStore> Function() _reopen;
  late final CoreSyncLocalStore local = CoreSyncLocalStore(store);

  String get _file => '${directory.path}/$_fileName';
  String get _movedFile => '$_file.moved';

  /// Whether [failCommits] is in effect.
  bool get commitsFailing => File(_movedFile).existsSync();

  /// S-20 with real CORE: moves the open database file away, so SQLite refuses every write
  /// transaction (SQLITE_READONLY_DBMOVED — its rollback journal would have no database
  /// name to belong to) while reads go on. CORE's write queue treats that as a storage
  /// failure (6.9): the transaction rolls back and is retried after 100 ms, 400 ms, 1.6 s,
  /// then every 5 s, its write Futures stay pending (no value, no error) and
  /// PersistenceStatus.consecutiveFailures counts up (writeFailing from 3). [healCommits]
  /// moves the file back and the next retry commits. Relies on the rollback journal of
  /// openTestNoteStore's file database (no WAL): a test using it waits for writeFailing OR
  /// its write completing, then expects the write still pending, so a store that keeps
  /// committing fails at once with that reason.
  void failCommits() {
    if (!commitsFailing) File(_file).renameSync(_movedFile);
  }

  /// Ends [failCommits]: the database file is back under its name.
  void healCommits() {
    if (commitsFailing) File(_movedFile).renameSync(_file);
  }

  /// Closes this store and opens the same file again (the directory moves to the result).
  Future<CoreTestStore> reopen() async {
    healCommits();
    await store.close();
    return CoreTestStore._(await _reopen(), directory, _reopen);
  }

  /// Heals commits first: close waits for the queued writes (CORE 6.9).
  Future<void> close() async {
    healCommits();
    await store.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  /// One synthetic stroke on [pageId] through a session (opens the note: N-6 markOpened).
  Future<Stroke> addStroke(PageId pageId, {int seed = 0}) async {
    final page = await store.content.getPage(pageId);
    if (page == null) throw StateError('no page $pageId');
    final session = await store.openSession(page.noteId);
    try {
      final stroke = StrokeFixtures.synthetic(
        pageId: pageId,
        ids: store.ids,
        seed: seed,
        createdAt: store.clock.now().millisecondsSinceEpoch,
      );
      await session.executeAsync(AddStrokes(pageId: pageId, strokes: [stroke]));
      await session.flush();
      return stroke;
    } finally {
      await session.close();
    }
  }

  /// Runs [command] in a session of [noteId].
  Future<void> edit(NoteId noteId, EditCommand command) async {
    final session = await store.openSession(noteId);
    try {
      await session.executeAsync(command);
      await session.flush();
    } finally {
      await session.close();
    }
  }
}

/// SyncStoreContractDriver over real CORE (test/contract/sync_store_contract.dart).
final class CoreStoreDriver implements SyncStoreContractDriver {
  CoreStoreDriver(this.core);

  static Future<CoreStoreDriver> open({
    required String deviceNodeId,
    required Clock clock,
  }) async => CoreStoreDriver(
    await CoreTestStore.open(deviceNodeId: deviceNodeId, clock: clock),
  );

  final CoreTestStore core;
  int _seed = 0;

  NoteStore get _store => core.store;

  @override
  SyncStore get sync => core.local.sync;

  @override
  AssetStore get assets => core.local.assets;

  @override
  Stream<void> get localChanges => core.local.localChanges;

  @override
  Future<FolderId> createFolder(String name) async =>
      (await _store.library.createFolder(name: name)).id;

  @override
  Future<NoteId> createNote(String title, {FolderId? folderId}) async =>
      (await _store.library.createNote(title: title, folderId: folderId)).id;

  @override
  Future<List<PageId>> activePageIds(NoteId noteId) async => [
    for (final page in await _store.content.pagesOf(noteId)) page.id,
  ];

  @override
  Future<void> renameNote(NoteId noteId, String title) =>
      _store.library.renameNote(noteId, title);

  @override
  Future<ElementId> addStroke(PageId pageId) async =>
      (await core.addStroke(pageId, seed: ++_seed)).id;

  @override
  Future<void> trashNote(NoteId noteId) =>
      _store.library.trashItems([NoteRef(noteId)]);

  @override
  Future<void> trashFolder(FolderId folderId) =>
      _store.library.trashItems([FolderRef(folderId)]);

  @override
  Future<void> purgeNote(NoteId noteId) =>
      _store.trash.purge([NoteRef(noteId)]);

  @override
  Future<Asset> putAsset(Uint8List bytes) => _store.assets.put(
    bytes,
    type: AssetType.pdf,
    mimeType: 'application/pdf',
  );

  /// N-6: openSession is CORE's only markOpened path.
  @override
  Future<void> markOpened(NoteId noteId) async {
    final session = await _store.openSession(noteId);
    await session.close();
  }

  @override
  Future<NoteLocalValues> noteLocal(NoteId noteId) async {
    final note = await _store.library.getNote(noteId);
    if (note == null) throw StateError('no note $noteId');
    return (
      lastOpenedAt: note.lastOpenedAt,
      pageCount: note.pageCount,
      firstPageId: note.firstPageId,
    );
  }

  @override
  Future<int> contentRevision(PageId pageId) async {
    final page = await _store.content.getPage(pageId);
    if (page == null) throw StateError('no page $pageId');
    return page.contentRevision;
  }

  @override
  Future<bool> hasLocalBytes(AssetId assetId) =>
      _store.assets.hasBytes(assetId);

  @override
  Future<SyncStoreContractDriver?> reopen() async =>
      CoreStoreDriver(await core.reopen());

  @override
  Future<void> close() => core.close();
}
