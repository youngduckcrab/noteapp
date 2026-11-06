# note_core

Owned by CORE: document model, local storage, undo, sync outbox. Plan:
[docs/plans/02-core.md](../../docs/plans/02-core.md), contract:
[00-overview.md 7장](../../docs/plans/00-overview.md) (7.2.2 ~ 7.2.14, 7.6 B2).

Pure Dart, web safe. Entry points:

| Import | Use |
|---|---|
| `package:note_core/note_core.dart` | Everything public: data types, commands, `NoteSession`, repositories, `SyncStore`, `AssetStore`, providers |
| `package:note_core/dev_tools.dart` | `seedSyntheticNote` (developer menu) |
| `package:note_core/testing.dart` | `test/` only: `createFakeNoteStore`, `FakeNoteStoreFaults`, `StrokeFixtures`, `newerVersionWinsPolicy`, (2차) `PageObjectFixtures`, `FakeAudioRecorder`, `FakeAudioPlayback` |
| `package:note_core/testing_vm.dart` | VM `test/` only: `openTestNoteStore` (the SQLite store in memory or on a file) |
| `package:note_core/testing_web.dart` | (2차) `test/web/` only: `openWebTestNoteStore`, `deleteWebTestNoteStore` (the real web store under a test name) |

State: the whole of plan chapter 4 works on both stores. `openNoteStore` opens
SQLite through drift (web: `WasmDatabase` in `drift_worker.js`; VM: a native
file or memory database), asset bytes and thumbnails live in IndexedDB on the
web. (2차 T35, plan m5-7/02-core 6.15.3) Off the web a durable store needs both
`nativeDatabasePath` and `nativeAssetDirectoryPath` (one alone, or a directory
that cannot be made or written → `storageUnavailable`): a WAL file database
plus file blobs under `<dir>/blobs` and `<dir>/thumbs`, which CORE makes when
missing; `deleteLocalNoteData` removes the database, its v1 copy and those two
directories. `openTestNoteStore(filePath:)` keeps the in-memory blobs.
`createFakeNoteStore()` has the same meaning in memory (no outbox, no remote
path — plan 6.19).

The examples below are also compiled and run by
`test/readme_examples_test.dart`.

## App shell (INFRA, X1)

```dart
final config = NoteStoreConfig(
  // Web: absolute URLs resolved against document.baseURI (01-infra 6.4).
  web: WebStorageConfig(
    sqlite3WasmPath: baseUri.resolve('sqlite3.wasm').toString(),
    driftWorkerPath: baseUri.resolve('drift_worker.js').toString(),
  ),
);
final NoteStore store;
try {
  store = await openNoteStore(config);
} on NoteStoreOpenException catch (e) {
  // e.reason: storageUnavailable / migrationFailed / corrupted / newerSchema /
  // unknown → start error screen. Its 'reset local data' button:
  //   await deleteLocalNoteData(config); then openNoteStore(config) again.
  rethrow;
}
// Root ProviderScope, once: noteStoreProvider.overrideWithValue(store).
// App hidden: await store.flush() (500 ms limit). Stop: await store.close().
```

- `openNoteStore` asks `navigator.storage.persist()` (waits at most 1 s) and
  `estimate()` while the database opens. `store.storageInfo` holds the
  result. After `await store.refreshStorageInfo()`, the caller runs
  `ref.invalidate(storageInfoProvider)` so other screens see the new value.
- Banner condition: `storageWarningOf(info, status)` → `writeFailing`
  (3 failed commits in a row), `notDurable` (memory storage) or `null`. The
  banner text belongs to LIBRARY / EDITOR (7.4.5).
- `deleteLocalNoteData(config)` throws `StateError` while a store of that
  database is open in this tab. On the web it throws `TimeoutException` after
  10 s when another tab keeps the database open.

## Editor session (EDITOR, X2 ~ X4)

```dart
final session = await store.openSession(noteId); // or noteSessionProvider(noteId)
final page = session.pages.first;
await session.openPage(page.id); // pins the page; closePage(page.id) unpins
session.execute(AddStrokes(pageId: page.id, strokes: [stroke])); // pen up
final inserted = await session.executeAsync(
  InsertPages(
    drafts: const [PageDraft.blankA4],
    position: PageAfter(page.id),
  ),
);
final newPageId = inserted.edit.insertedPageIds.single;
final undone = await session.undo(); // one step: the inserted page goes away
session.closePage(page.id);
await session.close(); // the last reference flushes and frees memory
```

- `execute` changes the memory state and fires `pageChanges` / `pagesStream` /
  `historyStream` listeners before it returns (N-1). The returned
  `CommandReceipt.persisted` completes after the DB commit.
- A trashed note, or a note written by a newer app, opens read only
  (`session.isReadOnly`). Then `execute`, `executeAsync`, `undo` and `redo`
  throw `ReadOnlyNoteException` (N-4).
- Remote changes to a loaded page come in as
  `PageContentChange(origin: remote)`. They are not added to the history (N-7).

## PDF import (PDF, X6)

```dart
final asset = await store.assets.put(
  pdfBytes,
  type: AssetType.pdf,
  mimeType: 'application/pdf',
  fileName: 'lecture.pdf',
);
final note = await store.library.createNote(
  title: 'lecture',
  pages: [
    for (var i = 0; i < pageSizes.length; i++) // ≤ 2000 pages
      PageDraft(
        size: pageSizes[i], // pt, already ratio-fitted to 72..14400
        background: PdfBackground(assetId: asset.id, pdfPageIndex: i),
      ),
  ],
);
```

- Write rule (4.5 head, 7.2.9): a repository `Future` completes after the
  commit. While a failed commit is retried it neither completes nor fails.
  Argument errors fail before anything is queued. `put` fails at once only
  when writing the byte chunks fails.
- Missing original: when `await store.assets.readBytes(id) == null`, call
  `ensureLocal(id)` on `remoteAssetFetcherProvider` (null before M4). Then try
  again when `store.assets.bytesArrived` emits that id.

## Sync window (SYNC, X7)

```dart
final pending = await store.sync.pendingChanges(); // seq order
final snapshots = await store.sync.readVersioned([
  for (final e in pending) e.ref,
]);
// ... upload snapshots ...
await store.sync.acknowledge([for (final e in pending) e.ack]);
final report = await store.sync.applyRemote(
  remoteChanges, // RemoteUpsert(entity, versions) / RemotePurge(ref)
  policy: mergePolicy, // pure function, runs inside the CORE transaction
  metaUpdates: {'sync.cursor.notes': cursorText}, // saved atomically with it
);
```

- `applyRemote` stores the received versions as they are. It writes nothing
  to the outbox except what `WriteMerged.fieldsToUpload` asks for, and
  `NoteStore.changes` emits `ChangeBatch(origin: remote)`. A policy exception
  rolls back everything, the meta included, and `applyRemote` rethrows it.
- `commitRepairs` (cycle repair, revived pages), `readMeta` / `writeMeta`
  (`sync.` keys, 256 KiB), `reassignOwner(from: 'local', to: uid)` and
  `duplicateNoteForRecovery(noteId, titleSuffix: ...)` complete the window
  (7.2.10).
- Device-local fields (`lastOpenedAt`, `pageCount`, `firstPageId`,
  `contentRevision`, `hasLocalBytes`) of entities passed in are never stored.
  CORE computes them.

## Tests in other areas

```dart
final store = createFakeNoteStore(); // sequential ids, system clock
final container = ProviderContainer.test(
  overrides: [noteStoreProvider.overrideWithValue(store)],
);
```

- Riverpod 3 pauses providers without listeners. Keep a listener
  (`container.listen(provider.future, (_, _) {})`) while you await a
  stream-backed provider.
- Failures: `createFakeNoteStore(faults: FakeNoteStoreFaults()..failNextCommits(3))`
  retries on the same schedule as the real write queue.
- Banner tests: `createFakeNoteStore(storageInfo: const StorageInfo(backend: StorageBackend.webInMemory))`.
- The fake's `SyncStore` has only `ownerId`, `deviceNodeId`, an empty
  `pendingChanges()` and `watchPendingCount()` = 0. All other members throw
  `UnsupportedError`, so sync tests use `openTestNoteStore()` (VM).
- `openTestNoteStore()` (VM, `integration` tag in other areas) is the real
  SQLite store with no timers. The outbox of a new database already holds the
  5 default pen presets, so tests that count outbox entries pass
  `seedDefaultPenPresets: false`. In memory it reports `nativeMemory`
  (`storageWarningOf` → `notDurable`); pass `storageInfo:` to report another
  backend.
- fake_async: SQLite writes finish on microtasks. Asset `put` and thumbnail
  writes on `openTestNoteStore` use the in-memory IndexedDB, which ends on
  0.1 ms timers, so advance time (e.g. `async.elapse(1 ms)` in a loop).
- Fixtures: `StrokeFixtures.synthetic(pageId:, ids:, seed:, pointCount:)`,
  `newerVersionWinsPolicy`, and `seedSyntheticNote(store, pages:, strokesPerPage:)`
  from `dev_tools.dart`.
- (2차, plan m5-7/02-core 6.17, 8.1 'B2 상태') The fake store already has the
  2nd-round behaviour: page object commands, recordings, recording drafts,
  handwriting results (`update`, `stalePages`, `notesWithStalePages`) and a
  memory search index that decides and orders like the real one (text boxes,
  math and handwriting are indexed by the store; pdf goes through
  `store.search.replaceUnits`). On the real store (`openTestNoteStore`) these
  come with the concurrent tasks: page object commands (sessions,
  `createNote` drafts, `store.content.loadPage(…).objects`) since CORE T27,
  recordings since T30, recording drafts (chunks and meta in the asset blob
  store) since T31; the handwriting / index writes throw
  `UnimplementedError('CORE T32: …')` / T33a until those tasks.
- `PageObjectFixtures.shape / textBox / image / math / unknown(pageId: …)`
  build valid objects with the contract defaults (`id` omitted → a unique
  `fx-<type>-<n>`).
- `FakeAudioRecorder(store: store)`: no timers; `advance(d)` moves its clock
  (one 16-byte draft chunk per recorded second, an empty keep-alive chunk per
  paused second), `stop()` stores the asset, then the recording. The
  'recently updated' window of `pendingDrafts()` (10 s) is measured on
  `store.clock`, so pass a controllable clock to `createFakeNoteStore(clock:)`.
  Status streams deliver asynchronously (await a microtask before checking).
- `FakeAudioPlayback()`: `setPositionMs`, `calls` (`'open:<id>'`, `'play'`,
  `'pause'`, `'seek:<ms>'`, `'speed:<x>'`, `'close'`).

## Testing note_core

```text
flutter test                                    # VM (perf skipped)
dart run tool/prepare_web_test.dart             # test/web/sqlite3.wasm, drift_worker.js
flutter test --platform chrome test/web         # browser (real WasmDatabase store)
flutter test --run-skipped -t perf              # performance budgets (plan 9.1)
```

V7 fixture (2차 T25a — plan m5-7/02-core 6.12.3): `test/fixtures/db_v1/` holds
a v1 database written by the 1st-round code (`noteapp_v1.sqlite` as the native
store left it, `noteapp_v1_web.sqlite` the same rows with the rollback journal
header for Chrome), the PDF asset bytes, `fixture_source.json` (source commit,
generator hash, entity ids) and `manifest.json` (row counts and canonical dump
hashes). Never open these files in place — tests copy them first.

(2차 T25b) `test/migration/v1_fixture_migration_test.dart` (VM: file database
+ file blobs) and `test/web/v1_fixture_migration_browser_test.dart` (Chrome:
the fixture as the initial bytes of a new web database) upgrade it and compare
with the manifest (`test/shared/v7_fixture_checks.dart`); PF-8 is
`test/perf/migration_perf_test.dart`. `tool/prepare_web_test.dart` copies the
Chrome files to `test/web/fixtures_v1/`.

```text
dart run tool/v1_fixture_manifest.dart --check  # manifest.json matches the files
dart run tool/make_v1_fixture.dart --out <dir> --source-commit <sha> --core-tree <sha>
                                                # generator: steps in its header
```

`tool/prepare_web_test.dart` copies `drift_worker.js` from the resolved
drift package and checks the sha256 of `sqlite3.wasm` (sqlite3 3.8.0). The
file comes from the cache (`.dart_tool/note_core_web_test/`), then from the
drift package, then from the release URL. `dart run tool/ws.dart test
--platform chrome` runs the script first.

Browser tests of another package that open the real web store
(`package:note_core/testing_web.dart` — `openWebTestNoteStore(name)` /
`deleteWebTestNoteStore(name)`, plan m5-7/02-core 4.9, 6.18.1) need the same
two files next to their test page. From that package's directory:

```text
dart run ../note_core/tool/prepare_web_test.dart --out test/web
```

(or resolve the note_core directory with
`Isolate.resolvePackageUri(Uri.parse('package:note_core/note_core.dart'))` in
the package's own `tool/prepare_web_test.dart`). The two files are build
artifacts: keep them out of git in that package.

Performance budgets (plan 9.1, VM, `test/perf/`). Measured on 2026-11-05 in a
4-CPU container shared with other test runs:

| Test | Budget | Measured |
|---|---|---|
| Seed a 100,000-stroke note (500 × 200 × 100 points) | record only | 45.9 s |
| `openSession` of that note | < 200 ms | 5.7 ms |
| `openPage` of a 2,000-stroke page | < 300 ms | 58 ms |
| `execute(AddStrokes 1)` on a 5,000-stroke page | mean < 2 ms | 0.37 ms |
| One stroke enqueue → commit (file DB) | median < 30 ms | 6.8 ms |
| Decode 1,000,000 points | < 300 ms | 60 ms |
| `watchListing` first value, 200 folders + 1,000 notes | < 100 ms | 17 ms |
| Chrome `openNoteStore`: empty / 10,000 strokes (`test/web/open_time_browser_test.dart`, DDC) | record only | 567 ms / 338 ~ 411 ms |
