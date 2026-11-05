// Internal: the in-memory NoteStore behind createFakeNoteStore() (CORE 6.19, contract 7.6
// 'B2 테스트·개발 도우미'). Same value types, ordering, search and trash rules as the real
// store; no SQLite, no outbox / field versions, no remote path (N-7 does not apply).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

import '../assets/asset_store.dart';
import '../backup/backup_export.dart';
import '../common/errors.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/sort_keys.dart';
import '../common/sort_planner.dart';
import '../common/text_normalize.dart';
import '../edit/command_resolver.dart';
import '../edit/page_draft.dart';
import '../model/asset.dart';
import '../model/folder.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/pen_preset.dart';
import '../model/pen_style.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../repo/content_reader.dart';
import '../repo/events.dart';
import '../repo/folder_tree.dart';
import '../repo/folder_tree_equality.dart';
import '../repo/library_repository.dart';
import '../repo/library_types.dart';
import '../repo/note_store.dart';
import '../repo/pen_preset_repository.dart';
import '../repo/settings_internal.dart';
import '../repo/settings_repository.dart';
import '../repo/status.dart';
import '../repo/trash_repository.dart';
import '../session/note_session.dart';
import '../session/page_content.dart';
import '../session/session_backend.dart';
import '../session/session_engine.dart';
import '../sync/field_versions.dart';
import '../sync/merge.dart';
import '../sync/outbox_types.dart';
import '../sync/sync_store.dart';
import 'fake_write_queue.dart';

/// Device node id of the fake store's HLC (CORE 4.10 'B2 단계 값').
const String kFakeDeviceNodeId = '0000000000000001';

/// Default presets (contract 7.2.4, CORE 6.2.2).
const Map<PenTool, String> _defaultPresetNames = {
  PenTool.ballpoint: '볼펜',
  PenTool.fountain: '만년필',
  PenTool.highlighter: '형광펜',
  PenTool.pencil: '연필',
  PenTool.marker: '마커',
};
const Hlc _seedHlc = Hlc(1, 0, '0000000000000000');

int _byKey(String ka, String ia, String kb, String ib) =>
    compareSortKeyThenId(ka, ia, kb, ib);

String _checkName(String name, {int max = 200, String what = 'name'}) {
  final t = name.trim();
  if (t.isEmpty || t.length > max) {
    throw ArgumentError.value(
      name,
      what,
      'must be 1..$max characters after trim',
    );
  }
  return t;
}

/// Cuts [name] so that name + suffix fits [max] (C-5), never splitting a surrogate pair.
String _nameWithSuffix(String name, String suffix, {int max = 200}) {
  if (name.length + suffix.length <= max) return name + suffix;
  var cut = max - suffix.length;
  if (cut > 0 && cut < name.length) {
    final unit = name.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
  }
  return name.substring(0, cut.clamp(0, name.length)) + suffix;
}

final class FakeNoteStore implements NoteStore {
  FakeNoteStore({
    required this.clock,
    required this.ids,
    required this._ownerId,
    required bool seedDefaultPenPresets,
    required this._storageInfo,
    required FakeNoteStoreFaults faults,
  }) : hlc = HlcClock(nodeId: kFakeDeviceNodeId, clock: clock) {
    queue = FakeWriteQueue(
      clock: clock,
      faults: faults,
      onCommitted: _committed,
    );
    library = _FakeLibrary(this);
    trash = _FakeTrash(this);
    penPresets = _FakePresets(this);
    settings = _FakeSettings(this);
    content = _FakeContentReader(this);
    assets = FakeAssets(this);
    thumbnails = FakeThumbnails(this);
    sync = _FakeSyncStore(this);
    if (seedDefaultPenPresets) _seedDefaults();
  }

  @override
  final Clock clock;
  @override
  final IdGenerator ids;
  final HlcClock hlc;
  final OwnerId _ownerId;
  final StorageInfo _storageInfo;
  late final FakeWriteQueue queue;
  final Duration trashRetention = const Duration(days: 30);

  // Tables.
  final Map<FolderId, Folder> folders = {};
  final Map<NoteId, Note> notes = {};
  final Map<PageId, Page> pages = {};
  final Map<ElementId, Stroke> strokes = {};
  final Map<PageId, Set<ElementId>> strokesOfPage = {};
  final Map<PresetId, PenPreset> presets = {};
  final Map<AssetId, Asset> assetRows = {};
  final Map<AssetId, Uint8List> blobs = {};
  final Map<String, SettingValue> syncedSettings = {};
  final Map<String, String> deviceSettings = {};
  final Map<PageId, PageThumbnail> thumbnailRows = {};
  final Set<String> kv = {};

  final Map<NoteId, SessionEngine> _sessions = {};
  final Set<void Function()> _watchers = {};
  final StreamController<ChangeBatch> _changes = StreamController.broadcast();

  /// EntityChanges of the commit in progress, grouped by origin.
  final List<(ChangeOrigin, List<EntityChange>)> _pendingBatches = [];
  bool _closed = false;

  @override
  late final LibraryRepository library;
  @override
  late final TrashRepository trash;
  @override
  late final PenPresetRepository penPresets;
  @override
  late final SettingsRepository settings;
  @override
  late final NoteContentReader content;
  @override
  late final FakeAssets assets;
  @override
  late final FakeThumbnails thumbnails;
  @override
  late final SyncStore sync;

  @override
  OwnerId get ownerId => _ownerId;
  @override
  Stream<ChangeBatch> get changes => _changes.stream;
  @override
  PersistenceStatus get persistenceStatus => queue.status;
  @override
  Stream<PersistenceStatus> get persistenceStatusStream => Stream.multi((c) {
    c.add(queue.status);
    final sub = queue.statusChanges.listen(c.add);
    c.onCancel = sub.cancel;
  }, isBroadcast: true);
  @override
  StorageInfo get storageInfo => _storageInfo;
  @override
  Future<StorageInfo> refreshStorageInfo() async => _storageInfo;

  EpochMillis get now => clock.now().millisecondsSinceEpoch;

  // ---- commit plumbing ------------------------------------------------------------

  /// Runs [body] as one write; [body] mutates the tables and records its changes.
  Future<T> write<T>(T Function() body) => queue.run(body);

  void record(ChangeOrigin origin, List<EntityChange> changes) {
    if (changes.isEmpty) return;
    _pendingBatches.add((origin, changes));
  }

  void _committed() {
    final at = now;
    // One ChangeBatch per origin run of this commit; an entity changed twice keeps its
    // first position and its last value (same as the SQLite store's batchesOf).
    ChangeOrigin? origin;
    var current = <(EntityKind, String), EntityChange>{};
    void close() {
      if (origin != null && current.isNotEmpty) {
        _changes.add(
          ChangeBatch(
            origin: origin,
            changes: List.unmodifiable(current.values),
            committedAt: at,
          ),
        );
      }
    }

    for (final (o, changes) in _pendingBatches) {
      if (o != origin) {
        close();
        origin = o;
        current = {};
      }
      for (final c in changes) {
        current[(c.kind, c.id)] = c;
      }
    }
    close();
    _pendingBatches.clear();
    for (final s in _sessions.values.toList()) {
      final n = notes[s.noteId];
      if (n != null) s.noteCommitted(n);
    }
    for (final w in _watchers.toList()) {
      w();
    }
  }

  /// C-1: current value on listen, then again after every commit that changes it.
  Stream<T> watch<T>(T Function() compute, {bool Function(T, T)? equals}) {
    final eq = equals ?? (T a, T b) => a == b;
    return Stream.multi((c) {
      var last = compute();
      c.add(last);
      void listener() {
        final next = compute();
        if (eq(next, last)) return;
        last = next;
        c.add(next);
      }

      _watchers.add(listener);
      c.onCancel = () => _watchers.remove(listener);
    });
  }

  // ---- entity helpers -------------------------------------------------------------

  Folder? activeFolder(FolderId? id) {
    final f = id == null ? null : folders[id];
    return f != null && !f.isDeleted && f.ownerId == ownerId ? f : null;
  }

  Note? activeNote(NoteId id) {
    final n = notes[id];
    return n != null && !n.isDeleted && n.ownerId == ownerId ? n : null;
  }

  Iterable<Folder> get ownFolders =>
      folders.values.where((f) => f.ownerId == ownerId);
  Iterable<Note> get ownNotes =>
      notes.values.where((n) => n.ownerId == ownerId);

  List<Page> activePagesOf(NoteId noteId) =>
      pages.values.where((p) => p.noteId == noteId && !p.isDeleted).toList()
        ..sort(comparePages);

  List<Stroke> activeStrokesOf(PageId pageId) => [
    for (final id in strokesOfPage[pageId] ?? const <ElementId>{})
      if (strokes[id] case final s? when !s.isDeleted) s,
  ]..sort(Stroke.compareOrder);

  void putStroke(Stroke s) {
    strokes[s.id] = s;
    (strokesOfPage[s.pageId] ??= {}).add(s.id);
  }

  /// pageCount / firstPageId of [noteId] recomputed (local derived values).
  void refreshNoteDerived(NoteId noteId) {
    final n = notes[noteId];
    if (n == null) return;
    final active = activePagesOf(noteId);
    notes[noteId] = n.copyWith(
      pageCount: active.length,
      firstPageId: active.isEmpty ? null : active.first.id,
      clearFirstPageId: active.isEmpty,
    );
  }

  EntityChange changeOf(SyncEntity e, {bool purged = false}) => switch (e) {
    Page(:final noteId) => EntityChange(
      kind: e.kind,
      id: e.id,
      noteId: noteId,
      deleted: e.isDeleted,
      purged: purged,
    ),
    Stroke(:final pageId) => EntityChange(
      kind: e.kind,
      id: e.id,
      noteId: pages[pageId]?.noteId,
      pageId: pageId,
      deleted: e.isDeleted,
      purged: purged,
    ),
    Recording(:final noteId) => EntityChange(
      kind: e.kind,
      id: e.id,
      noteId: noteId,
      deleted: e.isDeleted,
      purged: purged,
    ),
    _ => EntityChange(
      kind: e.kind,
      id: e.id,
      deleted: e.isDeleted,
      purged: purged,
    ),
  };

  /// Writes the active pages and strokes of [drafts] for a new note (createNote / copy).
  List<EntityChange> insertDraftPages(
    NoteId noteId,
    List<PageDraft> drafts,
    Hlc v,
  ) {
    final keys = SortKeys.nBetween(null, null, drafts.length);
    final changes = <EntityChange>[];
    final t = now;
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      final pageId = d.id ?? ids.newId();
      if (pages.containsKey(pageId)) {
        throw ArgumentError.value(pageId, 'draft.id', 'page id already exists');
      }
      final page = Page(
        id: pageId,
        noteId: noteId,
        sortKey: keys[i],
        size: d.size.clamped(),
        background: d.background,
        createdAt: t,
        updatedAt: t,
        version: v,
      );
      pages[pageId] = page;
      changes.add(changeOf(page));
      for (final s in d.strokes) {
        final copy = Stroke(
          id: ids.newId(),
          pageId: pageId,
          style: s.style.normalized(),
          points: s.points,
          recordingId: s.recordingId,
          recordingOffsetMs: s.recordingOffsetMs,
          createdAt: s.createdAt,
          updatedAt: t,
          version: v,
        );
        putStroke(copy);
        changes.add(changeOf(copy));
      }
    }
    return changes;
  }

  void _seedDefaults() {
    if (kv.contains('seed.presets.v1')) return;
    final keys = SortKeys.nBetween(null, null, _defaultPresetNames.length);
    var i = 0;
    final t = now;
    for (final e in _defaultPresetNames.entries) {
      final id = 'preset-default-${e.key.wireName}';
      if (!presets.containsKey(id)) {
        presets[id] = PenPreset(
          id: id,
          ownerId: ownerId,
          name: e.value,
          style: StrokeStyle.defaultsFor(e.key),
          sortKey: keys[i],
          createdAt: t,
          updatedAt: t,
          version: _seedHlc,
        );
      }
      i++;
    }
    kv.add('seed.presets.v1');
  }

  /// ensureDefaults as one commit.
  Future<void> ensureDefaults() => write(() {
    if (kv.contains('seed.presets.v1')) return;
    final before = presets.keys.toSet();
    _seedDefaults();
    record(ChangeOrigin.local, [
      for (final p in presets.values)
        if (!before.contains(p.id)) changeOf(p),
    ]);
  });

  // ---- sessions -------------------------------------------------------------------

  @override
  Future<NoteSession> openSession(
    NoteId noteId, {
    NoteSessionOptions options = const NoteSessionOptions(),
  }) async {
    _checkOpen();
    final note = notes[noteId];
    if (note == null || note.ownerId != ownerId) {
      throw EntityNotFoundException('Note $noteId does not exist');
    }
    var session = _sessions[noteId];
    if (session != null && !session.isClosed) {
      session.retain();
    } else {
      session = SessionEngine(
        note: note,
        pages: activePagesOf(noteId),
        backend: _FakeSessionBackend(this),
        options: options,
        hlc: hlc,
        clock: clock,
        ids: ids,
      );
      _sessions[noteId] = session;
    }
    // N-6: CORE is the only writer of 'recent'. The commit is not awaited.
    unawaited(library.markOpened(noteId).then<void>((_) {}, onError: (_) {}));
    return session;
  }

  void sessionClosed(NoteId noteId) => _sessions.remove(noteId);

  void applySessionWrite(SessionWrite w) {
    final changes = <EntityChange>[];
    for (final e in w.entities) {
      switch (e) {
        case Stroke():
          putStroke(e);
        case Page():
          pages[e.id] = e;
        default:
          throw StateError('Unexpected session entity ${e.kind.name}');
      }
      changes.add(changeOf(e));
    }
    for (final p in w.localPages) {
      final cur = pages[p.id];
      if (cur != null) {
        pages[p.id] = cur.copyWith(contentRevision: p.contentRevision);
      }
    }
    final stored = notes[w.note.id];
    if (stored != null) {
      notes[w.note.id] = stored.copyWith(
        updatedAt: stored.updatedAt > w.note.updatedAt
            ? null
            : w.note.updatedAt,
      );
      refreshNoteDerived(w.note.id);
      changes.add(changeOf(notes[w.note.id]!));
    }
    record(w.origin, changes);
  }

  @override
  Future<void> flush() => queue.flush();

  @override
  Future<void> close() async {
    if (_closed) return;
    await flush();
    _closed = true;
    _sessions.clear();
    await queue.close();
    await _changes.close();
    await assets.dispose();
    await thumbnails.dispose();
  }

  void _checkOpen() {
    if (_closed) throw StateError('The note store is closed');
  }

  /// The real backup format (CORE 6.17, T19): every active and trashed entity, kind
  /// then id order, each with EntityFieldVersions(version) (the fake keeps no per-field
  /// versions); no asset bytes, device settings or thumbnails.
  @override
  Future<Uint8List> exportBackupJson() async {
    _checkOpen();
    await flush();
    final out = BackupJsonWriter(
      exportedAt: now,
      ownerId: ownerId,
      deviceNodeId: kFakeDeviceNodeId,
    );
    final byKind = <EntityKind, Iterable<SyncEntity>>{
      EntityKind.folder: folders.values,
      EntityKind.note: notes.values,
      EntityKind.page: pages.values,
      EntityKind.stroke: strokes.values,
      EntityKind.penPreset: presets.values,
      EntityKind.asset: assetRows.values,
      EntityKind.setting: syncedSettings.values,
    };
    for (final kind in EntityKind.values) {
      final rows = [...?byKind[kind]]..sort((a, b) => a.id.compareTo(b.id));
      for (final e in rows) {
        out.add(e, EntityFieldVersions(e.version ?? _seedHlc));
      }
    }
    return out.finish();
  }
}

// ---- session backend --------------------------------------------------------------

final class _FakeSessionBackend implements SessionBackend {
  _FakeSessionBackend(this.store);
  final FakeNoteStore store;

  @override
  Future<List<Stroke>> loadStrokes(PageId pageId) async {
    await store.flush();
    return store.activeStrokesOf(pageId);
  }

  @override
  Future<void> write(SessionWrite write) =>
      store.write(() => store.applySessionWrite(write));

  @override
  Future<void> flush() => store.flush();

  @override
  void sessionClosed(NoteId noteId) => store.sessionClosed(noteId);
}

// ---- library ------------------------------------------------------------------------

final class _FakeLibrary implements LibraryRepository {
  _FakeLibrary(this.s);
  final FakeNoteStore s;

  static const ListEquality<Note> _notesEq = ListEquality<Note>();

  // Queries -----------------------------------------------------------------------

  FolderTree _tree() => FolderTree(s.ownFolders.where((f) => !f.isDeleted));

  @override
  Stream<FolderTree> watchFolderTree() =>
      s.watch(_tree, equals: sameFolderTree);

  @override
  Stream<LibraryListing> watchListing(LibraryQuery query) =>
      s.watch(() => _listing(query));

  LibraryListing _listing(LibraryQuery q) {
    final folderId = q.folderId;
    if (folderId != null && s.activeFolder(folderId) == null) {
      return LibraryListing(
        folderId: folderId,
        folders: const [],
        notes: const [],
      );
    }
    // Top level also lists items whose parent is missing or deleted (6.8).
    bool inPlace(FolderId? parent) => folderId == null
        ? parent == null || s.activeFolder(parent) == null
        : parent == folderId;
    final fs = s.ownFolders
        .where((f) => !f.isDeleted && inPlace(f.parentId))
        .toList();
    final ns = s.ownNotes
        .where((n) => !n.isDeleted && inPlace(n.folderId))
        .toList();
    int dir(int c) =>
        q.sort != LibrarySortField.custom && q.descending ? -c : c;
    int then(int c, String a, String b) => c != 0 ? c : a.compareTo(b);
    fs.sort(
      (a, b) => dir(switch (q.sort) {
        LibrarySortField.name => then(
          normalizeForSearch(a.name).compareTo(normalizeForSearch(b.name)),
          a.id,
          b.id,
        ),
        LibrarySortField.createdAt => then(
          a.createdAt.compareTo(b.createdAt),
          a.id,
          b.id,
        ),
        LibrarySortField.updatedAt => then(
          a.updatedAt.compareTo(b.updatedAt),
          a.id,
          b.id,
        ),
        LibrarySortField.custom => _byKey(a.sortKey, a.id, b.sortKey, b.id),
      }),
    );
    ns.sort(
      (a, b) => dir(switch (q.sort) {
        LibrarySortField.name => then(
          normalizeForSearch(a.title).compareTo(normalizeForSearch(b.title)),
          a.id,
          b.id,
        ),
        LibrarySortField.createdAt => then(
          a.createdAt.compareTo(b.createdAt),
          a.id,
          b.id,
        ),
        LibrarySortField.updatedAt => then(
          a.updatedAt.compareTo(b.updatedAt),
          a.id,
          b.id,
        ),
        LibrarySortField.custom => _byKey(a.sortKey, a.id, b.sortKey, b.id),
      }),
    );
    return LibraryListing(
      folderId: folderId,
      folders: List.unmodifiable(fs),
      notes: List.unmodifiable(ns),
    );
  }

  @override
  Stream<Note?> watchNote(NoteId id) => s.watch(() {
    final n = s.notes[id];
    return n != null && n.ownerId == s.ownerId ? n : null;
  });

  @override
  Future<Note?> getNote(NoteId id) async {
    final n = s.notes[id];
    return n != null && n.ownerId == s.ownerId ? n : null;
  }

  @override
  Future<Folder?> getFolder(FolderId id) async {
    final f = s.folders[id];
    return f != null && f.ownerId == s.ownerId ? f : null;
  }

  @override
  Stream<List<Note>> watchRecentNotes({int limit = 20}) => s.watch(
    () => List<Note>.unmodifiable(
      (s.ownNotes.where((n) => !n.isDeleted && n.lastOpenedAt != null).toList()
            ..sort((a, b) {
              final c = b.lastOpenedAt!.compareTo(a.lastOpenedAt!);
              return c != 0 ? c : a.id.compareTo(b.id);
            }))
          .take(limit),
    ),
    equals: _notesEq.equals,
  );

  @override
  Stream<List<Note>> watchFavoriteNotes() => s.watch(
    () => List<Note>.unmodifiable(
      s.ownNotes.where((n) => !n.isDeleted && n.isFavorite).toList()
        ..sort((a, b) {
          final c = b.updatedAt.compareTo(a.updatedAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        }),
    ),
    equals: _notesEq.equals,
  );

  @override
  Future<LibrarySearchResult> searchLibrary(
    String query, {
    int limit = 50,
  }) async {
    final q = normalizeForSearch(query);
    if (q.isEmpty) {
      return LibrarySearchResult(
        query: query,
        folders: const [],
        notes: const [],
      );
    }
    int newest(int a, int b, String ia, String ib) {
      final c = b.compareTo(a);
      return c != 0 ? c : ia.compareTo(ib);
    }

    final fs =
        s.ownFolders
            .where(
              (f) => !f.isDeleted && normalizeForSearch(f.name).contains(q),
            )
            .toList()
          ..sort((a, b) => newest(a.updatedAt, b.updatedAt, a.id, b.id));
    final ns =
        s.ownNotes
            .where(
              (n) => !n.isDeleted && normalizeForSearch(n.title).contains(q),
            )
            .toList()
          ..sort((a, b) => newest(a.updatedAt, b.updatedAt, a.id, b.id));
    return LibrarySearchResult(
      query: query,
      folders: List.unmodifiable(fs.take(limit)),
      notes: List.unmodifiable(ns.take(limit)),
    );
  }

  // Folders -------------------------------------------------------------------------

  String _endKey(Iterable<String> keys) => sortKeyAfterAll(keys);

  Iterable<Folder> _childFolders(FolderId? parent) =>
      s.ownFolders.where((f) => !f.isDeleted && f.parentId == parent);
  Iterable<Note> _childNotes(FolderId? parent) =>
      s.ownNotes.where((n) => !n.isDeleted && n.folderId == parent);

  void _requireTarget(FolderId? id) {
    if (id != null && s.activeFolder(id) == null) {
      throw EntityNotFoundException('Folder $id does not exist');
    }
  }

  @override
  Future<Folder> createFolder({
    FolderId? parentId,
    required String name,
    int? colorArgb,
    String? icon,
  }) async {
    final n = _checkName(name);
    if (icon != null && icon.length > 32) {
      throw ArgumentError.value(icon, 'icon', 'at most 32 characters');
    }
    return s.write(() {
      _requireTarget(parentId);
      final t = s.now;
      final f = Folder(
        id: s.ids.newId(),
        ownerId: s.ownerId,
        parentId: parentId,
        name: n,
        colorArgb: colorArgb,
        icon: icon,
        sortKey: _endKey(_childFolders(parentId).map((f) => f.sortKey)),
        createdAt: t,
        updatedAt: t,
        version: s.hlc.now(),
      );
      s.folders[f.id] = f;
      s.record(ChangeOrigin.local, [s.changeOf(f)]);
      return f;
    });
  }

  Folder _folder(FolderId id) {
    final f = s.folders[id];
    if (f == null || f.ownerId != s.ownerId) {
      throw EntityNotFoundException('Folder $id does not exist');
    }
    return f;
  }

  Note _note(NoteId id) {
    final n = s.notes[id];
    if (n == null || n.ownerId != s.ownerId) {
      throw EntityNotFoundException('Note $id does not exist');
    }
    return n;
  }

  void _putFolder(Folder f) {
    s.folders[f.id] = f;
    s.record(ChangeOrigin.local, [s.changeOf(f)]);
  }

  void _putNote(Note n) {
    s.notes[n.id] = n;
    s.record(ChangeOrigin.local, [s.changeOf(n)]);
  }

  @override
  Future<void> renameFolder(FolderId id, String name) async {
    final n = _checkName(name);
    return s.write(() {
      final f = _folder(id);
      if (f.name == n) return;
      _putFolder(f.copyWith(name: n, updatedAt: s.now, version: s.hlc.now()));
    });
  }

  @override
  Future<void> setFolderAppearance(
    FolderId id, {
    int? colorArgb,
    String? icon,
    bool clearColor = false,
    bool clearIcon = false,
  }) async {
    if (icon != null && icon.length > 32) {
      throw ArgumentError.value(icon, 'icon', 'at most 32 characters');
    }
    return s.write(() {
      final f = _folder(id);
      final next = f.copyWith(
        colorArgb: colorArgb,
        clearColor: clearColor,
        icon: icon,
        clearIcon: clearIcon,
      );
      if (next == f) return;
      _putFolder(next.copyWith(updatedAt: s.now, version: s.hlc.now()));
    });
  }

  // Notes ---------------------------------------------------------------------------

  @override
  Future<Note> createNote({
    FolderId? folderId,
    required String title,
    List<PageDraft> pages = const [PageDraft.blankA4],
    NoteCover cover = const FirstPageCover(),
  }) async {
    final t = _checkName(title, what: 'title');
    if (pages.isEmpty || pages.length > 2000) {
      throw ArgumentError.value(
        pages.length,
        'pages',
        'must be 1..2000 drafts',
      );
    }
    for (final d in pages) {
      final id = d.id;
      if (id != null && !isValidEntityId(id)) {
        throw ArgumentError.value(id, 'draft.id', 'invalid entity id');
      }
    }
    return s.write(() {
      _requireTarget(folderId);
      final draftIds = [for (final d in pages) ?d.id];
      if (draftIds.toSet().length != draftIds.length ||
          draftIds.any(s.pages.containsKey)) {
        throw ArgumentError('Draft page ids must be new and unique');
      }
      final v = s.hlc.now();
      final now = s.now;
      final noteId = s.ids.newId();
      final note = Note(
        id: noteId,
        ownerId: s.ownerId,
        folderId: folderId,
        title: t,
        cover: cover,
        sortKey: _endKey(_childNotes(folderId).map((n) => n.sortKey)),
        createdAt: now,
        updatedAt: now,
        version: v,
      );
      s.notes[noteId] = note;
      final changes = [
        s.changeOf(note),
        ...s.insertDraftPages(noteId, pages, v),
      ];
      s.refreshNoteDerived(noteId);
      s.record(ChangeOrigin.local, changes);
      return s.notes[noteId]!;
    });
  }

  @override
  Future<void> renameNote(NoteId id, String title) async {
    final t = _checkName(title, what: 'title');
    return s.write(() {
      final n = _note(id);
      if (n.title == t) return;
      _putNote(n.copyWith(title: t, updatedAt: s.now, version: s.hlc.now()));
    });
  }

  @override
  Future<void> setFavorite(List<NoteId> ids, bool favorite) => s.write(() {
    final v = s.hlc.now();
    for (final id in ids.toSet()) {
      final n = s.notes[id];
      if (n == null || n.ownerId != s.ownerId || n.isFavorite == favorite) {
        continue;
      }
      _putNote(n.copyWith(isFavorite: favorite, updatedAt: s.now, version: v));
    }
  });

  @override
  Future<void> setCover(NoteId id, NoteCover cover) => s.write(() {
    final n = _note(id);
    if (n.cover == cover) return;
    _putNote(n.copyWith(cover: cover, updatedAt: s.now, version: s.hlc.now()));
  });

  @override
  Future<void> setTags(NoteId id, List<String> tags) async {
    final clean = [for (final t in tags) t.trim()];
    if (clean.length > 50 || clean.any((t) => t.isEmpty || t.length > 32)) {
      throw ArgumentError.value(
        tags,
        'tags',
        'at most 50 tags of 1..32 characters',
      );
    }
    return s.write(() {
      final n = _note(id);
      if (const ListEquality<String>().equals(n.tags, clean)) return;
      _putNote(
        n.copyWith(
          tags: List.unmodifiable(clean),
          updatedAt: s.now,
          version: s.hlc.now(),
        ),
      );
    });
  }

  @override
  Future<void> markOpened(NoteId id) => s.write(() {
    final n = _note(id);
    // Local only (lastOpenedAt): no version bump, no outbox, no ChangeBatch entry.
    s.notes[id] = n.copyWith(lastOpenedAt: s.now);
  });

  // Mixed -------------------------------------------------------------------------

  ({List<Folder> folders, List<Note> notes}) _resolveActive(
    List<LibraryItemRef> items,
  ) {
    final fs = <Folder>[];
    final ns = <Note>[];
    for (final ref in items.toSet()) {
      switch (ref) {
        case FolderRef(:final id):
          final f = s.activeFolder(id);
          if (f == null) {
            throw EntityNotFoundException('Folder $id does not exist');
          }
          fs.add(f);
        case NoteRef(:final id):
          final n = s.activeNote(id);
          if (n == null) {
            throw EntityNotFoundException('Note $id does not exist');
          }
          ns.add(n);
      }
    }
    fs.sort((a, b) => _byKey(a.sortKey, a.id, b.sortKey, b.id));
    ns.sort((a, b) => _byKey(a.sortKey, a.id, b.sortKey, b.id));
    return (folders: fs, notes: ns);
  }

  @override
  Future<void> moveItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
  }) => s.write(() {
    _requireTarget(targetFolderId);
    final r = _resolveActive(items);
    final tree = _tree();
    for (final f in r.folders) {
      if (targetFolderId != null &&
          tree.isSelfOrDescendant(targetFolderId, of: f.id)) {
        throw FolderCycleException(
          'Folder ${f.id} cannot move into itself or its descendant $targetFolderId',
        );
      }
    }
    final fs = [
      for (final f in r.folders)
        if (f.parentId != targetFolderId) f,
    ];
    final ns = [
      for (final n in r.notes)
        if (n.folderId != targetFolderId) n,
    ];
    final v = s.hlc.now();
    final t = s.now;
    final fKeys = SortKeys.nBetween(
      _maxKey(_childFolders(targetFolderId).map((f) => f.sortKey)),
      null,
      fs.length,
    );
    for (var i = 0; i < fs.length; i++) {
      _putFolder(
        fs[i].copyWith(
          parentId: targetFolderId,
          clearParentId: targetFolderId == null,
          sortKey: fKeys[i],
          updatedAt: t,
          version: v,
        ),
      );
    }
    final nKeys = SortKeys.nBetween(
      _maxKey(_childNotes(targetFolderId).map((n) => n.sortKey)),
      null,
      ns.length,
    );
    for (var i = 0; i < ns.length; i++) {
      _putNote(
        ns[i].copyWith(
          folderId: targetFolderId,
          clearFolderId: targetFolderId == null,
          sortKey: nKeys[i],
          updatedAt: t,
          version: v,
        ),
      );
    }
  });

  static String? _maxKey(Iterable<String> keys) {
    String? max;
    for (final k in keys) {
      if (max == null || k.compareTo(max) > 0) max = k;
    }
    return max;
  }

  @override
  Future<void> reorderItem(
    LibraryItemRef item, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) => reorderItems([item], after: after, before: before);

  @override
  Future<void> reorderItems(
    List<LibraryItemRef> items, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) async {
    if (items.isEmpty) return;
    final isFolder = items.first is FolderRef;
    final all = [...items, ?after, ?before];
    if (all.any((r) => (r is FolderRef) != isFolder)) {
      throw ArgumentError('reorderItems: folders and notes cannot be mixed');
    }
    final ids = {for (final r in items) r.id};
    if ((after != null && ids.contains(after.id)) ||
        (before != null && ids.contains(before.id))) {
      throw ArgumentError('reorderItems: the anchor is one of the moved items');
    }
    return s.write(() {
      final r = _resolveActive(items);
      final anchor = after ?? before;
      final List<({String key, String id, String? parent})> moving = isFolder
          ? [
              for (final f in r.folders)
                (key: f.sortKey, id: f.id, parent: f.parentId),
            ]
          : [
              for (final n in r.notes)
                (key: n.sortKey, id: n.id, parent: n.folderId),
            ];
      final parent = moving.first.parent;
      if (moving.any((m) => m.parent != parent)) {
        throw ArgumentError('reorderItems: items have different parents');
      }
      final siblings = isFolder
          ? [
              for (final f
                  in _childFolders(parent).toList()
                    ..sort((a, b) => _byKey(a.sortKey, a.id, b.sortKey, b.id)))
                if (!ids.contains(f.id)) (key: f.sortKey, id: f.id),
            ]
          : [
              for (final n
                  in _childNotes(parent).toList()
                    ..sort((a, b) => _byKey(a.sortKey, a.id, b.sortKey, b.id)))
                if (!ids.contains(n.id)) (key: n.sortKey, id: n.id),
            ];
      var index = siblings.length;
      if (anchor != null) {
        final at = siblings.indexWhere((x) => x.id == anchor.id);
        if (at < 0) {
          throw ArgumentError.value(
            anchor.id,
            'anchor',
            'not an active sibling of the moved items',
          );
        }
        index = after != null ? at + 1 : at;
      }
      final plan = planSortKeys(siblings, index, moving.length);
      final v = s.hlc.now();
      final t = s.now;
      final newKeys = {
        for (var i = 0; i < moving.length; i++) moving[i].id: plan.keys[i],
        ...plan.rekeyed,
      };
      for (final e in newKeys.entries) {
        if (isFolder) {
          final f = s.folders[e.key]!;
          if (f.sortKey != e.value) {
            _putFolder(f.copyWith(sortKey: e.value, updatedAt: t, version: v));
          }
        } else {
          final n = s.notes[e.key]!;
          if (n.sortKey != e.value) {
            _putNote(n.copyWith(sortKey: e.value, updatedAt: t, version: v));
          }
        }
      }
    });
  }

  @override
  Future<List<LibraryItemRef>> copyItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
    String nameSuffix = '',
  }) async {
    if (nameSuffix.length >= 200) {
      throw ArgumentError.value(
        nameSuffix,
        'nameSuffix',
        'shorter than 200 characters',
      );
    }
    return s.write(() {
      _requireTarget(targetFolderId);
      for (final ref in items) {
        final ok = ref is FolderRef
            ? s.activeFolder(ref.id) != null
            : s.activeNote(ref.id) != null;
        if (!ok) throw EntityNotFoundException('${ref.id} does not exist');
      }
      final tree = _tree();
      final v = s.hlc.now();
      final changes = <EntityChange>[];
      var folderKey = _maxKey(
        _childFolders(targetFolderId).map((f) => f.sortKey),
      );
      var noteKey = _maxKey(_childNotes(targetFolderId).map((n) => n.sortKey));
      final out = <LibraryItemRef>[];
      for (final ref in items) {
        if (ref is FolderRef) {
          folderKey = SortKeys.between(folderKey, null);
          final f = s.folders[ref.id]!;
          out.add(
            FolderRef(
              _copyFolder(
                tree,
                f,
                targetFolderId,
                folderKey,
                _nameWithSuffix(f.name, nameSuffix),
                v,
                changes,
              ),
            ),
          );
        } else {
          noteKey = SortKeys.between(noteKey, null);
          final n = s.notes[ref.id]!;
          out.add(
            NoteRef(
              copyNote(
                n,
                targetFolderId,
                noteKey,
                _nameWithSuffix(n.title, nameSuffix),
                v,
                changes,
              ),
            ),
          );
        }
      }
      s.record(ChangeOrigin.local, changes);
      return out;
    });
  }

  FolderId _copyFolder(
    FolderTree tree,
    Folder f,
    FolderId? parent,
    String key,
    String name,
    Hlc v,
    List<EntityChange> changes,
  ) {
    final t = s.now;
    final copy = Folder(
      id: s.ids.newId(),
      ownerId: s.ownerId,
      parentId: parent,
      name: name,
      colorArgb: f.colorArgb,
      icon: f.icon,
      sortKey: key,
      createdAt: t,
      updatedAt: t,
      version: v,
    );
    s.folders[copy.id] = copy;
    changes.add(s.changeOf(copy));
    final childFolders = tree.childrenOf(f.id);
    final childNotes = _childNotes(f.id).toList();
    for (final c in childFolders) {
      _copyFolder(tree, c, copy.id, c.sortKey, c.name, v, changes);
    }
    for (final n in childNotes) {
      copyNote(n, copy.id, n.sortKey, n.title, v, changes);
    }
    return copy.id;
  }

  /// Copy of a note with its active pages and strokes under new ids (also used by
  /// duplicate-for-recovery in the real store).
  NoteId copyNote(
    Note n,
    FolderId? folderId,
    String key,
    String title,
    Hlc v,
    List<EntityChange> changes,
  ) {
    final t = s.now;
    final id = s.ids.newId();
    s.notes[id] = Note(
      id: id,
      ownerId: s.ownerId,
      folderId: folderId,
      title: title,
      cover: n.cover,
      tags: n.tags,
      isFavorite: n.isFavorite,
      sortKey: key,
      schemaVersion: n.schemaVersion,
      createdAt: t,
      updatedAt: t,
      version: v,
    );
    changes.add(s.changeOf(s.notes[id]!));
    for (final p in s.activePagesOf(n.id)) {
      final pageId = s.ids.newId();
      final page = Page(
        id: pageId,
        noteId: id,
        sortKey: p.sortKey,
        size: p.size,
        background: p.background,
        createdAt: t,
        updatedAt: t,
        version: v,
      );
      s.pages[pageId] = page;
      changes.add(s.changeOf(page));
      for (final st in s.activeStrokesOf(p.id)) {
        final copy = Stroke(
          id: s.ids.newId(),
          pageId: pageId,
          style: st.style,
          points: st.points,
          recordingId: st.recordingId,
          recordingOffsetMs: st.recordingOffsetMs,
          createdAt: st.createdAt,
          updatedAt: t,
          version: v,
        );
        s.putStroke(copy);
        changes.add(s.changeOf(copy));
      }
    }
    s.refreshNoteDerived(id);
    return id;
  }

  @override
  Future<void> trashItems(List<LibraryItemRef> items) => s.write(() {
    final refs = items.toSet();
    for (final ref in refs) {
      final exists = ref is FolderRef ? s.folders[ref.id] : s.notes[ref.id];
      if (exists == null ||
          (exists is Folder && exists.ownerId != s.ownerId) ||
          (exists is Note && exists.ownerId != s.ownerId)) {
        throw EntityNotFoundException('${ref.id} does not exist');
      }
    }
    final v = s.hlc.now();
    final t = s.now;
    final tree = _tree();
    for (final ref in refs) {
      switch (ref) {
        case FolderRef(:final id):
          final f = s.activeFolder(id);
          if (f == null) continue; // already in the trash
          final group = {id, ...tree.descendantsOf(id)};
          for (final fid in group) {
            final g = s.folders[fid]!;
            if (g.isDeleted) continue;
            _putFolder(
              g.copyWith(
                deletedAt: t,
                trashRootId: id,
                updatedAt: t,
                version: v,
              ),
            );
          }
          for (final n in s.ownNotes.toList()) {
            if (n.isDeleted || !group.contains(n.folderId)) continue;
            _putNote(
              n.copyWith(
                deletedAt: t,
                trashRootId: id,
                updatedAt: t,
                version: v,
              ),
            );
          }
        case NoteRef(:final id):
          final n = s.activeNote(id);
          if (n == null) continue;
          _putNote(
            n.copyWith(deletedAt: t, trashRootId: id, updatedAt: t, version: v),
          );
      }
    }
  });
}

// ---- trash ----------------------------------------------------------------------------

final class _FakeTrash implements TrashRepository {
  _FakeTrash(this.s);
  final FakeNoteStore s;

  int _expiry(int deletedAt) => deletedAt + s.trashRetention.inMilliseconds;

  List<TrashItem> _items() {
    final out = <TrashItem>[
      for (final f in s.ownFolders)
        if (f.isDeleted && f.trashRootId == f.id)
          TrashedFolder(
            folder: f,
            folderCount: s.ownFolders
                .where((x) => x.id != f.id && x.trashRootId == f.id)
                .length,
            noteCount: s.ownNotes.where((n) => n.trashRootId == f.id).length,
            expiresAt: _expiry(f.deletedAt!),
          ),
      for (final n in s.ownNotes)
        if (n.isDeleted && n.trashRootId == n.id)
          TrashedNote(note: n, expiresAt: _expiry(n.deletedAt!)),
    ];
    out.sort((a, b) {
      final c = b.deletedAt.compareTo(a.deletedAt);
      return c != 0 ? c : a.ref.id.compareTo(b.ref.id);
    });
    return List.unmodifiable(out);
  }

  @override
  Stream<List<TrashItem>> watchTrash() =>
      s.watch(_items, equals: const ListEquality<TrashItem>().equals);

  @override
  Future<void> restore(List<LibraryItemRef> items) => s.write(() {
    final v = s.hlc.now();
    final t = s.now;
    final changes = <EntityChange>[];
    for (final ref in items.toSet()) {
      final rootId = ref.id;
      final root = ref is FolderRef ? s.folders[rootId] : s.notes[rootId];
      if (root == null) throw EntityNotFoundException('$rootId does not exist');
      if (!root.isDeleted) continue;
      // The representative's new parent: nearest active ancestor, else top level (6.8).
      FolderId? parent = root is Folder
          ? root.parentId
          : (root as Note).folderId;
      final seen = <FolderId>{};
      while (parent != null && seen.add(parent)) {
        final p = s.folders[parent];
        if (p == null) {
          parent = null;
          break;
        }
        if (!p.isDeleted && p.trashRootId != rootId) break;
        parent = p.parentId;
      }
      for (final f in s.ownFolders.toList()) {
        if (f.trashRootId != rootId) continue;
        var next = f.copyWith(
          clearDeletedAt: true,
          clearTrashRootId: true,
          updatedAt: t,
          version: v,
        );
        if (f.id == rootId && f.parentId != parent) {
          next = next.copyWith(
            parentId: parent,
            clearParentId: parent == null,
            sortKey: sortKeyAfterAll(
              s.ownFolders
                  .where((x) => !x.isDeleted && x.parentId == parent)
                  .map((x) => x.sortKey),
            ),
          );
        }
        s.folders[f.id] = next;
        changes.add(s.changeOf(next));
      }
      for (final n in s.ownNotes.toList()) {
        if (n.trashRootId != rootId) continue;
        var next = n.copyWith(
          clearDeletedAt: true,
          clearTrashRootId: true,
          updatedAt: t,
          version: v,
        );
        if (n.id == rootId && n.folderId != parent) {
          next = next.copyWith(
            folderId: parent,
            clearFolderId: parent == null,
            sortKey: sortKeyAfterAll(
              s.ownNotes
                  .where((x) => !x.isDeleted && x.folderId == parent)
                  .map((x) => x.sortKey),
            ),
          );
        }
        s.notes[n.id] = next;
        changes.add(s.changeOf(next));
      }
    }
    s.record(ChangeOrigin.local, changes);
  });

  void _purgeGroup(String rootId, List<EntityChange> changes) {
    for (final f
        in s.ownFolders.where((f) => f.trashRootId == rootId).toList()) {
      s.folders.remove(f.id);
      changes.add(s.changeOf(f, purged: true));
    }
    for (final n in s.ownNotes.where((n) => n.trashRootId == rootId).toList()) {
      s.notes.remove(n.id);
      changes.add(s.changeOf(n, purged: true));
      for (final p in s.pages.values.where((p) => p.noteId == n.id).toList()) {
        s.pages.remove(p.id);
        s.thumbnailRows.remove(p.id);
        for (final sid in s.strokesOfPage.remove(p.id) ?? const <ElementId>{}) {
          s.strokes.remove(sid);
        }
      }
    }
  }

  @override
  Future<void> purge(List<LibraryItemRef> items) => s.write(() {
    final changes = <EntityChange>[];
    for (final ref in items.toSet()) {
      final root = ref is FolderRef ? s.folders[ref.id] : s.notes[ref.id];
      if (root == null || !root.isDeleted) continue;
      _purgeGroup(ref.id, changes);
    }
    s.record(ChangeOrigin.local, changes);
  });

  @override
  Future<void> emptyTrash() => s.write(() {
    final changes = <EntityChange>[];
    for (final item in _items()) {
      _purgeGroup(item.ref.id, changes);
    }
    s.record(ChangeOrigin.local, changes);
  });

  @override
  Future<int> purgeExpired() => s.write(() {
    final changes = <EntityChange>[];
    var count = 0;
    final t = s.now;
    for (final item in _items()) {
      if (t - item.deletedAt < s.trashRetention.inMilliseconds) continue;
      _purgeGroup(item.ref.id, changes);
      count++;
    }
    s.record(ChangeOrigin.local, changes);
    return count;
  });
}

// ---- pen presets ------------------------------------------------------------------------

final class _FakePresets implements PenPresetRepository {
  _FakePresets(this.s);
  final FakeNoteStore s;

  List<PenPreset> _active() =>
      s.presets.values
          .where((p) => !p.isDeleted && p.ownerId == s.ownerId)
          .toList()
        ..sort((a, b) => _byKey(a.sortKey, a.id, b.sortKey, b.id));

  void _put(PenPreset p) {
    s.presets[p.id] = p;
    s.record(ChangeOrigin.local, [s.changeOf(p)]);
  }

  PenPreset _preset(PresetId id) {
    final p = s.presets[id];
    if (p == null || p.isDeleted || p.ownerId != s.ownerId) {
      throw EntityNotFoundException('Preset $id does not exist');
    }
    return p;
  }

  @override
  Stream<List<PenPreset>> watchPresets() => s.watch(
    () => List<PenPreset>.unmodifiable(_active()),
    equals: const ListEquality<PenPreset>().equals,
  );

  @override
  Future<List<PenPreset>> getPresets() async => List.unmodifiable(_active());

  @override
  Future<PenPreset> createPreset({
    required String name,
    required StrokeStyle style,
    String? group,
    bool pinned = true,
    PresetId? after,
  }) async {
    final n = _checkName(name, max: 60);
    return s.write(() {
      final list = _active();
      var index = list.length;
      if (after != null) {
        final at = list.indexWhere((p) => p.id == after);
        if (at < 0) {
          throw EntityNotFoundException('Preset $after does not exist');
        }
        index = at + 1;
      }
      final plan = planSortKeys(
        [for (final p in list) (key: p.sortKey, id: p.id)],
        index,
        1,
      );
      final v = s.hlc.now();
      final t = s.now;
      for (final e in plan.rekeyed.entries) {
        _put(
          s.presets[e.key]!.copyWith(
            sortKey: e.value,
            updatedAt: t,
            version: v,
          ),
        );
      }
      final p = PenPreset(
        id: s.ids.newId(),
        ownerId: s.ownerId,
        name: n,
        style: style.normalized(),
        group: group,
        pinned: pinned,
        sortKey: plan.keys.single,
        createdAt: t,
        updatedAt: t,
        version: v,
      );
      _put(p);
      return p;
    });
  }

  @override
  Future<void> updatePreset(PenPreset preset) async {
    final n = _checkName(preset.name, max: 60);
    return s.write(() {
      final cur = _preset(preset.id);
      final next = cur.copyWith(
        name: n,
        style: preset.style.normalized(),
        group: preset.group,
        clearGroup: preset.group == null,
        pinned: preset.pinned,
      );
      if (next == cur) return;
      _put(next.copyWith(updatedAt: s.now, version: s.hlc.now()));
    });
  }

  @override
  Future<void> reorderPreset(
    PresetId id, {
    PresetId? after,
    PresetId? before,
  }) => s.write(() {
    final cur = _preset(id);
    final rest = [
      for (final p in _active())
        if (p.id != id) p,
    ];
    var index = rest.length;
    final anchor = after ?? before;
    if (anchor != null) {
      final at = rest.indexWhere((p) => p.id == anchor);
      if (at < 0) {
        throw ArgumentError.value(anchor, 'anchor', 'not an active preset');
      }
      index = after != null ? at + 1 : at;
    }
    final plan = planSortKeys(
      [for (final p in rest) (key: p.sortKey, id: p.id)],
      index,
      1,
    );
    final v = s.hlc.now();
    final t = s.now;
    for (final e in plan.rekeyed.entries) {
      _put(
        s.presets[e.key]!.copyWith(sortKey: e.value, updatedAt: t, version: v),
      );
    }
    if (cur.sortKey != plan.keys.single) {
      _put(cur.copyWith(sortKey: plan.keys.single, updatedAt: t, version: v));
    }
  });

  @override
  Future<void> reorderPresets(List<PresetId> orderedIds) => s.write(() {
    final active = _active();
    final byId = {for (final p in active) p.id: p};
    final listed = <PenPreset>[];
    for (final id in orderedIds) {
      final p = byId.remove(id);
      if (p != null) listed.add(p);
    }
    final order = [...listed, ...active.where((p) => byId.containsKey(p.id))];
    final keys = SortKeys.nBetween(null, null, order.length);
    final v = s.hlc.now();
    final t = s.now;
    for (var i = 0; i < order.length; i++) {
      if (order[i].sortKey == keys[i]) continue;
      _put(order[i].copyWith(sortKey: keys[i], updatedAt: t, version: v));
    }
  });

  @override
  Future<void> deletePreset(PresetId id) => s.write(() {
    final p = _preset(id);
    final t = s.now;
    _put(p.copyWith(deletedAt: t, updatedAt: t, version: s.hlc.now()));
  });

  @override
  Future<void> ensureDefaults() => s.ensureDefaults();
}

// ---- settings ---------------------------------------------------------------------------

final class _FakeSettings implements SettingsRepository {
  _FakeSettings(this.s);
  final FakeNoteStore s;

  Object? _rawOf(String name) {
    final device = s.deviceSettings[name];
    if (device != null) return jsonDecode(device);
    final synced = s.syncedSettings[name];
    if (synced == null || synced.isDeleted) return null;
    return jsonDecode(synced.valueJson);
  }

  T _value<T>(SettingKey<T> key) => decodeSetting(key, _rawOf(key.name));

  @override
  Future<T> get<T>(SettingKey<T> key) async {
    checkSettingKeyName(key.name);
    return _value(key);
  }

  @override
  Stream<T> watch<T>(SettingKey<T> key) {
    checkSettingKeyName(key.name);
    return s.watch(
      () => _value(key),
      equals: (a, b) => const DeepCollectionEquality().equals(a, b),
    );
  }

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    checkSettingKeyName(key.name);
    final String json;
    try {
      json = jsonEncode(key.encode(value));
    } on Object catch (e) {
      throw ArgumentError.value(value, 'value', 'not JSON-encodable: $e');
    }
    return s.write(() {
      if (key.scope == SettingScope.device) {
        s.deviceSettings[key.name] = json;
        return;
      }
      final cur = s.syncedSettings[key.name];
      if (cur != null && !cur.isDeleted && cur.valueJson == json) return;
      final next = SettingValue(
        key: key.name,
        valueJson: json,
        updatedAt: s.now,
        version: s.hlc.now(),
      );
      s.syncedSettings[key.name] = next;
      s.record(ChangeOrigin.local, [s.changeOf(next)]);
    });
  }

  @override
  Future<void> reset<T>(SettingKey<T> key) async {
    checkSettingKeyName(key.name);
    return s.write(() {
      if (key.scope == SettingScope.device) {
        s.deviceSettings.remove(key.name);
        return;
      }
      final cur = s.syncedSettings[key.name];
      if (cur == null || cur.isDeleted) return;
      final t = s.now;
      final next = cur.copyWith(
        deletedAt: t,
        updatedAt: t,
        version: s.hlc.now(),
      );
      s.syncedSettings[key.name] = next;
      s.record(ChangeOrigin.local, [s.changeOf(next)]);
    });
  }

  SettingsSnapshot _snapshot() => SettingsSnapshot(
    Map.unmodifiable({
      for (final e in s.syncedSettings.entries)
        if (!e.value.isDeleted) e.key: jsonDecode(e.value.valueJson),
      for (final e in s.deviceSettings.entries) e.key: jsonDecode(e.value),
    }),
  );

  @override
  Stream<SettingsSnapshot> watchAll() => s.watch(_snapshot);
}

// ---- content reader ---------------------------------------------------------------------

final class _FakeContentReader implements NoteContentReader {
  _FakeContentReader(this.s);
  final FakeNoteStore s;

  @override
  Future<List<Page>> pagesOf(NoteId noteId) async =>
      List.unmodifiable(s.activePagesOf(noteId));

  @override
  Future<PageContent> loadPage(PageId pageId) async {
    final p = s.pages[pageId];
    if (p == null) throw EntityNotFoundException('Page $pageId does not exist');
    return PageContent(
      page: p,
      strokes: s.activeStrokesOf(pageId),
      revision: 0,
    );
  }

  @override
  Future<Page?> getPage(PageId pageId) async {
    final p = s.pages[pageId];
    return p == null || p.isDeleted ? null : p;
  }
}

// ---- assets / thumbnails ------------------------------------------------------------------

final class FakeAssets implements AssetStore {
  FakeAssets(this.s);
  final FakeNoteStore s;
  final StreamController<AssetId> _arrived = StreamController.broadcast();
  final Map<AssetId, Future<Asset>> _pendingPuts = {};

  @override
  Stream<AssetId> get bytesArrived => _arrived.stream;

  static String hashOf(Uint8List bytes) => sha256.convert(bytes).toString();

  @override
  Future<Asset> put(
    Uint8List bytes, {
    required AssetType type,
    required String mimeType,
    String? fileName,
  }) {
    final id = hashOf(bytes);
    final existing = s.assetRows[id];
    if (existing != null && existing.hasLocalBytes && s.blobs.containsKey(id)) {
      return Future.value(existing);
    }
    final pending = _pendingPuts[id];
    if (pending != null) return pending;
    // Bytes first (the fake blob store never fails), then the metadata commit (6.13 ③).
    s.blobs[id] = Uint8List.fromList(bytes);
    final future = s
        .write(() {
          final cur = s.assetRows[id];
          final Asset row;
          if (cur != null) {
            row = cur.copyWith(hasLocalBytes: true);
          } else {
            row = Asset(
              id: id,
              ownerId: s.ownerId,
              type: type,
              mimeType: mimeType,
              size: bytes.length,
              fileName: fileName,
              createdAt: s.now,
              version: s.hlc.now(),
            );
            s.record(ChangeOrigin.local, [s.changeOf(row)]);
          }
          s.assetRows[id] = row;
          return row;
        })
        .whenComplete(() {
          // A block body: returning the removed Future here would make whenComplete
          // wait for itself.
          _pendingPuts.remove(id);
        });
    _pendingPuts[id] = future.then((row) {
      if (!_arrived.isClosed) _arrived.add(id);
      return row;
    });
    return _pendingPuts[id]!;
  }

  @override
  Future<Asset?> getAsset(AssetId id) async => s.assetRows[id];

  @override
  Future<Uint8List?> readBytes(AssetId id) async {
    final row = s.assetRows[id];
    final b = s.blobs[id];
    return row != null && row.hasLocalBytes && b != null
        ? Uint8List.fromList(b)
        : null;
  }

  @override
  Future<bool> hasBytes(AssetId id) async {
    final row = s.assetRows[id];
    return row != null && row.hasLocalBytes && s.blobs.containsKey(id);
  }

  @override
  Future<void> putDownloadedBytes(AssetId id, Uint8List bytes) {
    if (hashOf(bytes) != id) {
      return Future.error(
        AssetHashMismatchException('Downloaded bytes do not hash to $id'),
      );
    }
    s.blobs[id] = Uint8List.fromList(bytes);
    return s
        .write(() {
          final cur = s.assetRows[id];
          if (cur != null) s.assetRows[id] = cur.copyWith(hasLocalBytes: true);
        })
        .then((_) {
          if (!_arrived.isClosed) _arrived.add(id);
        });
  }

  @override
  Future<List<Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) async =>
      List.unmodifiable(
        s.assetRows.values.where(
          (a) =>
              !a.isDeleted &&
              a.ownerId == s.ownerId &&
              (hasLocalBytes == null || a.hasLocalBytes == hasLocalBytes) &&
              (uploaded == null || (a.storagePath != null) == uploaded),
        ),
      );

  @override
  Future<void> markUploaded(AssetId id, String storagePath) => s.write(() {
    final cur = s.assetRows[id];
    if (cur == null) throw EntityNotFoundException('Asset $id does not exist');
    final next = cur.copyWith(storagePath: storagePath, version: s.hlc.now());
    s.assetRows[id] = next;
    s.record(ChangeOrigin.local, [s.changeOf(next)]);
  });

  @override
  Future<AssetStorageUsage> usage() async => AssetStorageUsage(
    assetCount: s.assetRows.values.where((a) => !a.isDeleted).length,
    totalBytes: s.assetRows.values
        .where((a) => !a.isDeleted && a.hasLocalBytes)
        .fold(0, (sum, a) => sum + a.size),
    thumbnailBytes: s.thumbnailRows.values.fold(
      0,
      (sum, t) => sum + t.bytes.length,
    ),
  );

  Future<void> dispose() => _arrived.close();
}

final class FakeThumbnails implements ThumbnailCache {
  FakeThumbnails(this.s);
  final FakeNoteStore s;
  final StreamController<PageId> _updates = StreamController.broadcast();

  @override
  Stream<PageId> get updates => _updates.stream;

  @override
  Future<PageThumbnail?> read(PageId pageId) async => s.thumbnailRows[pageId];

  @override
  Future<void> write(PageThumbnail thumbnail) async {
    s.thumbnailRows[thumbnail.pageId] = thumbnail;
    if (!_updates.isClosed) _updates.add(thumbnail.pageId);
  }

  @override
  Future<void> delete(PageId pageId) async {
    s.thumbnailRows.remove(pageId);
    if (!_updates.isClosed) _updates.add(pageId);
  }

  Future<void> dispose() => _updates.close();
}

// ---- sync store ---------------------------------------------------------------------------

/// SyncStore of the fake: ownerId / deviceNodeId return values, pendingChanges() is empty,
/// watchPendingCount() emits 0, every other member throws UnsupportedError (contract 7.6).
final class _FakeSyncStore implements SyncStore {
  _FakeSyncStore(this.s);
  final FakeNoteStore s;

  static Never _unsupported(String member) => throw UnsupportedError(
    'createFakeNoteStore().sync.$member is not supported; SYNC contract tests use '
    'openTestNoteStore() (contract 7.6)',
  );

  @override
  String get deviceNodeId => kFakeDeviceNodeId;
  @override
  OwnerId get ownerId => s.ownerId;
  @override
  Future<List<OutboxEntry>> pendingChanges({
    int limit = 500,
    int? afterSeq,
  }) async => const [];
  @override
  Stream<int> watchPendingCount() => Stream<int>.value(0);
  @override
  Future<void> acknowledge(List<OutboxAck> acks) => _unsupported('acknowledge');
  @override
  Future<List<VersionedEntity?>> readVersioned(List<EntityRef> refs) =>
      _unsupported('readVersioned');
  @override
  Future<RemoteApplyReport> applyRemote(
    List<RemoteChange> changes, {
    required RemoteMergePolicy policy,
    Map<String, String> metaUpdates = const {},
  }) => _unsupported('applyRemote');
  @override
  Future<void> commitRepairs(List<RepairWrite> repairs) =>
      _unsupported('commitRepairs');
  @override
  Future<String?> readMeta(String key) => _unsupported('readMeta');
  @override
  Future<void> writeMeta(Map<String, String> updates) =>
      _unsupported('writeMeta');
  @override
  Future<void> reassignOwner({required OwnerId from, required OwnerId to}) =>
      _unsupported('reassignOwner');
  @override
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  }) => _unsupported('duplicateNoteForRecovery');
}
