// CoverThumbnailScheduler (05-library 6.15.3, 8 L11). fakeAsync over the CORE
// fake store; `changes` and `assetArrivals` are injected StreamControllers
// (the fake store has no remote path — 5.7), except the provider test at the
// end, which uses the store's own streams.
import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:fake_async/fake_async.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/thumbnails/cover_thumbnail_scheduler.dart';
import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import '../support/fake_library_backend.dart';
import '../support/fake_thumbnail_renderer.dart';
import '../support/recording_thumbnail_io.dart';

final String _assetA = 'a' * 64;
final String _assetB = 'b' * 64;

PageDraft _pdfPage(AssetId asset) => PageDraft(
  size: PageSize.a4Portrait,
  background: PdfBackground(assetId: asset, pdfPageIndex: 0),
);

/// One fakeAsync world: CORE fake store, recording reader / cache, fake
/// renderer, injected streams and the scheduler under test.
final class _Rig {
  _Rig(this.async, {bool withRenderer = true}) {
    backend = FakeLibraryBackend();
    reader = RecordingContentReader(backend.store.content);
    cache = RecordingThumbnailCache(backend.store.thumbnails);
    scheduler = CoverThumbnailScheduler(
      reader: reader,
      cache: cache,
      renderer: withRenderer ? renderer : null,
      assetArrivals: arrivals.stream,
      changes: changes.stream,
      report: (error, _) => reports.add(error),
    );
  }

  final FakeAsync async;
  late final FakeLibraryBackend backend;
  late final RecordingContentReader reader;
  late final RecordingThumbnailCache cache;
  final FakeThumbnailRenderer renderer = FakeThumbnailRenderer();
  final StreamController<ChangeBatch> changes = StreamController<ChangeBatch>();
  final StreamController<AssetId> arrivals = StreamController<AssetId>();
  final List<Object> reports = [];
  late final CoverThumbnailScheduler scheduler;
  final IdGenerator _strokeIds = SequentialIdGenerator(prefix: 'stroke');

  T run<T>(Future<T> future) {
    late T result;
    var done = false;
    future.then((v) {
      result = v;
      done = true;
    });
    async.flushMicrotasks();
    for (var i = 0; i < 20 && !done; i++) {
      async.elapse(Duration.zero);
    }
    expect(done, isTrue, reason: 'future did not complete');
    return result;
  }

  void elapse(int ms) => async.elapse(Duration(milliseconds: ms));

  /// Long enough for the start delay, every job and a remote round.
  void drain() => elapse(10000);

  Note note(
    String title, {
    List<PageDraft> pages = const [PageDraft.blankA4],
  }) => run(backend.seedNote(title, pages: pages));

  List<PageId> pageIds(Note note) => [
    for (final p in run(backend.store.content.pagesOf(note.id))) p.id,
  ];

  int revisionOf(PageId pageId) =>
      run(backend.store.content.getPage(pageId))!.contentRevision;

  PageThumbnail? cached(PageId pageId) =>
      run(backend.store.thumbnails.read(pageId));

  /// A real content change of [pageId] (contentRevision + 1) through a session
  /// — what a remote apply does to the page (C11-03). The scheduler is not
  /// told about the note's new updatedAt.
  void addStroke(Note note, PageId pageId) {
    run(() async {
      final session = await backend.store.openSession(note.id);
      await session.executeAsync(
        AddStrokes(
          pageId: pageId,
          strokes: [
            StrokeFixtures.synthetic(
              pageId: pageId,
              ids: _strokeIds,
              pointCount: 8,
            ),
          ],
        ),
      );
      await session.close();
      await backend.store.flush();
    }());
  }

  void batch(
    List<EntityChange> list, {
    ChangeOrigin origin = ChangeOrigin.remote,
  }) {
    changes.add(ChangeBatch(origin: origin, changes: list, committedAt: 0));
    async.flushMicrotasks();
  }

  EntityChange strokeOf(Note note, PageId pageId) => EntityChange(
    kind: EntityKind.stroke,
    id: 'stroke-x',
    noteId: note.id,
    pageId: pageId,
  );

  bool isIdle() {
    var done = false;
    scheduler.idle().then((_) => done = true);
    async.flushMicrotasks();
    return done;
  }

  void close() {
    scheduler.dispose();
    unawaited(changes.close());
    unawaited(arrivals.close());
    async.flushMicrotasks();
    run(backend.dispose());
  }
}

void _testRig(
  String description,
  void Function(_Rig r) body, {
  bool withRenderer = true,
}) {
  test(description, () {
    fakeAsync((async) {
      final r = _Rig(async, withRenderer: withRenderer);
      body(r);
      r.close();
    });
  });
}

void main() {
  group('queue', () {
    _testRig('nothing renders before the 800 ms start delay', (r) {
      final n = r.note('n');
      r.scheduler.request(n);
      expect(r.scheduler.pendingCount, 1);
      r.elapse(799);
      expect(r.renderer.rendered, isEmpty);
      expect(r.reader.log, isEmpty);
      r.elapse(1);
      expect(r.renderer.rendered, [n.firstPageId]);
      expect(r.cache.writes, ['write ${n.firstPageId} rev:0']);
      expect(r.cached(n.firstPageId!), isNotNull);
      expect(r.isIdle(), isTrue);
    });

    _testRig('the most recent request runs first (LIFO)', (r) {
      final a = r.note('a'), b = r.note('b'), c = r.note('c');
      r.scheduler
        ..request(a)
        ..request(b)
        ..request(c)
        ..request(a); // asked again → newest
      r.drain();
      expect(r.renderer.rendered, [
        a.firstPageId,
        c.firstPageId,
        b.firstPageId,
      ]);
    });

    _testRig('beyond 64 pending requests the oldest are dropped', (r) {
      final notes = [for (var i = 0; i < 70; i++) r.note('n$i')];
      notes.forEach(r.scheduler.request);
      expect(r.scheduler.pendingCount, 64);
      r.drain();
      expect(r.renderer.rendered, [
        for (final n in notes.reversed.take(64)) n.firstPageId,
      ]);
      expect(r.scheduler.pendingCount, 0);
    });

    _testRig('request is idempotent and the gap does not restart the delay', (
      r,
    ) {
      final a = r.note('a'), b = r.note('b');
      r.scheduler
        ..request(a)
        ..request(a);
      expect(r.scheduler.pendingCount, 1);
      r.elapse(800);
      expect(r.renderer.rendered, [a.firstPageId]);
      // Later requests start without the start delay.
      r.scheduler.request(b);
      r.elapse(0);
      expect(r.renderer.rendered, [a.firstPageId, b.firstPageId]);
    });

    _testRig('the first page is checked with one getPage — never pagesOf', (r) {
      final n = r.note('n');
      r.scheduler.request(n);
      r.drain();
      final p = n.firstPageId;
      expect(r.reader.log, ['getPage $p', 'loadPage $p']);
      expect(r.reader.log.where((e) => e.startsWith('pagesOf')), isEmpty);
    });

    _testRig('covers that are not FirstPageCover / no first page: ignored', (
      r,
    ) {
      final n = r.note('n');
      r.scheduler
        ..request(n.copyWith(cover: const ColorCover(0xFF2F4A7A)))
        ..request(n.copyWith(cover: AssetCover(_assetA)))
        ..request(n.copyWith(clearFirstPageId: true));
      expect(r.scheduler.pendingCount, 0);
      r.drain();
      expect(r.renderer.rendered, isEmpty);
      expect(r.reader.log, isEmpty);
    });

    _testRig('cancel drops a pending request', (r) {
      final a = r.note('a'), b = r.note('b');
      r.scheduler
        ..request(a)
        ..request(b)
        ..cancel(b.id);
      expect(r.scheduler.pendingCount, 1);
      r.drain();
      expect(r.renderer.rendered, [a.firstPageId]);
    });
  });

  group('freshness', () {
    _testRig('a fresh cached thumbnail is kept (PDF import cover)', (r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      // What PDF writes right after an import: the page's contentRevision.
      r.run(
        r.backend.store.thumbnails.write(
          PageThumbnail(
            pageId: p,
            contentRevision: r.revisionOf(p),
            width: 1,
            height: 1,
            mimeType: 'image/png',
            bytes: kTestPng1x1,
          ),
        ),
      );
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, isEmpty);
      expect(r.reader.log, ['getPage $p']);
      expect(r.cache.log, ['read $p']);
    });

    _testRig('a stale cached thumbnail is drawn again', (r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.run(
        r.backend.store.thumbnails.write(
          PageThumbnail(
            pageId: p,
            contentRevision: r.revisionOf(p),
            width: 1,
            height: 1,
            mimeType: 'image/png',
            bytes: kTestPng1x1,
          ),
        ),
      );
      r.addStroke(n, p);
      final revision = r.revisionOf(p);
      expect(revision, greaterThan(0));
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p]);
      expect(r.cached(p)!.contentRevision, revision);
    });

    _testRig('a failure is reported and the same key is not tried again', (r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.renderer.failFor = {p};
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p]);
      expect(r.reports, [isA<StateError>()]);
      expect(r.cache.writes, isEmpty);
      r.renderer.failFor = {};
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p]);
      // A new version of the note (local edit, C-9) is checked again.
      r.scheduler.request(n.copyWith(updatedAt: n.updatedAt + 1));
      r.drain();
      expect(r.renderer.rendered, [p, p]);
      expect(r.cache.writes, ['write $p rev:0']);
    });

    _testRig('null (cannot render now): no cache write, no retry for the key', (
      r,
    ) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.renderer.nullFor = {p};
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p]);
      expect(r.cache.writes, isEmpty);
      expect(r.cached(p), isNull);
      expect(r.reports, isEmpty);
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p]);
    });

    _testRig('same updatedAt but a new firstPageId (remote reorder) → retry', (
      r,
    ) {
      final n = r.note(
        'n',
        pages: const [PageDraft.blankA4, PageDraft.blankA4],
      );
      final [p1, p2] = r.pageIds(n);
      expect(n.firstPageId, p1);
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p1]);
      r.scheduler.request(n.copyWith(firstPageId: p2));
      r.drain();
      expect(r.renderer.rendered, [p1, p2]);
    });

    _testRig('asked again while its job runs → runs once more after it', (r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.renderer.delay = const Duration(milliseconds: 100);
      r.scheduler.request(n);
      r.elapse(850); // rendering
      expect(r.renderer.rendered, [p]);
      r.addStroke(n, p); // the running render draws the old revision
      final later = r.run(r.backend.store.library.getNote(n.id))!;
      r.scheduler.request(later);
      expect(r.scheduler.pendingCount, 0); // not queued: marked for a rerun
      r.drain();
      expect(r.renderer.rendered, [p, p]);
      expect(r.cached(p)!.contentRevision, r.revisionOf(p));
      expect(r.reader.getPageCalls, hasLength(2));
    });
  });

  group('disabled and disposed', () {
    _testRig('no renderer: isEnabled is false and nothing happens', (r) {
      final n = r.note('n');
      expect(r.scheduler.isEnabled, isFalse);
      r.scheduler.request(n);
      expect(r.scheduler.pendingCount, 0);
      r.drain();
      expect(r.reader.log, isEmpty);
      expect(r.cache.log, isEmpty);
      // It does not even listen.
      expect(r.changes.hasListener, isFalse);
      expect(r.arrivals.hasListener, isFalse);
      expect(r.isIdle(), isTrue);
    }, withRenderer: false);

    _testRig('dispose: the running job writes nothing, streams cancelled', (r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.renderer.delay = const Duration(milliseconds: 100);
      expect(r.scheduler.isEnabled, isTrue);
      expect(r.changes.hasListener, isTrue);
      expect(r.arrivals.hasListener, isTrue);
      r.scheduler.request(r.note('other'));
      r.scheduler.request(n);
      r.elapse(850); // n is rendering
      expect(r.renderer.rendered, [p]);
      var idle = false;
      r.scheduler.idle().then((_) => idle = true);
      r.scheduler.dispose();
      r.async.flushMicrotasks();
      expect(idle, isTrue);
      r.drain();
      expect(r.cache.writes, isEmpty);
      expect(r.cached(p), isNull);
      expect(r.renderer.rendered, [p]); // 'other' never ran
      expect(r.changes.hasListener, isFalse);
      expect(r.arrivals.hasListener, isFalse);
      r.scheduler.request(n); // ignored after dispose
      r.drain();
      expect(r.renderer.rendered, [p]);
    });
  });

  group('asset arrival (LIBRARY-O1)', () {
    _testRig('null → bytesArrived: visible notes again, cancelled ones not', (
      r,
    ) {
      final a = r.note('a', pages: [_pdfPage(_assetA)]);
      final b = r.note('b', pages: [_pdfPage(_assetA)]);
      final c = r.note('c', pages: [_pdfPage(_assetB)]);
      final pa = a.firstPageId!, pb = b.firstPageId!, pc = c.firstPageId!;
      r.renderer.nullFor = {pa, pb, pc};
      r.scheduler
        ..request(a)
        ..request(b)
        ..request(c);
      r.drain();
      expect(r.renderer.rendered, [pc, pb, pa]);
      expect(r.cache.writes, isEmpty);
      // The PDF bytes arrive (download / import); b's tile left the screen.
      r.renderer.nullFor = {};
      r.scheduler.cancel(b.id);
      r.arrivals.add('c' * 64); // an asset nobody waits for
      r.drain();
      expect(r.renderer.rendered, hasLength(3));
      r.arrivals.add(_assetA);
      r.drain();
      expect(r.renderer.rendered, [pc, pb, pa, pa]);
      expect(r.cache.writes, ['write $pa rev:0']);
      // b's check was cleared too: it renders when its tile shows again.
      r.scheduler.request(b);
      r.drain();
      expect(r.renderer.rendered, [pc, pb, pa, pa, pb]);
      // c still waits for its own asset.
      r.arrivals.add(_assetB);
      r.drain();
      expect(r.renderer.rendered.last, pc);
      expect(r.cached(pc), isNotNull);
    });

    _testRig('the asset arrives while the null render runs → rendered again', (
      r,
    ) {
      final n = r.note('n', pages: [_pdfPage(_assetA)]);
      final p = n.firstPageId!;
      r.renderer
        ..nullFor = {p}
        ..delay = const Duration(milliseconds: 100);
      r.scheduler.request(n);
      r.elapse(850); // rendering; this call will return null
      expect(r.renderer.rendered, [p]);
      r.renderer.nullFor = {}; // the bytes are here now
      r.arrivals.add(_assetA);
      r.async.flushMicrotasks();
      r.drain();
      expect(r.renderer.rendered, [p, p]);
      expect(r.cache.writes, ['write $p rev:0']);
    });
  });

  group('remote batches (LIBRARY-2-2, contract 7.2.10 v1.1)', () {
    /// n drawn once, then its first page changed "remotely".
    (Note, PageId) drawnThenChanged(_Rig r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p]);
      r.addStroke(n, p);
      return (n, p);
    }

    _testRig('remote stroke batch → one render after remoteSettle', (r) {
      final (n, p) = drawnThenChanged(r);
      r.batch([r.strokeOf(n, p)]);
      r.elapse(499);
      expect(r.renderer.rendered, [p]);
      r.elapse(1);
      r.drain();
      expect(r.renderer.rendered, [p, p]);
      expect(r.cached(p)!.contentRevision, r.revisionOf(p));
      expect(r.revisionOf(p), greaterThan(0));
    });

    _testRig('the same batch with origin local → nothing', (r) {
      final (n, p) = drawnThenChanged(r);
      r.batch([r.strokeOf(n, p)], origin: ChangeOrigin.local);
      r.batch([r.strokeOf(n, p)], origin: ChangeOrigin.undo);
      r.drain();
      expect(r.renderer.rendered, [p]);
    });

    _testRig('kind note (id = note id, no noteId) → same as a stroke', (r) {
      final (n, p) = drawnThenChanged(r);
      r.batch([EntityChange(kind: EntityKind.note, id: n.id)]);
      r.elapse(499);
      expect(r.renderer.rendered, [p]);
      r.drain();
      expect(r.renderer.rendered, [p, p]);
    });

    _testRig('folder / asset changes (noteId == null) are ignored', (r) {
      final (_, p) = drawnThenChanged(r);
      r.batch([
        const EntityChange(kind: EntityKind.folder, id: 'f-1'),
        EntityChange(kind: EntityKind.asset, id: _assetA),
      ]);
      r.drain();
      expect(r.renderer.rendered, [p]);
      expect(r.reader.getPageCalls, hasLength(1));
    });

    _testRig('a cancelled note is not drawn; requested again → drawn', (r) {
      final (n, p) = drawnThenChanged(r);
      r.scheduler.cancel(n.id);
      r.batch([r.strokeOf(n, p)]);
      r.drain();
      expect(r.renderer.rendered, [p]);
      // Its check was cleared, so the same (old) note value is checked again.
      r.scheduler.request(n);
      r.drain();
      expect(r.renderer.rendered, [p, p]);
    });

    _testRig('three batches within 500 ms for one note → one render', (r) {
      final (n, p) = drawnThenChanged(r);
      r.batch([r.strokeOf(n, p)]);
      r.elapse(200);
      r.batch([r.strokeOf(n, p)]);
      r.elapse(200);
      r.batch([
        r.strokeOf(n, p),
        EntityChange(kind: EntityKind.note, id: n.id),
      ]);
      r.drain();
      expect(r.renderer.rendered, [p, p]);
      expect(r.reader.getPageCalls, hasLength(2));
    });

    _testRig('a batch for another page → getPage + read only, no render', (r) {
      final n = r.note(
        'n',
        pages: const [PageDraft.blankA4, PageDraft.blankA4],
      );
      final [p1, p2] = r.pageIds(n);
      r.scheduler.request(n);
      r.drain();
      r.reader.log.clear();
      r.cache.log.clear();
      r.addStroke(n, p2);
      r.batch([r.strokeOf(n, p2)]);
      r.drain();
      expect(r.renderer.rendered, [p1]);
      expect(r.reader.log, ['getPage $p1']);
      expect(r.cache.log, ['read $p1']);
    });

    _testRig('a remote batch while the note renders → once more after it', (r) {
      final n = r.note('n');
      final p = n.firstPageId!;
      r.renderer.delay = const Duration(milliseconds: 100);
      r.scheduler.request(n);
      r.elapse(850); // rendering the old revision
      expect(r.renderer.rendered, [p]);
      r.addStroke(n, p);
      r.batch([r.strokeOf(n, p)]);
      r.drain();
      expect(r.renderer.rendered, [p, p]);
      expect(r.cached(p)!.contentRevision, r.revisionOf(p));
      expect(r.isIdle(), isTrue);
    });

    _testRig('idle() waits for the remote round', (r) {
      final (n, p) = drawnThenChanged(r);
      r.batch([r.strokeOf(n, p)]);
      expect(r.isIdle(), isFalse);
      var idle = false;
      r.scheduler.idle().then((_) => idle = true);
      r.elapse(400);
      expect(idle, isFalse);
      r.drain();
      expect(idle, isTrue);
    });
  });

  group('providers', () {
    test('coverThumbnailSchedulerProvider: CORE slots and streams', () {
      fakeAsync((async) {
        final backend = FakeLibraryBackend();
        final renderer = FakeThumbnailRenderer();
        final container = ProviderContainer(
          overrides: [
            ...backend.overrides,
            pageThumbnailRendererProvider.overrideWithValue(renderer),
          ],
        );
        T run<T>(Future<T> f) {
          late T v;
          var done = false;
          f.then((x) {
            v = x;
            done = true;
          });
          async.flushMicrotasks();
          for (var i = 0; i < 20 && !done; i++) {
            async.elapse(Duration.zero);
          }
          expect(done, isTrue);
          return v;
        }

        final bytes = Uint8List.fromList([1, 2, 3]);
        // The id the bytes will have (AssetId = SHA-256 of the bytes).
        final assetId = run(
          createFakeNoteStore().assets.put(
            bytes,
            type: AssetType.pdf,
            mimeType: 'application/pdf',
          ),
        ).id;
        final n = run(backend.seedNote('n', pages: [_pdfPage(assetId)]));
        final p = n.firstPageId!;
        renderer.nullFor = {p};
        final scheduler = container.read(coverThumbnailSchedulerProvider);
        expect(scheduler.isEnabled, isTrue);
        scheduler.request(n);
        async.elapse(const Duration(seconds: 2));
        expect(renderer.rendered, [p]);
        // AssetStore.bytesArrived of the real (fake) store → drawn again.
        renderer.nullFor = {};
        run(
          backend.store.assets.put(
            bytes,
            type: AssetType.pdf,
            mimeType: 'application/pdf',
          ),
        );
        async.elapse(const Duration(seconds: 2));
        expect(renderer.rendered, [p, p]);
        expect(run(backend.store.thumbnails.read(p)), isNotNull);
        // Disposing the container disposes the scheduler.
        container.dispose();
        async.flushMicrotasks();
        scheduler.request(n.copyWith(updatedAt: n.updatedAt + 1));
        async.elapse(const Duration(seconds: 2));
        expect(renderer.rendered, [p, p]);
        run(backend.dispose());
      });
    });

    test('without a renderer the provider gives a disabled scheduler', () {
      fakeAsync((async) {
        final backend = FakeLibraryBackend();
        final container = ProviderContainer(overrides: backend.overrides);
        expect(
          container.read(coverThumbnailSchedulerProvider).isEnabled,
          isFalse,
        );
        container.dispose();
        async.flushMicrotasks();
        backend.dispose();
        async.flushMicrotasks();
      });
    });

    test('a failure is reported to FlutterError (feature_library)', () {
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        fakeAsync((async) {
          final backend = FakeLibraryBackend();
          final renderer = FakeThumbnailRenderer();
          final container = ProviderContainer(
            overrides: [
              ...backend.overrides,
              pageThumbnailRendererProvider.overrideWithValue(renderer),
            ],
          );
          late Note n;
          backend.seedNote('n').then((v) => n = v);
          async.flushMicrotasks();
          async.elapse(Duration.zero);
          renderer.failFor = {n.firstPageId!};
          container.read(coverThumbnailSchedulerProvider).request(n);
          async.elapse(const Duration(seconds: 2));
          container.dispose();
          backend.dispose();
          async.flushMicrotasks();
        });
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, hasLength(1));
      expect(reports.single.library, 'feature_library');
      expect(reports.single.exception, isA<StateError>());
    });

    test('assetCoverBytesProvider: null until the bytes arrive', () {
      fakeAsync((async) {
        final backend = FakeLibraryBackend();
        final container = ProviderContainer(overrides: backend.overrides);
        final bytes = Uint8List.fromList([4, 5, 6]);
        late AssetId id;
        createFakeNoteStore().assets
            .put(bytes, type: AssetType.image, mimeType: 'image/png')
            .then((a) => id = a.id);
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        final sub = container.listen(assetCoverBytesProvider(id), (_, _) {});
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(sub.read(), const AsyncData<Uint8List?>(null));
        backend.store.assets.put(
          bytes,
          type: AssetType.image,
          mimeType: 'image/png',
        );
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.elapse(Duration.zero);
        expect(sub.read().value, bytes);
        sub.close();
        container.dispose();
        backend.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
