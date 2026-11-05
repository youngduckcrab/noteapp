// CORE T18 — the usage examples of README.md, compiled and run (VM). Each body is
// the README code block with the values it assumes supplied around it.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:note_core/testing_vm.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('app shell: open, classify the failure, flush, close', () async {
    final baseUri = Uri.parse('https://example.test/app/');
    final shown = NoteStoreConfig(
      // Web: absolute URLs resolved against document.baseURI (01-infra 6.4).
      web: WebStorageConfig(
        sqlite3WasmPath: baseUri.resolve('sqlite3.wasm').toString(),
        driftWorkerPath: baseUri.resolve('drift_worker.js').toString(),
      ),
    );
    expect(shown.web.sqlite3WasmPath, 'https://example.test/app/sqlite3.wasm');
    // Off the web a path or inMemory is needed: the same code paths in the VM.
    await expectLater(
      openNoteStore(shown),
      throwsA(
        isA<NoteStoreOpenException>().having(
          (e) => e.reason,
          'reason',
          NoteStoreOpenFailure.storageUnavailable,
        ),
      ),
    );
    const config = NoteStoreConfig(inMemory: true);
    final NoteStore store;
    try {
      store = await openNoteStore(config);
    } on NoteStoreOpenException {
      rethrow;
    }
    final container = ProviderContainer.test(
      overrides: [noteStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    expect(container.read(storageInfoProvider), store.storageInfo);
    await store.refreshStorageInfo();
    container.invalidate(storageInfoProvider);
    expect(
      storageWarningOf(
        container.read(storageInfoProvider),
        store.persistenceStatus,
      ),
      StorageWarning.notDurable,
    );
    await store.flush();
    await store.close();
    await deleteLocalNoteData(config);
  });

  for (final (name, open) in [
    ('fake', () async => createFakeNoteStore()),
    ('SQLite', openTestNoteStore),
  ]) {
    test('editor session ($name store)', () async {
      final store = await open();
      addTearDown(store.close);
      final noteId = (await store.library.createNote(title: 'n')).id;

      final session = await store.openSession(noteId);
      final page = session.pages.first;
      await session.openPage(page.id);
      final stroke = StrokeFixtures.synthetic(pageId: page.id, ids: store.ids);
      session.execute(AddStrokes(pageId: page.id, strokes: [stroke]));
      final inserted = await session.executeAsync(
        InsertPages(
          drafts: const [PageDraft.blankA4],
          position: PageAfter(page.id),
        ),
      );
      final newPageId = inserted.edit.insertedPageIds.single;
      expect(session.pages.map((p) => p.id), contains(newPageId));
      final undone = await session.undo();
      expect(undone.applied, isTrue);
      expect(session.pages.map((p) => p.id), isNot(contains(newPageId)));
      expect(session.pageIfLoaded(page.id)!.strokeCount, 1);
      session.closePage(page.id);
      await session.close();
    });

    test('PDF import ($name store)', () async {
      final store = await open();
      addTearDown(store.close);
      final pdfBytes = Uint8List.fromList('%PDF-1.7 test'.codeUnits);
      final pageSizes = [PageSize.a4Portrait, PageSize.letterPortrait];

      final asset = await store.assets.put(
        pdfBytes,
        type: AssetType.pdf,
        mimeType: 'application/pdf',
        fileName: 'lecture.pdf',
      );
      final note = await store.library.createNote(
        title: 'lecture',
        pages: [
          for (var i = 0; i < pageSizes.length; i++)
            PageDraft(
              size: pageSizes[i],
              background: PdfBackground(assetId: asset.id, pdfPageIndex: i),
            ),
        ],
      );
      final pages = await store.content.pagesOf(note.id);
      expect(
        [for (final p in pages) p.background],
        [
          PdfBackground(assetId: asset.id, pdfPageIndex: 0),
          PdfBackground(assetId: asset.id, pdfPageIndex: 1),
        ],
      );
      expect(await store.assets.readBytes(asset.id), pdfBytes);
    });
  }

  test('sync window (SQLite store)', () async {
    final store = await openTestNoteStore(seedDefaultPenPresets: false);
    addTearDown(store.close);
    await store.library.createNote(title: 'local');
    final remote = Folder(
      id: '01890000-0000-7000-8000-000000000001',
      ownerId: kLocalOwnerId,
      name: 'remote',
      sortKey: 'a0',
      createdAt: 1,
      updatedAt: 1,
      version: Hlc(
        store.clock.now().millisecondsSinceEpoch + 1000,
        0,
        '00000000000000ff',
      ),
    );
    final remoteChanges = [
      RemoteUpsert(remote, EntityFieldVersions(remote.version!)),
    ];
    const mergePolicy = newerVersionWinsPolicy;
    const cursorText = 'cursor-1';

    final pending = await store.sync.pendingChanges();
    final snapshots = await store.sync.readVersioned([
      for (final e in pending) e.ref,
    ]);
    expect(snapshots, hasLength(pending.length));
    await store.sync.acknowledge([for (final e in pending) e.ack]);
    final report = await store.sync.applyRemote(
      remoteChanges,
      policy: mergePolicy,
      metaUpdates: {'sync.cursor.notes': cursorText},
    );

    expect(report.taken, 1);
    expect(await store.sync.pendingChanges(), isEmpty);
    expect(await store.sync.readMeta('sync.cursor.notes'), cursorText);
    expect((await store.library.getFolder(remote.id))!.name, 'remote');
  });
}
