// Real CORE for the T16 integration tests (integration stage): openTestNoteStore on a
// temporary SQLite file (so it can be reopened), wrapped by CoreSyncLocalStore, and the
// SyncStore contract driver doing local edits the way the app does them (5.1.4): library
// and trash repositories, a session's AddStrokes, assets.put, markOpened through
// openSession (N-6) and reopening the same file. (2nd round, 07-sync 6.6) A session's
// AddObjects / UpdateObjects / RemoveElements, store.handwriting.put and
// store.recordings.createRecording / renameRecording (compile-only until the CORE milestones
// of 07-sync 6.7.2 — the integration tag is skipped by default); (S2-9) CoreTestStore's edits
// for the T16-v2 scenarios (objects through a session's AddObjects / TransformElements /
// UpdateObjects / RemoveElements, DeletePages, a fresh handwriting result, a recording with its
// audio asset, a stroke linked to a recording, trash + purge). Commit failures for S-20 (5.1.2) come from
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
  /// (2nd round) [recordingId] / [recordingOffsetMs] link it to a recording (M6 pen meta).
  Future<Stroke> addStroke(
    PageId pageId, {
    int seed = 0,
    RecordingId? recordingId,
    int? recordingOffsetMs,
  }) async {
    final page = await store.content.getPage(pageId);
    if (page == null) throw StateError('no page $pageId');
    final session = await store.openSession(page.noteId);
    try {
      final stroke =
          StrokeFixtures.synthetic(
            pageId: pageId,
            ids: store.ids,
            seed: seed,
            createdAt: store.clock.now().millisecondsSinceEpoch,
          ).copyWith(
            recordingId: recordingId,
            recordingOffsetMs: recordingOffsetMs,
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

  // ---- 2nd round (07-sync 6.7.2, T16-v2): edits the way EDITOR / LIBRARY make them --------

  EpochMillis get _now => store.clock.now().millisecondsSinceEpoch;

  /// The note of [pageId] (deleted pages too).
  Future<NoteId> noteOf(PageId pageId) async {
    final page = await store.content.getPage(pageId);
    if (page == null) throw StateError('no page $pageId');
    return page.noteId;
  }

  /// Runs [command] in a session of [pageId]'s note.
  Future<void> editPage(PageId pageId, EditCommand command) async =>
      edit(await noteOf(pageId), command);

  /// The active objects of [pageId] (PageContent.objects).
  Future<List<PageObject>> objectsOf(PageId pageId) async =>
      (await store.content.loadPage(pageId)).objects;

  /// The active object [id] of [pageId], or null.
  Future<PageObject?> objectOf(PageId pageId, ElementId id) async {
    for (final o in await objectsOf(pageId)) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Adds [object] (a fixture: version null, its own pageId) through a session's AddObjects.
  Future<T> addObject<T extends PageObject>(T object) async {
    await editPage(
      object.pageId,
      AddObjects(pageId: object.pageId, objects: [object]),
    );
    return object;
  }

  /// A lasso move: TransformElements by (dx, dy) — strokes and objects alike.
  Future<void> moveElements(
    PageId pageId,
    List<ElementId> ids, {
    required double dx,
    required double dy,
  }) => editPage(
    pageId,
    TransformElements(
      pageId: pageId,
      elementIds: ids,
      transform: Affine2.translation(dx, dy),
    ),
  );

  /// Handles, style or a text editing session's end: UpdateObjects with [objects] (same ids).
  Future<void> updateObjects(PageId pageId, List<PageObject> objects) =>
      editPage(pageId, UpdateObjects(pageId: pageId, objects: objects));

  /// Delete / cut: RemoveElements.
  Future<void> removeElements(PageId pageId, List<ElementId> ids) =>
      editPage(pageId, RemoveElements(pageId: pageId, elementIds: ids));

  /// The page panel's delete: DeletePages.
  Future<void> deletePages(NoteId noteId, List<PageId> pageIds) =>
      edit(noteId, DeletePages(pageIds: pageIds));

  /// The recognizer's write of [pageId]'s result: one line per entry of [lines] over the
  /// page's input strokes, sourceRev = HandwritingText.sourceRevOf(those strokes) (CORE 6.9.2
  /// — the value a fresh result has), engine 't16:ko'. Returns the value written.
  Future<HandwritingText> putHandwriting(
    PageId pageId,
    List<String> lines,
  ) async {
    final page = await store.content.getPage(pageId);
    if (page == null) throw StateError('no page $pageId');
    final input = [
      for (final s in (await store.content.loadPage(pageId)).strokes)
        if (HandwritingText.isRecognitionInput(s)) s,
    ];
    final value = HandwritingText(
      noteId: page.noteId,
      pageId: pageId,
      engineId: 't16:ko',
      sourceRev: HandwritingText.sourceRevOf(input),
      lines: [
        for (final (i, text) in lines.indexed)
          HandwritingLine(
            text: text,
            rect: PageRect(40, 80 + 60.0 * i, 320, 120 + 60.0 * i),
            strokeIds: [for (final s in input) s.id],
          ),
      ],
      createdAt: _now,
    );
    await store.handwriting.put(value);
    return value;
  }

  /// A finished recording the way media_io saves it (M-1): the audio asset first, then
  /// RecordingRepository.createRecording.
  Future<Recording> createRecording(
    NoteId noteId, {
    int seed = 0,
    int durationMs = 1000,
    String? title,
  }) async {
    final audio = await store.assets.put(
      Uint8List.fromList(List<int>.generate(400, (i) => (i * 37 + seed) % 251)),
      type: AssetType.audio,
      mimeType: 'audio/webm',
    );
    return store.recordings.createRecording(
      id: store.ids.newId(),
      noteId: noteId,
      assetId: audio.id,
      durationMs: durationMs,
      startedAt: _now,
      title: title,
    );
  }

  /// The library's trash, then the trash's purge of [noteId] (purge takes trashed roots only).
  Future<void> trashAndPurge(NoteId noteId) async {
    await store.library.trashItems([NoteRef(noteId)]);
    await store.trash.purge([NoteRef(noteId)]);
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

  // ---- 2nd round (07-sync 6.6) -------------------------------------------------------

  /// Object id → its page (UpdateObjects / RemoveElements name the page).
  final Map<ElementId, PageId> _objectPages = {};

  /// Page → createdAt of its first handwriting put (later puts keep it).
  final Map<PageId, int> _handwritingCreated = {};

  int get _now => _store.clock.now().millisecondsSinceEpoch;

  Future<NoteId> _noteOf(PageId pageId) async {
    final page = await _store.content.getPage(pageId);
    if (page == null) throw StateError('no page $pageId');
    return page.noteId;
  }

  @override
  Future<ElementId> addObject(PageId pageId) async {
    final shape = PageObjectFixtures.shape(
      pageId: pageId,
      id: _store.ids.newId(),
      createdAt: _now,
    );
    await core.edit(
      await _noteOf(pageId),
      AddObjects(pageId: pageId, objects: [shape]),
    );
    _objectPages[shape.id] = pageId;
    return shape.id;
  }

  @override
  Future<void> restyleObject(ElementId objectId) async {
    final pageId = _objectPages[objectId]!;
    final content = await _store.content.loadPage(pageId);
    final shape =
        content.objects.firstWhere((o) => o.id == objectId) as ShapeObject;
    await core.edit(
      await _noteOf(pageId),
      UpdateObjects(
        pageId: pageId,
        objects: [
          shape.copyWith(
            style: shape.style.copyWith(strokeColorArgb: 0xFFD03030),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> removeObject(ElementId objectId) async {
    final pageId = _objectPages[objectId]!;
    await core.edit(
      await _noteOf(pageId),
      RemoveElements(pageId: pageId, elementIds: [objectId]),
    );
  }

  @override
  Future<void> putHandwriting(
    PageId pageId, {
    List<String> lines = const ['가나'],
  }) async {
    final at = _handwritingCreated.putIfAbsent(pageId, () => _now);
    await _store.handwriting.put(
      contractHandwriting(await _noteOf(pageId), pageId, at: at, lines: lines),
    );
  }

  @override
  Future<RecordingId> createRecording(NoteId noteId) async {
    final audio = await _store.assets.put(
      contractBytes(++_seed + 100, 200),
      type: AssetType.audio,
      mimeType: 'audio/webm',
    );
    final recording = await _store.recordings.createRecording(
      id: _store.ids.newId(),
      noteId: noteId,
      assetId: audio.id,
      durationMs: 1000,
      startedAt: _now,
    );
    return recording.id;
  }

  @override
  Future<void> renameRecording(RecordingId recordingId, String? title) =>
      _store.recordings.renameRecording(recordingId, title);

  @override
  Future<List<ElementId>> activeObjectIds(PageId pageId) async => [
    for (final o in (await _store.content.loadPage(pageId)).objects) o.id,
  ];

  @override
  Stream<ChangeBatch> get changeBatches => _store.changes;
}
