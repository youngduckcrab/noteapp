// CORE T18 — the usage examples of README.md, compiled and run (VM). Each body is
// the README code block with the values it assumes supplied around it. (2차 T37 —
// m5-7/02-core 8.2) The 2nd-round examples — native storage, page objects, recordings and
// drafts, the PDF text index, search and handwriting results — run on the fake store and on
// the SQLite store (native storage: the real store only).
@TestOn('vm')
library;

import 'dart:io';
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

  test(
    'native storage: both paths → file database + file blobs (SQLite)',
    () async {
      final dir = await Directory.systemTemp.createTemp('note_core_readme_');
      addTearDown(() => dir.delete(recursive: true));
      final supportDir = dir.path;

      final config = NoteStoreConfig(
        // Android / iOS: both paths (app support directory). One alone →
        // storageUnavailable, like a directory that cannot be made or written.
        nativeDatabasePath: '$supportDir/noteapp.db',
        nativeAssetDirectoryPath: '$supportDir/assets', // made when missing
      );
      final store = await openNoteStore(config); // nativeFile, no banner
      expect(store.storageInfo.backend, StorageBackend.nativeFile);
      expect(
        storageWarningOf(store.storageInfo, store.persistenceStatus),
        isNull,
      );
      final asset = await store.assets.put(
        Uint8List.fromList([1, 2, 3]),
        type: AssetType.image,
        mimeType: 'image/png',
      );
      expect(await store.assets.readBytes(asset.id), [1, 2, 3]);
      expect(
        Directory('$supportDir/assets/blobs')
            .listSync(recursive: true)
            .whereType<File>(),
        isNotEmpty,
      );
      await store.close();
      await deleteLocalNoteData(config);
      expect(File('$supportDir/noteapp.db').existsSync(), isFalse);
      expect(Directory('$supportDir/assets/blobs').existsSync(), isFalse);
      expect(Directory('$supportDir/assets/thumbs').existsSync(), isFalse);

      await expectLater(
        openNoteStore(
          NoteStoreConfig(nativeDatabasePath: '$supportDir/noteapp.db'),
        ),
        throwsA(
          isA<NoteStoreOpenException>().having(
            (e) => e.reason,
            'reason',
            NoteStoreOpenFailure.storageUnavailable,
          ),
        ),
      );
    },
  );

  for (final (name, open) in [
    ('fake', () async => createFakeNoteStore()),
    ('SQLite', openTestNoteStore),
  ]) {
    test('page objects ($name store)', () async {
      final store = await open();
      addTearDown(store.close);
      final noteId = (await store.library.createNote(title: 'n')).id;
      final session = await store.openSession(noteId);
      final page = session.pages.first;
      await session.openPage(page.id);

      final box = TextBoxObject(
        id: store.ids.newId(),
        pageId: page.id,
        frame: const ElementFrame(PageRect(72, 72, 372, 112)),
        text: '회의 메모',
        style: const TextBoxStyle(),
        createdAt: store.clock.now().millisecondsSinceEpoch,
      );
      session.execute(AddObjects(pageId: page.id, objects: [box]));
      expect(
        [for (final o in session.pageIfLoaded(page.id)!.objects) o.id],
        [box.id],
      );
      session.execute(
        UpdateObjects(
          pageId: page.id,
          objects: [box.copyWith(text: '회의 메모 2')],
        ),
      );
      final edited = session.pageIfLoaded(page.id)!.objectById(box.id);
      expect((edited! as TextBoxObject).text, '회의 메모 2');
      await store.flush();
      expect(
        ((await store.content.loadPage(page.id)).objects.single
                as TextBoxObject)
            .text,
        '회의 메모 2',
      );
      session.execute(RemoveElements(pageId: page.id, elementIds: [box.id]));
      final objects = session.pageIfLoaded(page.id)!.objects;
      expect(objects, isEmpty);
      expect(
        () => session.execute(
          UpdateObjects(pageId: page.id, objects: [box]), // removed: missing id
        ),
        throwsArgumentError,
      );
      await session.close();

      final created = await store.library.createNote(
        title: 'with a box',
        pages: [
          PageDraft(
            size: PageSize.a4Portrait,
            background: const BlankBackground(),
            objects: [box],
          ),
        ],
      );
      final firstPage = (await store.content.pagesOf(created.id)).single;
      final copied = (await store.content.loadPage(firstPage.id)).objects;
      expect(copied.single.id, isNot(box.id));
      expect(copied.single.pageId, firstPage.id);
      expect(copied.single.createdAt, box.createdAt);
    });

    test('recordings and drafts ($name store)', () async {
      final store = await open();
      addTearDown(store.close);
      final noteId = (await store.library.createNote(title: 'n')).id;
      final startedAt = store.clock.now().millisecondsSinceEpoch;
      final chunk = Uint8List.fromList(List.filled(64, 7));

      final recordingId = store.ids.newId(); // chosen at record start
      final draft = await store.recordingDrafts.begin(
        recordingId: recordingId,
        noteId: noteId,
        mimeType: 'audio/webm',
        startedAt: startedAt,
      );
      await store.recordingDrafts.append(draft.draftId, chunk, activeMs: 1000);
      expect(
        (await store.recordingDrafts.listDrafts()).single.chunkCount,
        1,
        reason: 'what a restart would recover',
      );
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

      expect(await store.recordingDrafts.listDrafts(), isEmpty);
      expect(await store.recordings.recordingsOf(noteId), [recording]);
      expect(
        await store.recordings.createRecording(
          id: recordingId,
          noteId: noteId,
          assetId: audio.id,
          durationMs: 1000,
          startedAt: startedAt,
        ),
        recording,
      );
      expect(await store.recordings.audioBytesOf(noteId), chunk.length);
      await expectLater(
        store.recordingDrafts.begin(
          recordingId: store.ids.newId(),
          noteId: noteId,
          mimeType: 'audio/webm',
          startedAt: startedAt,
        ),
        completes,
      );
    });

    test('PDF text index and search ($name store)', () async {
      final store = await open();
      addTearDown(store.close);
      final asset = await store.assets.put(
        Uint8List.fromList('%PDF-1.7 test'.codeUnits),
        type: AssetType.pdf,
        mimeType: 'application/pdf',
      );
      final note = await store.library.createNote(
        title: 'lecture',
        pages: [
          for (var i = 0; i < 2; i++)
            PageDraft(
              size: PageSize.a4Portrait,
              background: PdfBackground(assetId: asset.id, pdfPageIndex: i),
            ),
        ],
      );
      final notePages = await store.content.pagesOf(note.id);
      const pageText = '푸리에 변환 Fourier transform';
      final glyphBoxes = [
        for (var i = 0; i < pageText.length; i++)
          PageRect(0.1 + i * 0.02, 0.1, 0.12 + i * 0.02, 0.12),
      ];
      const pdfWidth = 595.0, pdfHeight = 842.0;

      for (final (pdfPageIndex, body) in [(0, pageText), (1, '')]) {
        final ownerKey = '${asset.id}#$pdfPageIndex'; // one owner per PDF page
        final sourceRev = '${asset.id}:${SearchText.normalizerVersion}';
        if (await store.search.sourceRevOf(SearchSource.pdf, ownerKey) !=
            sourceRev) {
          await store.search.replaceUnits(SearchSource.pdf, ownerKey, [
            if (body.isNotEmpty) // page 1: a scanned page — no units
              SearchUnitDraft(
                body: body,
                rects: glyphBoxes,
                pdfPageAspect: pdfWidth / pdfHeight,
              ),
          ], sourceRev: sourceRev);
        }
      }
      expect(await store.search.sourceRevs(SearchSource.pdf), {
        '${asset.id}#0': '${asset.id}:${SearchText.normalizerVersion}',
        '${asset.id}#1': '${asset.id}:${SearchText.normalizerVersion}',
      });

      const query = '푸리에';
      final noteId = note.id;
      final result = await store.library.searchLibrary(query);
      expect(result.pages, hasLength(1));
      for (final hit in result.pages) {
        expect(hit.noteId, note.id);
        expect(hit.pageId, notePages.first.id);
        expect(hit.source, SearchSource.pdf);
        expect(
          hit.snippet.substring(hit.matchRange.$1, hit.matchRange.$2),
          query,
        );
        expect(hit.rects, isNotEmpty);
      }
      final more = result.pagesTruncated;
      expect(more, isFalse);
      final inNote = await store.search.searchPages(query, withinNote: noteId);
      expect(inNote, result.pages);

      await store.library.trashItems([NoteRef(note.id)]);
      expect((await store.library.searchLibrary(query)).pages, isEmpty);
    });

    test('handwriting results ($name store)', () async {
      final store = await open();
      addTearDown(store.close);
      final note = await store.library.createNote(title: 'ink');
      final session = await store.openSession(note.id);
      final page = session.pages.single;
      await session.openPage(page.id);
      final stroke = StrokeFixtures.synthetic(pageId: page.id, ids: store.ids);
      await session
          .execute(AddStrokes(pageId: page.id, strokes: [stroke]))
          .persisted;
      await session.close();
      const engineId = 'test-engine/1:ko';
      Future<List<HandwritingLine>> recognize(List<Stroke> input) async => [
        HandwritingLine(
          text: '안녕',
          rect: input.first.points.pointBounds,
          strokeIds: [for (final s in input) s.id],
        ),
      ];
      HandwritingText? mergeConfirmed(
        HandwritingText? current,
        HandwritingText fresh,
      ) => current?.sourceRev == fresh.sourceRev ? null : fresh;

      expect(await store.handwriting.notesWithStalePages(), [note.id]);
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

      expect(await store.handwriting.notesWithStalePages(), isEmpty);
      expect(await store.handwriting.stalePages(note.id), isEmpty);
      final stored = await store.handwriting.forPage(page.id);
      expect(stored!.lines.single.text, '안녕');
      final strokes = (await store.content.loadPage(page.id)).strokes;
      expect(strokes.single.id, stroke.id);
      expect(stored.sourceRev, HandwritingText.sourceRevOf(strokes));
      expect(
        (await store.library.searchLibrary('안녕')).pages.single.source,
        SearchSource.ink,
      );
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
