// Shared body of the CORE provider tests (6.16, 7.2.14): run on the fake store
// (test/providers/providers_fake_test.dart, T5) and on the SQLite store
// (test/providers/providers_real_test.dart, T17). Web-safe (no dart:io).
import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

/// Riverpod 3 pauses providers without listeners, so reads of stream-backed values
/// keep a listener while waiting.
Future<T> readWhileListening<T>(
  ProviderContainer container,
  ProviderListenable<Future<T>> provider,
) async {
  final sub = container.listen(provider, (_, _) {});
  try {
    return await sub.read();
  } finally {
    sub.close();
  }
}

/// The provider cases every store must pass; [open] returns a newly opened store
/// with the default pen presets.
void defineProviderContractTests(Future<NoteStore> Function() open) {
  late NoteStore store;
  late ProviderContainer container;

  Future<T> readAsync<T>(ProviderListenable<Future<T>> provider) =>
      readWhileListening(container, provider);

  setUp(() async {
    store = await open();
    container = ProviderContainer.test(
      overrides: [noteStoreProvider.overrideWithValue(store)],
    );
  });

  tearDown(() async {
    container.dispose();
    await store.close();
  });

  test('noteStoreProvider must be overridden', () {
    final bare = ProviderContainer.test();
    expect(() => bare.read(noteStoreProvider), throwsA(anything));
  });

  test('services come from the store', () {
    expect(container.read(libraryRepositoryProvider), same(store.library));
    expect(container.read(trashRepositoryProvider), same(store.trash));
    expect(container.read(penPresetRepositoryProvider), same(store.penPresets));
    expect(container.read(settingsRepositoryProvider), same(store.settings));
    expect(container.read(noteContentReaderProvider), same(store.content));
    expect(container.read(assetStoreProvider), same(store.assets));
    expect(container.read(thumbnailCacheProvider), same(store.thumbnails));
    expect(container.read(syncStoreProvider), same(store.sync));
    expect(container.read(idGeneratorProvider), same(store.ids));
    expect(container.read(clockProvider), same(store.clock));
    expect(container.read(storageInfoProvider), store.storageInfo);
    expect(container.read(pageThumbnailRendererProvider), isNull);
    expect(container.read(remoteAssetFetcherProvider), isNull);
  });

  test('syncBadgeProvider defaults to off', () async {
    expect(await readAsync(syncBadgeProvider.future), SyncBadge.off);
  });

  test(
    'persistenceStatusProvider: first value arrives without any write',
    () async {
      final value = await readAsync(persistenceStatusProvider.future);
      expect(value.pendingOps, 0);
      expect(
        container.read(persistenceStatusProvider),
        isA<AsyncData<PersistenceStatus>>(),
      );
    },
  );

  test('library listing refreshes after a commit', () async {
    final values = <List<String>>[];
    container.listen(libraryListingProvider(const LibraryQuery()), (_, next) {
      if (next case AsyncData(:final value)) {
        values.add([for (final n in value.notes) n.title]);
      }
    }, fireImmediately: true);
    await pumpEventQueue();
    await store.library.createNote(title: 'n1');
    await pumpEventQueue();
    expect(values.first, isEmpty);
    expect(values.last, ['n1']);
    final tree = await readAsync(folderTreeProvider.future);
    expect(tree.length, 0);
    expect(await readAsync(penPresetsProvider.future), hasLength(5));
    // The fake keeps no outbox (0); the SQLite store counts its entries.
    expect(
      await readAsync(syncPendingCountProvider.future),
      (await store.sync.pendingChanges()).length,
    );
  });

  test('noteSessionProvider closes the session when disposed', () async {
    final note = await store.library.createNote(title: 'n');
    final sub = container.listen(noteSessionProvider(note.id), (_, _) {});
    final session = await readAsync(noteSessionProvider(note.id).future);
    expect(session.isClosed, isFalse);
    expect(await readAsync(notePagesProvider(note.id).future), session.pages);
    expect(
      await readAsync(historyStateProvider(note.id).future),
      HistoryState.empty,
    );
    sub.close();
    await container.pump();
    await pumpEventQueue();
    expect(session.isClosed, isTrue);
  });

  test('pageContentProvider pins the page and unpins it on dispose', () async {
    final note = await store.library.createNote(title: 'n');
    final sessionSub = container.listen(
      noteSessionProvider(note.id),
      (_, _) {},
    );
    final session = await readAsync(noteSessionProvider(note.id).future);
    final pageId = session.pages.single.id;
    final key = (noteId: note.id, pageId: pageId);
    final contents = <PageContent>[];
    final sub = container.listen(pageContentProvider(key), (_, next) {
      if (next case AsyncData(:final value)) contents.add(value);
    });
    await pumpEventQueue();
    expect(contents, hasLength(1));
    expect(session.pageIfLoaded(pageId), isNotNull);
    session.execute(
      AddStrokes(
        pageId: pageId,
        strokes: [StrokeFixtures.synthetic(pageId: pageId, ids: store.ids)],
      ),
    );
    await pumpEventQueue();
    expect(contents.last.strokeCount, 1);
    sub.close();
    await container.pump();
    await pumpEventQueue();
    // Unpinned: with a cache of 0 pages it is evicted by the next close.
    final probe = await session.openPage(pageId);
    session.closePage(pageId);
    expect(probe.strokeCount, 1);
    sessionSub.close();
  });

  test('pageThumbnailProvider re-reads after ThumbnailCache.updates', () async {
    final note = await store.library.createNote(title: 'n');
    final page = (await store.content.pagesOf(note.id)).single;
    final values = <PageThumbnail?>[];
    container.listen(pageThumbnailProvider(page.id), (_, next) {
      if (next case AsyncData(:final value)) values.add(value);
    }, fireImmediately: true);
    await pumpEventQueue();
    expect(values, [null]);
    await store.thumbnails.write(
      PageThumbnail(
        pageId: page.id,
        contentRevision: 0,
        width: 1,
        height: 1,
        mimeType: 'image/png',
        bytes: Uint8List(1),
      ),
    );
    await pumpEventQueue();
    expect(values.last, isNotNull);
  });

  test('recent / favorites / search / trash providers', () async {
    final note = await store.library.createNote(title: '강의');
    await store.library.setFavorite([note.id], true);
    expect(await readAsync(favoriteNotesProvider.future), hasLength(1));
    expect(
      (await readAsync(librarySearchProvider('강').future)).notes,
      hasLength(1),
    );
    expect(await readAsync(recentNotesProvider.future), isEmpty);
    expect(await readAsync(trashItemsProvider.future), isEmpty);
    expect((await readAsync(noteProvider(note.id).future))!.title, '강의');
    expect(
      await readAsync(settingsSnapshotProvider.future),
      isA<SettingsSnapshot>(),
    );
    unawaited(Future<void>.value());
    expect(const Clock(), isNotNull);
  });

  // ---- v2 (m5-7/02-core 4.10, 6.8.2, 6.16 — B2-α: values; behaviour of the store members
  // follows 8.1 'B2 상태') ---------------------------------------------------------------

  test('v2: repositories and the index come from the store', () async {
    expect(container.read(recordingRepositoryProvider), same(store.recordings));
    expect(
      container.read(handwritingRepositoryProvider),
      same(store.handwriting),
    );
    expect(container.read(searchIndexProvider), same(store.search));
    final note = await store.library.createNote(title: 'r');
    expect(await readAsync(noteRecordingsProvider(note.id).future), isEmpty);
  });

  // ---- v2 behaviour on the store (CORE T36 — m5-7/02-core 6.16) -------------------------

  test('v2: noteRecordingsProvider follows the note\'s recording commits '
      '(startedAt order, no value for other notes) and is disposed with its '
      'last listener', () async {
    final note = await store.library.createNote(title: '녹음');
    final other = await store.library.createNote(title: '다른');
    final audio = await store.assets.put(
      Uint8List.fromList(List.filled(32, 3)),
      type: AssetType.audio,
      mimeType: 'audio/mp4',
    );
    Future<RecordingId> record(
      NoteId noteId,
      int startedAt, [
      String? title,
    ]) async => (await store.recordings.createRecording(
      id: store.ids.newId(),
      noteId: noteId,
      assetId: audio.id,
      durationMs: 1000,
      startedAt: startedAt,
      title: title,
    )).id;

    final provider = noteRecordingsProvider(note.id);
    final values = <List<String?>>[];
    final sub = container.listen(provider, (_, next) {
      if (next case AsyncData(:final value)) {
        values.add([for (final r in value) r.title]);
      }
    }, fireImmediately: true);
    await pumpEventQueue();
    expect(values, [<String?>[]]);

    final first = await record(note.id, 20, '첫 녹음');
    await pumpEventQueue();
    final second = await record(note.id, 10);
    await pumpEventQueue();
    await store.recordings.renameRecording(first, '바꾼 이름');
    await pumpEventQueue();
    await record(other.id, 5, '다른 노트');
    await pumpEventQueue();
    await store.recordings.deleteRecording(second);
    await pumpEventQueue();
    expect(values, [
      <String?>[],
      ['첫 녹음'],
      [null, '첫 녹음'],
      [null, '바꾼 이름'],
      ['바꾼 이름'],
    ]);

    expect(container.exists(provider), isTrue);
    sub.close();
    await container.pump();
    await pumpEventQueue();
    expect(container.exists(provider), isFalse, reason: 'autoDispose');
    // A new listener starts again from the current value.
    final again = await readAsync(provider.future);
    expect([for (final r in again) r.id], [first]);
    expect(
      [
        for (final r in await readAsync(
          noteRecordingsProvider(other.id).future,
        ))
          r.title,
      ],
      ['다른 노트'],
    );
  });

  test('v2: handwritingRepositoryProvider and searchIndexProvider read and '
      'write the store', () async {
    final note = await store.library.createNote(
      title: '공급자',
      pages: [
        PageDraft(
          size: PageSize.a4Portrait,
          background: const BlankBackground(),
          objects: [PageObjectFixtures.textBox(pageId: 'x', text: '공급자 상자')],
        ),
      ],
    );
    final page = (await store.content.pagesOf(note.id)).single.id;
    final handwriting = container.read(handwritingRepositoryProvider);
    await handwriting.put(
      HandwritingText(
        noteId: note.id,
        pageId: page,
        engineId: 'fake/1:ko',
        sourceRev: HandwritingText.sourceRevOf(const []),
        lines: const [
          HandwritingLine(
            text: '공급자 손글씨',
            rect: PageRect(10, 10, 200, 40),
            strokeIds: [],
            languageTag: 'ko',
          ),
        ],
        createdAt: 1,
      ),
    );
    expect(
      (await store.handwriting.forPage(page))!.lines.single.text,
      '공급자 손글씨',
    );
    expect(await handwriting.stalePages(note.id), isEmpty);
    // One result per page (its best unit): one query per source.
    final index = container.read(searchIndexProvider);
    for (final (q, source) in [
      ('공급자 상자', SearchSource.text),
      ('공급자 손글씨', SearchSource.ink),
    ]) {
      final hit = (await index.searchPages(q)).single;
      expect((hit.pageId, hit.source), (page, source), reason: q);
    }
  });

  test('v2: the store-derived providers follow a new noteStoreProvider value '
      '(6.16)', () async {
    final second = await open();
    addTearDown(second.close);
    container.updateOverrides([noteStoreProvider.overrideWithValue(second)]);
    expect(
      container.read(recordingRepositoryProvider),
      same(second.recordings),
    );
    expect(
      container.read(handwritingRepositoryProvider),
      same(second.handwriting),
    );
    expect(container.read(searchIndexProvider), same(second.search));
    final note = await second.library.createNote(title: '둘째 저장소');
    expect(await readAsync(noteRecordingsProvider(note.id).future), isEmpty);
  });

  test('v2: audio ports default to Unsupported* (6.8.2)', () async {
    final recorder = container.read(audioRecorderServiceProvider);
    final playback = container.read(audioPlaybackServiceProvider);
    expect(recorder, isA<UnsupportedAudioRecorder>());
    expect(playback, isA<UnsupportedAudioPlayback>());
    // Recorder: idle status once, unsupported, start throws, the rest does nothing.
    expect(recorder.status, const RecorderStatus());
    expect(recorder.status.phase, RecorderPhase.idle);
    expect(await recorder.statusStream.toList(), [const RecorderStatus()]);
    expect(await recorder.checkSupport(), AudioSupport.unsupported);
    expect(
      await recorder.checkSupport(requestPermission: true),
      AudioSupport.unsupported,
    );
    expect(
      recorder.start(recordingId: 'r1', noteId: 'n1'),
      throwsUnsupportedError,
    );
    await recorder.pause();
    await recorder.resume();
    await recorder.cancel();
    expect(await recorder.stop(), isNull);
    expect(await recorder.recoverDraft('d1'), isNull);
    expect(await recorder.pendingDrafts(), isEmpty);
    expect(recorder.offsetNowMs(), isNull);
    // Player: idle status once, open throws, the rest does nothing, position 0.
    expect(playback.status, const PlaybackStatus());
    expect(await playback.statusStream.toList(), [const PlaybackStatus()]);
    const recording = Recording(
      id: 'r1',
      noteId: 'n1',
      assetId: 'a',
      durationMs: 1000,
      startedAt: 0,
      createdAt: 0,
      updatedAt: 0,
    );
    expect(playback.open(recording), throwsUnsupportedError);
    await playback.play();
    await playback.pause();
    await playback.seekMs(500);
    await playback.setSpeed(2);
    expect(playback.positionMs(), 0);
    await playback.close();
    expect(playback.status, const PlaybackStatus());
  });
}
