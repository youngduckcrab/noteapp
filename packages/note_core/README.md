# note_core

Owned by CORE: document model, local storage, undo, sync outbox. Plan:
[docs/plans/02-core.md](../../docs/plans/02-core.md), contract:
[00-overview.md 7장](../../docs/plans/00-overview.md) (7.2.2 ~ 7.2.14, 7.6 B2).
2nd round (M5 ~ M7: page objects, recordings, handwriting results, search
index, DB v2): plan [docs/plans/m5-7/02-core.md](../../docs/plans/m5-7/02-core.md),
contract [m5-7/00-overview.md 7장](../../docs/plans/m5-7/00-overview.md)
(7.2.2 ~ 7.2.8, 7.6).

Pure Dart, web safe. Entry points:

| Import | Use |
|---|---|
| `package:note_core/note_core.dart` | Everything public: data types, commands, `NoteSession`, repositories, `SyncStore`, `AssetStore`, providers |
| `package:note_core/dev_tools.dart` | `seedSyntheticNote` (developer menu); (2차) the v1 copy of the upgrade: `v1DatabaseCopyInfo`, `readV1DatabaseCopy`, `deleteV1DatabaseCopy` |
| `package:note_core/testing.dart` | `test/` only: `createFakeNoteStore`, `FakeNoteStoreFaults`, `StrokeFixtures`, `newerVersionWinsPolicy`, (2차) `PageObjectFixtures`, `FakeAudioRecorder`, `FakeAudioPlayback` |
| `package:note_core/testing_vm.dart` | VM `test/` only: `openTestNoteStore` (the SQLite store in memory or on a file) |
| `package:note_core/testing_web.dart` | (2차) `test/web/` only: `openWebTestNoteStore`, `deleteWebTestNoteStore` (the real web store under a test name) |

State: the whole of plan chapter 4 (1st and 2nd round) works on both stores;
a 1st-round database is upgraded to v2 on open, after a v1 copy (2nd-round
plan 6.12.4, `dev_tools.dart`). `openNoteStore` opens
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

## Native storage (INFRA J4, 2차)

```dart
final config = NoteStoreConfig(
  // Android / iOS: both paths (app support directory). One alone →
  // storageUnavailable, like a directory that cannot be made or written.
  nativeDatabasePath: '$supportDir/noteapp.db',
  nativeAssetDirectoryPath: '$supportDir/assets', // made when missing
);
final store = await openNoteStore(config); // nativeFile, no banner
// 'reset local data': await store.close(); await deleteLocalNoteData(config);
// removes the database, its v1 copy and <assets>/blobs, <assets>/thumbs.
```

## Page objects (EDITOR, X18)

```dart
final box = TextBoxObject(
  id: store.ids.newId(),
  pageId: page.id,
  frame: const ElementFrame(PageRect(72, 72, 372, 112)),
  text: '회의 메모',
  style: const TextBoxStyle(),
  createdAt: store.clock.now().millisecondsSinceEpoch,
);
session.execute(AddObjects(pageId: page.id, objects: [box])); // one undo step
session.execute(
  UpdateObjects(pageId: page.id, objects: [box.copyWith(text: '회의 메모 2')]),
); // only the changed JSON keys get a new field version (C-11)
session.execute(RemoveElements(pageId: page.id, elementIds: [box.id]));
final objects = session.pageIfLoaded(page.id)!.objects; // active, in order
```

- `UpdateObjects` replaces by id (same id, same type). An `UnknownObject` or a
  missing id throws `ArgumentError` before anything changes.
- `createNote(pages: [PageDraft(…, objects: […])])` writes objects with the
  note (new ids, the original `createdAt`), and
  `store.content.loadPage(pageId)` reads them without a session (PDF export).

## Recordings (media_io, X19 · X20)

```dart
final recordingId = store.ids.newId(); // chosen at record start (strokes link to it)
final draft = await store.recordingDrafts.begin(
  recordingId: recordingId,
  noteId: noteId,
  mimeType: 'audio/webm',
  startedAt: startedAt,
);
await store.recordingDrafts.append(draft.draftId, chunk, activeMs: 1000);
// … stop: the whole draft → one audio asset → then the recording row (M-1)
final audio = await store.assets.put(
  await store.recordingDrafts.readAll(draft.draftId),
  type: AssetType.audio,
  mimeType: 'audio/webm',
);
final recording = await store.recordings.createRecording(
  id: recordingId, // a retry with the same id returns the same row
  noteId: noteId,
  assetId: audio.id,
  durationMs: 1000,
  startedAt: startedAt,
);
await store.recordingDrafts.discard(draft.draftId);
```

- After a crash or a closed tab, `listDrafts()` returns the leftovers (a web
  draft whose row was not yet durable comes back from its meta).
- `append` completes when the chunk is durable; each chunk ≤ 4 MiB, an empty
  chunk only moves `activeMs`. A second `begin` for the same `recordingId`
  throws `StateError`.
- `renameRecording(id, title)`, `deleteRecording(id)` (soft — strokes keep
  their `recordingId`), `watchRecordings(noteId)` / `noteRecordingsProvider`,
  `audioBytesOf(noteId)`.

## PDF text index (PDF, X23)

```dart
final ownerKey = '${asset.id}#$pdfPageIndex'; // one owner per PDF page
final sourceRev = '${asset.id}:${SearchText.normalizerVersion}';
if (await store.search.sourceRevOf(SearchSource.pdf, ownerKey) != sourceRev) {
  await store.search.replaceUnits(
    SearchSource.pdf,
    ownerKey,
    [
      SearchUnitDraft(
        body: pageText,
        rects: glyphBoxes, // fractions of the PDF page, one per UTF-16 unit, or []
        pdfPageAspect: pdfWidth / pdfHeight,
      ),
    ],
    sourceRev: sourceRev,
  );
}
```

- An empty unit list still records the owner with its `sourceRev` (a scanned
  page). `sourceRevs(SearchSource.pdf)` answers every owner in one query for
  the start-up catch-up. Text boxes, math and handwriting are indexed by CORE
  itself.
- An index write failure never fails the source write (C-13): the owner is
  marked pending and retried on the next write transaction or store open.

## Search (LIBRARY, X21)

```dart
final result = await store.library.searchLibrary(query);
// result.folders / result.notes: titles (1st round); result.pages: content hits
for (final hit in result.pages) {
  // hit.noteId, hit.pageId, hit.source, hit.snippet, hit.matchRange,
  // hit.rects (note page pt — pdf boxes already fitted), best first
}
final more = result.pagesTruncated; // the limit or the 2,000-candidate cap cut it
final inNote = await store.search.searchPages(query, withinNote: noteId);
```

- Trashed notes and deleted pages are left out. A pdf hit appears on every
  live page that shows that PDF page.
- Rects: ink → the matched lines, text / math → the object bounds, pdf → for
  each query word the glyph boxes of its first match, merged per line and
  joined in query order (contract v2.6 C26-03 — a phrase is highlighted as a
  whole). The snippet and `matchRange` follow the first query word.
- `store.search.status` reports `rebuilding` and `pendingOwners`;
  `rebuild()` is idempotent. Providers: `searchIndexProvider`,
  `librarySearchProvider(query)`.

## Handwriting results (recognition, X22)

```dart
for (final noteId in await store.handwriting.notesWithStalePages()) {
  for (final pageId in await store.handwriting.stalePages(noteId)) {
    final input = [
      for (final s in (await store.content.loadPage(pageId)).strokes)
        if (HandwritingText.isRecognitionInput(s)) s,
    ];
    final fresh = HandwritingText(
      noteId: noteId,
      pageId: pageId,
      engineId: engineId,
      sourceRev: HandwritingText.sourceRevOf(input),
      lines: await recognize(input), // engine work, outside CORE
      createdAt: store.clock.now().millisecondsSinceEpoch,
    );
    await store.handwriting.update(
      pageId,
      // recog's merge rule (user-confirmed lines — 05-library 6.9.4); null = keep
      (current) => mergeConfirmed(current, fresh),
    );
  }
}
```

- `update` reads, merges and writes in ONE CORE write transaction, so a
  result that arrived meanwhile (sync, the conversion UI) is merged, not
  overwritten (G-4). `transform` is synchronous and pure; returning null
  leaves the stored value as it is.
- Input strokes are the page's active strokes with
  `HandwritingText.isRecognitionInput` (not highlighter / tape / laser).
  After `put` / `update` with the current `sourceRev`, `stalePages` no longer
  lists the page.

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
  from `dev_tools.dart` — (2차, CP-9) `objectsPerPage:` adds page objects to
  every page (per 17: 10 shapes of every kind, 5 text boxes, 1 math, 1 image of
  one 64 × 48 PNG asset; `objectsPerPage: 340` = INK's object page B14).
- (2차, plan m5-7/02-core 6.17) Both stores have the 2nd-round behaviour:
  page object commands, recordings, recording drafts, handwriting results
  (`update`, `stalePages`, `notesWithStalePages`) and the search index. The
  fake's memory index decides and orders like the real FTS index (CP-14 —
  the shared search cases run on both); text boxes, math and handwriting are
  indexed by the store, pdf goes through `store.search.replaceUnits`. The
  examples above run on both (`test/readme_examples_test.dart`).
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

2nd-round budgets (plan m5-7/02-core 6.19, `flutter test --run-skipped -t perf`).
Measured on 2026-11-06 (CORE T37) in the same shared container, load 4 ~ 13 —
the time budgets are judged at load < 4 (plan 9.1); a run at high load can
go over the small ones (PF-2, PF-3) and is measured again. PF-3 and PF-4 use
the V10 budget of contract v2.5 (C25-01 — change request CP-18, plan 12.1,
approved): a query with fewer than 100 candidates (FTS5 / LIKE rows before the
2,000 cap, counted by the test for every query) is held to 5 ms (1-syllable
LIKE: 15 ms), any other query to 50 ms. Frequent words read up to 2,000
candidates and take 20 ~ 46 ms:

| # | Test | Budget | Measured |
|---|---|---|---|
| PF-1 | `openPage`, 2,000 objects + 2,000 strokes (`object_page_perf_test`) | ≤ 400 ms | 196 ~ 227 ms |
| PF-2 | `execute(UpdateObjects 1)` on 2,000 objects | mean ≤ 2 ms | 0.64 ~ 0.88 ms (2.04 at load 13) |
| PF-3 | 5,000-page index: 2-, 3-syllable, word-middle, Latin prefix, AND queries (`search_perf_test`) | median: < 100 candidates ≤ 5 ms, others ≤ 50 ms (V10, v2.5) | 38 ~ 65 candidates 1.6 ~ 2.7 ms; 136 candidates / 100 pages 4.0 ~ 4.5 ms; frequent words, 2,500 ~ 5,000 candidates: 24 ~ 34 ms (load 2.6 ~ 4.3; 22 ~ 31 ms in 8 runs at load < 4, 24 ~ 46 ms at load 5 ~ 9) |
| PF-4 | same index, 1-syllable LIKE | median: < 100 candidates ≤ 15 ms, others ≤ 50 ms (V10, v2.5) | absent syllable (0 candidates — the whole LIKE scan) 7.4 ~ 8.3 ms; 576 / 1,072 / 4,995 candidates 14.0 ~ 14.2 / 20.9 ~ 21.4 / 21.8 ~ 24.8 ms (load 2.6 ~ 4.3; 20 ~ 27 ms at load 5 ~ 9) |
| PF-5 | 5,000 × `replaceUnits` (pdf) | record only | 5.7 ~ 7.3 s |
| PF-6 | `stalePages` 20 × 1,000 strokes: first / one page changed | ≤ 150 / ≤ 10 ms | 54 / 5.6 ms |
| PF-7 | draft `append` 8 KiB: test store / native file blobs | median ≤ 10 ms | 4.4 / 5.9 ms |
| PF-8 | V7 fixture v1 → v2 with the v1 copy (`migration_perf_test`) | ≤ 1 s | 68 ms (43 ms without the copy step) |
| PF-9 | 1st-round table above | unchanged | see above (this run: 45 / 95 / 0.86 / 11 / 71 / 17 ms) |
| PF-10 | 500 real-shape PDF pages (2,500 chars + glyph boxes each): DB growth Korean / mixed / English | ≤ 12 MB | 8.31 / 6.15 / 3.62 MiB (+ 5.35 MiB glyph box blobs outside SQLite) |
| PF-10 | same, query of 100 pages with rects (in-process store) | median ≤ 50 ms | 20 ~ 37 ms (55 at load 13) |
| PF-10 | mixed on the native store (`openNoteStore`, file blobs) | record only | 35 ms |
| PF-10w | Chrome reopen after the Korean 500-page index (`search_reopen_time_browser_test`) | ≤ +300 ms | +183 ms (218 → 401 ms) |
| PF-11 | 100,000-stroke library: first catch-up / then `notesWithStalePages` | ≤ 1.5 s / ≤ 30 ms | 553 / 1.2 ms |
| — | Chrome `openNoteStore`: empty / 10,000 strokes (`open_time_browser_test`) | record only | 865 ms / 433 ~ 510 ms |
