// test/support/fake_library_backend.dart — 05-library 5.7 (L0).
//
// Web-safe: imports package:note_core/testing.dart, never testing_vm.dart
// (test/web/ uses this file too).
import 'package:clock/clock.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import 'test_clock.dart';

/// LIBRARY's thin layer over a NoteStore: failure / latency injection and a
/// call log on the two repositories LIBRARY mutates, plus seeding through the
/// CORE API. Everything else is the store itself (CORE fake, or real CORE in
/// L21). CORE semantics are never re-implemented here.
///
/// [calls] has one entry per mutating call of [library] / [trash], written
/// BEFORE the latency and the injected failure (a call that fails is still
/// logged):
///
///     createFolder <home|f:id> '<name>'[ color:0xAARRGGBB][ icon:<key>]
///     renameFolder f:<id> '<name>'
///     setFolderAppearance f:<id>[ color:..][ icon:..][ clearColor][ clearIcon]
///     createNote <home|f:id> '<title>' pages:<n> cover:<cover>
///     renameNote n:<id> '<title>'
///     setFavorite [n:<id>, ...] <true|false>
///     setCover n:<id> <firstPage|color:0x..|asset:<id>>
///     setTags n:<id> [<tag>, ...]
///     markOpened <id>
///     moveItems [n:<id>, f:<id>] -> <home|f:id>
///     reorderItem <ref>[ after:<ref>][ before:<ref>]
///     reorderItems [<ref>, ...][ after:<ref>][ before:<ref>]
///     copyItems [<ref>, ...] -> <home|f:id> suffix:'<suffix>'
///     trashItems [<ref>, ...]
///     restore [<ref>, ...] | purge [<ref>, ...] | emptyTrash | purgeExpired
///
/// [queries] logs the read calls the same way (e.g. 'watchFolderTree',
/// 'watchListing LibraryQuery(folder: null, updatedAt, desc)',
/// "searchLibrary '<q>' limit:50"), so tests can see which reads went through
/// the wrappers and with which arguments.
final class FakeLibraryBackend {
  /// Over CORE's shared fake (every unit / widget / browser test):
  ///   store = createFakeNoteStore(clock: this.clock.clock,
  ///       storageInfo: storageInfo ??
  ///           const StorageInfo(backend: StorageBackend.nativeFile),
  ///       faults: this.faults)
  /// where this.faults = faults ?? FakeNoteStoreFaults() (never null on this
  /// path).
  factory FakeLibraryBackend({
    TestClock? clock,
    StorageInfo? storageInfo,
    FakeNoteStoreFaults? faults,
  }) {
    final testClock = clock ?? TestClock();
    final storeFaults = faults ?? FakeNoteStoreFaults();
    final store = createFakeNoteStore(
      clock: testClock.clock,
      storageInfo:
          storageInfo ?? const StorageInfo(backend: StorageBackend.nativeFile),
      faults: storeFaults,
    );
    return FakeLibraryBackend._(testClock, store, storeFaults);
  }

  FakeLibraryBackend._(this.clock, this.store, this.faults) {
    library = RecordingLibraryRepository._(this, store.library);
    trash = RecordingTrashRepository._(this, store.trash);
  }

  /// Over a store opened by [open] with this backend's clock (L21, real CORE):
  ///   FakeLibraryBackend.overStore((c) => openTestNoteStore(clock: c, ...))
  /// The opener is a parameter so this file stays web-safe. faults == null on
  /// this path (CORE commit-fault injection exists only in the fake store). In
  /// testWidgets call it inside tester.runAsync (11절).
  static Future<FakeLibraryBackend> overStore(
    Future<NoteStore> Function(Clock clock) open, {
    TestClock? clock,
  }) async {
    final testClock = clock ?? TestClock();
    final store = await open(testClock.clock);
    return FakeLibraryBackend._(testClock, store, null);
  }

  final TestClock clock;

  /// CORE commit faults (failNextCommits / commitDelay). Non-null only over
  /// the fake store; scenarios that use it are
  /// LibraryScenario(needsFaults: true) and L21 skips them.
  final FakeNoteStoreFaults? faults;
  final NoteStore store;

  /// Wrapper that delegates to store.library (log + injection).
  late final RecordingLibraryRepository library;

  /// Wrapper that delegates to store.trash (log + injection).
  late final RecordingTrashRepository trash;

  // Injection (applies to the wrappers only, never to CORE internals)

  /// Thrown ONCE by the next mutating call, before delegating.
  Object? failNextMutation;

  /// Awaited before delegating every mutating call (zero = no wait at all).
  Duration latency = Duration.zero;

  /// One entry per mutating call (format in the class comment). Includes
  /// `'markOpened <id>'` if anything ever calls it (S-5 asserts it never
  /// appears).
  final List<String> calls = [];

  /// One entry per read call of the wrappers (format in the class comment).
  final List<String> queries = [];

  /// [noteStoreProvider.overrideWithValue(store),
  ///  libraryRepositoryProvider.overrideWithValue(library),
  ///  trashRepositoryProvider.overrideWithValue(trash)].
  /// Every other CORE provider (folderTreeProvider, clockProvider,
  /// storageInfoProvider, persistenceStatusProvider, thumbnails, settings,
  /// ...) derives from these (CORE 4.9).
  List<Override> get overrides => [
    noteStoreProvider.overrideWithValue(store),
    libraryRepositoryProvider.overrideWithValue(library),
    trashRepositoryProvider.overrideWithValue(trash),
  ];

  // Seeding through the real CORE API (results are CORE values). Seeding
  // bypasses the wrappers: nothing is logged and nothing is injected.

  /// Sets clock.current = [at] first, if given.
  Future<Folder> seedFolder(
    String name, {
    FolderId? parentId,
    int? colorArgb,
    String? icon,
    DateTime? at,
  }) {
    if (at != null) clock.current = at;
    return store.library.createFolder(
      parentId: parentId,
      name: name,
      colorArgb: colorArgb,
      icon: icon,
    );
  }

  /// Sets clock.current = [at] first, if given. [favorite] is applied with
  /// setFavorite after creation; the returned note is read back.
  Future<Note> seedNote(
    String title, {
    FolderId? folderId,
    NoteCover cover = const FirstPageCover(),
    bool favorite = false,
    DateTime? at,
    List<PageDraft> pages = const [PageDraft.blankA4],
  }) async {
    if (at != null) clock.current = at;
    final note = await store.library.createNote(
      folderId: folderId,
      title: title,
      pages: pages,
      cover: cover,
    );
    if (!favorite) return note;
    await store.library.setFavorite([note.id], true);
    return (await store.library.getNote(note.id))!;
  }

  /// Recent list entry the real way: store.openSession(id) then close()
  /// (N-6), then store.flush() so lastOpenedAt is committed. Sets
  /// clock.current = [at] first, if given.
  Future<void> seedOpened(NoteId id, {DateTime? at}) async {
    if (at != null) clock.current = at;
    final session = await store.openSession(id);
    await session.close();
    await store.flush();
  }

  /// Trash at a past time (clock moved to [at], then back).
  Future<void> seedTrashed(
    List<LibraryItemRef> items, {
    required DateTime at,
  }) async {
    final before = clock.current;
    clock.current = at;
    try {
      await store.library.trashItems(items);
    } finally {
      clock.current = before;
    }
  }

  /// "Another device" change: calls store.library / store.trash directly
  /// (bypassing the wrappers' log and injection) — LIBRARY sees it only
  /// through CORE streams. On the fake this commits with
  /// ChangeBatch(origin: local) (no remote path); the cover scheduler's remote
  /// handling is unit-tested with an injected changes stream (L11).
  Future<void> remoteChange(Future<void> Function(NoteStore store) change) =>
      change(store);

  /// store.close(). Real drift store in testWidgets:
  /// await tester.runAsync(backend.dispose).
  Future<void> dispose() => store.close();

  // ---- wrapper plumbing ----------------------------------------------------

  Future<T> _mutate<T>(String entry, Future<T> Function() delegate) async {
    calls.add(entry);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final failure = failNextMutation;
    if (failure != null) {
      failNextMutation = null;
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
    return delegate();
  }
}

String _ref(LibraryItemRef ref) => switch (ref) {
  FolderRef(:final id) => 'f:$id',
  NoteRef(:final id) => 'n:$id',
};

String _refs(List<LibraryItemRef> refs) => '[${refs.map(_ref).join(', ')}]';

String _target(FolderId? id) => id == null ? 'home' : 'f:$id';

String _argb(int argb) =>
    '0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _cover(NoteCover cover) => switch (cover) {
  FirstPageCover() => 'firstPage',
  ColorCover(:final colorArgb) => 'color:${_argb(colorArgb)}',
  AssetCover(:final assetId) => 'asset:$assetId',
};

String _anchors(LibraryItemRef? after, LibraryItemRef? before) => [
  if (after != null) ' after:${_ref(after)}',
  if (before != null) ' before:${_ref(before)}',
].join();

/// [FakeLibraryBackend.library]: delegates to store.library, logging every
/// call and applying the backend's injection to mutating calls.
final class RecordingLibraryRepository implements LibraryRepository {
  RecordingLibraryRepository._(this._backend, this._inner);

  final FakeLibraryBackend _backend;
  final LibraryRepository _inner;

  List<String> get _queries => _backend.queries;

  // Queries

  @override
  Stream<FolderTree> watchFolderTree() {
    _queries.add('watchFolderTree');
    return _inner.watchFolderTree();
  }

  @override
  Stream<LibraryListing> watchListing(LibraryQuery query) {
    _queries.add('watchListing $query');
    return _inner.watchListing(query);
  }

  @override
  Stream<Note?> watchNote(NoteId id) {
    _queries.add('watchNote $id');
    return _inner.watchNote(id);
  }

  @override
  Future<Note?> getNote(NoteId id) {
    _queries.add('getNote $id');
    return _inner.getNote(id);
  }

  @override
  Future<Folder?> getFolder(FolderId id) {
    _queries.add('getFolder $id');
    return _inner.getFolder(id);
  }

  @override
  Stream<List<Note>> watchRecentNotes({int limit = 20}) {
    _queries.add('watchRecentNotes limit:$limit');
    return _inner.watchRecentNotes(limit: limit);
  }

  @override
  Stream<List<Note>> watchFavoriteNotes() {
    _queries.add('watchFavoriteNotes');
    return _inner.watchFavoriteNotes();
  }

  @override
  Future<LibrarySearchResult> searchLibrary(String query, {int limit = 50}) {
    _queries.add("searchLibrary '$query' limit:$limit");
    return _inner.searchLibrary(query, limit: limit);
  }

  // Folders

  @override
  Future<Folder> createFolder({
    FolderId? parentId,
    required String name,
    int? colorArgb,
    String? icon,
  }) => _backend._mutate(
    "createFolder ${_target(parentId)} '$name'"
    '${colorArgb == null ? '' : ' color:${_argb(colorArgb)}'}'
    '${icon == null ? '' : ' icon:$icon'}',
    () => _inner.createFolder(
      parentId: parentId,
      name: name,
      colorArgb: colorArgb,
      icon: icon,
    ),
  );

  @override
  Future<void> renameFolder(FolderId id, String name) => _backend._mutate(
    "renameFolder f:$id '$name'",
    () => _inner.renameFolder(id, name),
  );

  @override
  Future<void> setFolderAppearance(
    FolderId id, {
    int? colorArgb,
    String? icon,
    bool clearColor = false,
    bool clearIcon = false,
  }) => _backend._mutate(
    'setFolderAppearance f:$id'
    '${colorArgb == null ? '' : ' color:${_argb(colorArgb)}'}'
    '${icon == null ? '' : ' icon:$icon'}'
    '${clearColor ? ' clearColor' : ''}'
    '${clearIcon ? ' clearIcon' : ''}',
    () => _inner.setFolderAppearance(
      id,
      colorArgb: colorArgb,
      icon: icon,
      clearColor: clearColor,
      clearIcon: clearIcon,
    ),
  );

  // Notes

  @override
  Future<Note> createNote({
    FolderId? folderId,
    required String title,
    List<PageDraft> pages = const [PageDraft.blankA4],
    NoteCover cover = const FirstPageCover(),
  }) => _backend._mutate(
    "createNote ${_target(folderId)} '$title' pages:${pages.length} "
    'cover:${_cover(cover)}',
    () => _inner.createNote(
      folderId: folderId,
      title: title,
      pages: pages,
      cover: cover,
    ),
  );

  @override
  Future<void> renameNote(NoteId id, String title) => _backend._mutate(
    "renameNote n:$id '$title'",
    () => _inner.renameNote(id, title),
  );

  @override
  Future<void> setFavorite(List<NoteId> ids, bool favorite) => _backend._mutate(
    'setFavorite [${ids.map((id) => 'n:$id').join(', ')}] $favorite',
    () => _inner.setFavorite(ids, favorite),
  );

  @override
  Future<void> setCover(NoteId id, NoteCover cover) => _backend._mutate(
    'setCover n:$id ${_cover(cover)}',
    () => _inner.setCover(id, cover),
  );

  @override
  Future<void> setTags(NoteId id, List<String> tags) => _backend._mutate(
    'setTags n:$id [${tags.join(', ')}]',
    () => _inner.setTags(id, tags),
  );

  @override
  Future<void> markOpened(NoteId id) =>
      _backend._mutate('markOpened $id', () => _inner.markOpened(id));

  // Mixed (multi-select)

  @override
  Future<void> moveItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
  }) => _backend._mutate(
    'moveItems ${_refs(items)} -> ${_target(targetFolderId)}',
    () => _inner.moveItems(items, targetFolderId: targetFolderId),
  );

  @override
  Future<void> reorderItem(
    LibraryItemRef item, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) => _backend._mutate(
    'reorderItem ${_ref(item)}${_anchors(after, before)}',
    () => _inner.reorderItem(item, after: after, before: before),
  );

  @override
  Future<void> reorderItems(
    List<LibraryItemRef> items, {
    LibraryItemRef? after,
    LibraryItemRef? before,
  }) => _backend._mutate(
    'reorderItems ${_refs(items)}${_anchors(after, before)}',
    () => _inner.reorderItems(items, after: after, before: before),
  );

  @override
  Future<List<LibraryItemRef>> copyItems(
    List<LibraryItemRef> items, {
    required FolderId? targetFolderId,
    String nameSuffix = '',
  }) => _backend._mutate(
    'copyItems ${_refs(items)} -> ${_target(targetFolderId)} '
    "suffix:'$nameSuffix'",
    () => _inner.copyItems(
      items,
      targetFolderId: targetFolderId,
      nameSuffix: nameSuffix,
    ),
  );

  @override
  Future<void> trashItems(List<LibraryItemRef> items) => _backend._mutate(
    'trashItems ${_refs(items)}',
    () => _inner.trashItems(items),
  );
}

/// [FakeLibraryBackend.trash]: delegates to store.trash, logging every call
/// and applying the backend's injection to mutating calls.
final class RecordingTrashRepository implements TrashRepository {
  RecordingTrashRepository._(this._backend, this._inner);

  final FakeLibraryBackend _backend;
  final TrashRepository _inner;

  @override
  Stream<List<TrashItem>> watchTrash() {
    _backend.queries.add('watchTrash');
    return _inner.watchTrash();
  }

  @override
  Future<void> restore(List<LibraryItemRef> items) =>
      _backend._mutate('restore ${_refs(items)}', () => _inner.restore(items));

  @override
  Future<void> purge(List<LibraryItemRef> items) =>
      _backend._mutate('purge ${_refs(items)}', () => _inner.purge(items));

  @override
  Future<void> emptyTrash() =>
      _backend._mutate('emptyTrash', _inner.emptyTrash);

  @override
  Future<int> purgeExpired() =>
      _backend._mutate('purgeExpired', _inner.purgeExpired);
}
