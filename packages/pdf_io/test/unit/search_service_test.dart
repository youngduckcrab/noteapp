// DefaultPdfTextService (06-pdf 4.8, 6.10.2; 8 T11) on FakePdfEngine + FakePdfNoteGateway +
// the real DefaultPdfDocumentPool: note page order, per-line merging, snippets, cancel,
// the hit cap, non-PDF and missing-original pages, PdfPageFit conversion to note pt
// (PDF-2-4, s ≠ 1 and resized pages), the pending pre-search flush (PDF-3-1), progress
// batching and the text cache.
import 'dart:async';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

Uint8List _pdf([String body = 'body']) =>
    Uint8List.fromList('%PDF-1.7\n% $body\n%%EOF\n'.codeUnits);

/// Text laid out on lines (joined with '\r\n'): line i at y = 10 + 20·i, characters 5 pt
/// wide and 10 pt high from x = 10. Line breaks get Rect.zero (PDFium has no box for them).
PdfPageTextData _text(int pageIndex, List<String> lines) {
  final text = StringBuffer();
  final rects = <Rect>[];
  for (var l = 0; l < lines.length; l++) {
    if (l > 0) {
      text.write('\r\n');
      rects.addAll([Rect.zero, Rect.zero]);
    }
    final line = lines[l];
    for (var c = 0; c < line.length; c++) {
      rects.add(Rect.fromLTWH(10 + 5.0 * c, 10 + 20.0 * l, 5, 10));
    }
    text.write(line);
  }
  return PdfPageTextData(
    pageIndex: pageIndex,
    text: text.toString(),
    charRects: rects,
  );
}

core.PageDraft _pdfPage(
  core.AssetId assetId,
  int index, {
  core.PageSize size = core.PageSize.a4Portrait,
}) => core.PageDraft(
  size: size,
  background: core.PdfBackground(assetId: assetId, pdfPageIndex: index),
);

const core.PageDraft _blank = core.PageDraft.blankA4;

final class _World {
  _World(this.engine);

  final FakePdfEngine engine;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final DefaultPdfDocumentPool pool = DefaultPdfDocumentPool(
    engine: engine,
    gateway: gateway,
  );
  late final DefaultPdfTextService service = DefaultPdfTextService(
    pool: pool,
    gateway: gateway,
  );

  Future<core.AssetId> addPdf([String body = 'body']) async =>
      (await gateway.putPdf(_pdf(body), fileName: '$body.pdf')).id;

  Future<core.Note> note(List<core.PageDraft> pages) =>
      gateway.createNote(title: 'note', pages: pages);

  Future<List<core.Page>> pages(core.NoteId id) => gateway.pagesOf(id);

  Future<void> dispose() => pool.dispose();
}

/// Collects a whole search.
Future<List<PdfSearchProgress>> _collect(Stream<PdfSearchProgress> s) =>
    s.toList();

List<PdfSearchHit> _hits(List<PdfSearchProgress> events) => [
  for (final e in events) ...e.newHits,
];

Matcher _rectCloseTo(Rect r) => isA<Rect>()
    .having((x) => x.left, 'left', closeTo(r.left, 1e-6))
    .having((x) => x.top, 'top', closeTo(r.top, 1e-6))
    .having((x) => x.width, 'width', closeTo(r.width, 1e-6))
    .having((x) => x.height, 'height', closeTo(r.height, 1e-6));

void main() {
  test(
    'note page order, non-PDF pages skipped, totalPages = PDF pages',
    () async {
      final w = _World(
        FakePdfEngine(
          pageCount: 2,
          texts: {
            0: _text(0, ['alpha beta']),
            1: _text(1, ['beta gamma beta']),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([
        _blank,
        _pdfPage(asset, 1),
        _blank,
        _pdfPage(asset, 0),
      ]);
      final pages = await w.pages(note.id);

      final events = await _collect(w.service.searchNote(note.id, 'BETA'));
      expect(events.last.isDone, isTrue);
      expect(events.last.scannedPages, 2);
      expect(events.last.totalPages, 2);
      expect(events.last.truncated, isFalse);
      final hits = _hits(events);
      expect(
        [for (final h in hits) (h.pageId, h.notePageNumber, h.pdfPageIndex)],
        [(pages[1].id, 2, 1), (pages[1].id, 2, 1), (pages[3].id, 4, 0)],
      );
      expect(hits.every((h) => h.assetId == asset), isTrue);
      // Position on the page: the second 'beta' of pdf page 1 is further right.
      expect(hits[1].rects.single.left, greaterThan(hits[0].rects.single.left));
    },
  );

  test('a note without PDF pages / an empty query → one done event', () async {
    final w = _World(FakePdfEngine());
    addTearDown(w.dispose);
    final note = await w.note([_blank]);
    final events = await _collect(w.service.searchNote(note.id, 'x'));
    expect(events, hasLength(1));
    expect(events.single.isDone, isTrue);
    expect(events.single.totalPages, 0);
    expect(events.single.newHits, isEmpty);

    final asset = await w.addPdf();
    final pdfNote = await w.note([_pdfPage(asset, 0)]);
    final blank = await _collect(w.service.searchNote(pdfNote.id, '  '));
    expect(blank.single.isDone, isTrue);
    expect(blank.single.totalPages, 1);
    expect(w.engine.loadTextCalls, isEmpty);
  });

  test('unknown note → noteNotFound on the stream', () async {
    final w = _World(FakePdfEngine());
    addTearDown(w.dispose);
    await expectLater(
      w.service.searchNote('note-404', 'x'),
      emitsError(
        isA<PdfIoException>().having(
          (e) => e.code,
          'code',
          PdfErrorCode.noteNotFound,
        ),
      ),
    );
  });

  group('rects merged per line', () {
    test('one line → one rect over the matched characters', () async {
      final w = _World(
        FakePdfEngine(
          texts: {
            0: _text(0, ['foo bar baz']),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]); // A4: identity fit
      final hit = _hits(
        await _collect(w.service.searchNote(note.id, 'bar baz')),
      ).single;
      // Characters 4..10: x 30..65.
      expect(hit.rects, [_rectCloseTo(const Rect.fromLTRB(30, 10, 65, 20))]);
    });

    test('a match over a line break → one rect per line', () async {
      final w = _World(
        FakePdfEngine(
          texts: {
            0: _text(0, ['aa bb', 'cc dd']),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'bb cc')))
          .single;
      expect(hit.rects, [
        _rectCloseTo(const Rect.fromLTRB(25, 10, 35, 20)),
        _rectCloseTo(const Rect.fromLTRB(10, 30, 20, 40)),
      ]);
    });

    test('a hyphenated word found across lines', () async {
      final w = _World(
        FakePdfEngine(
          texts: {
            0: _text(0, ['to con-', 'tinue here']),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(
        await _collect(w.service.searchNote(note.id, 'continue')),
      ).single;
      expect(hit.rects, hasLength(2));
      expect(
        hit.snippet.substring(hit.matchStart, hit.matchStart + hit.matchLength),
        'continue',
      );
    });

    test('a gap wider than half the height splits the rect', () async {
      final rects = [
        const Rect.fromLTWH(10, 10, 5, 10),
        const Rect.fromLTWH(15, 10, 5, 10),
        const Rect.fromLTWH(40, 10, 5, 10), // 20 pt gap
      ];
      final w = _World(
        FakePdfEngine(
          texts: {
            0: PdfPageTextData(pageIndex: 0, text: 'abc', charRects: rects),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'abc')))
          .single;
      expect(hit.rects, [
        _rectCloseTo(const Rect.fromLTRB(10, 10, 20, 20)),
        _rectCloseTo(const Rect.fromLTRB(40, 10, 45, 20)),
      ]);
    });

    test('char rects of the wrong length → a hit without rects', () async {
      final w = _World(
        FakePdfEngine(
          texts: {
            0: const PdfPageTextData(
              pageIndex: 0,
              text: 'abc',
              charRects: [Rect.fromLTWH(0, 0, 1, 1)],
            ),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'b')))
          .single;
      expect(hit.rects, isEmpty);
      expect(hit.snippet, 'abc');
    });
  });

  group('snippet', () {
    test('±24 characters of context in the original case', () async {
      final raw = '${'x' * 40} Target ${'y' * 40}';
      final w = _World(
        FakePdfEngine(
          texts: {
            0: _text(0, [raw]),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'target')))
          .single;
      expect(hit.snippet, '${'x' * 23} Target ${'y' * 23}');
      expect(hit.matchStart, 24);
      expect(hit.matchLength, 6);
    });

    test('whitespace collapsed, line breaks become spaces', () async {
      final w = _World(
        FakePdfEngine(
          texts: {
            0: _text(0, ['one', '', 'Two  three']),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'two')))
          .single;
      expect(hit.snippet, 'one Two three');
      expect(hit.snippet.substring(hit.matchStart, hit.matchStart + 3), 'Two');
    });

    test('NFD Korean text is found and shown composed', () async {
      // '강의 자료' with 강의 in conjoining jamo.
      const nfd = '\u1100\u1161\u11BC\u110B\u1174 자료';
      final w = _World(
        FakePdfEngine(
          texts: {
            0: _text(0, [nfd]),
          },
        ),
      );
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([_pdfPage(asset, 0)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, '강의')))
          .single;
      expect(hit.snippet, '강의 자료');
      expect(hit.matchStart, 0);
      expect(hit.matchLength, 2);
      // The rect covers the five jamo (x 10..35).
      expect(hit.rects, [_rectCloseTo(const Rect.fromLTRB(10, 10, 35, 20))]);
    });
  });

  test(
    'cancel while scanning: the stream ends without done or error',
    () async {
      final hold = Completer<void>();
      final engine = FakePdfEngine(
        pageCount: 3,
        texts: {
          for (var i = 0; i < 3; i++) i: _text(i, ['hit']),
        },
      );
      engine.beforeLoadText = (i) => i == 1 ? hold.future : Future.value();
      final w = _World(engine);
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final note = await w.note([
        for (var i = 0; i < 3; i++) _pdfPage(asset, i),
      ]);
      final cancel = PdfCancelSignal();
      final events = <PdfSearchProgress>[];
      final errors = <Object>[];
      var done = false;
      w.service
          .searchNote(note.id, 'hit', cancel: cancel)
          .listen(events.add, onError: errors.add, onDone: () => done = true);
      await pumpEventQueue();
      expect(engine.loadTextCalls, [0, 1]);
      cancel.cancel();
      await pumpEventQueue();
      expect(done, isTrue);
      expect(errors, isEmpty);
      expect(events.where((e) => e.isDone), isEmpty);
      hold.complete();
      await pumpEventQueue();
      expect(engine.loadTextCalls, [0, 1]); // page 2 never read
    },
  );

  test('PDF-3-1: cancel while the pre-search flush waits', () async {
    final w = _World(
      FakePdfEngine(
        texts: {
          0: _text(0, ['hit']),
        },
      ),
    );
    addTearDown(w.dispose);
    final asset = await w.addPdf();
    final note = await w.note([_pdfPage(asset, 0)]);
    w.gateway.calls.clear();
    w.gateway.holdWrites();
    final cancel = PdfCancelSignal();
    final events = <PdfSearchProgress>[];
    final errors = <Object>[];
    var done = false;
    await runZonedGuarded(() async {
      w.service
          .searchNote(note.id, 'hit', cancel: cancel)
          .listen(events.add, onError: errors.add, onDone: () => done = true);
      await pumpEventQueue();
      expect(w.gateway.calls, ['flush']);
      expect(done, isFalse);
      cancel.cancel();
      await pumpEventQueue();
      expect(done, isTrue);
      expect(events, isEmpty);
      expect(errors, isEmpty);
      // The held flush completes later: nothing else happens.
      w.gateway.releaseWrites();
      await pumpEventQueue();
    }, (e, st) => errors.add(e));
    expect(errors, isEmpty);
    expect(w.gateway.calls, ['flush']); // no pagesOf
    expect(w.engine.loadTextCalls, isEmpty);
  });

  test('hit cap: PdfTuning.maxSearchHits (2000) → truncated', () async {
    final line = List.filled(150, 'a').join(' ');
    final w = _World(
      FakePdfEngine(
        pageCount: 20,
        texts: {
          for (var i = 0; i < 20; i++) i: _text(i, [line]),
        },
      ),
    );
    addTearDown(w.dispose);
    final asset = await w.addPdf();
    final note = await w.note([
      for (var i = 0; i < 20; i++) _pdfPage(asset, i),
    ]);
    final events = await _collect(w.service.searchNote(note.id, 'a'));
    expect(PdfTuning.maxSearchHits, 2000);
    expect(_hits(events), hasLength(2000));
    expect(events.last.isDone, isTrue);
    expect(events.last.truncated, isTrue);
    expect(events.last.scannedPages, 14); // 14 × 150 ≥ 2000
    expect(w.engine.loadTextCalls, hasLength(14));

    final few = await _collect(w.service.searchNote(note.id, 'a', maxHits: 3));
    expect(_hits(few), hasLength(3));
    expect(few.last.truncated, isTrue);
  });

  test(
    'pages whose original is missing are skipped (scanned anyway)',
    () async {
      final w = _World(
        FakePdfEngine(
          pageCount: 2,
          texts: {
            0: _text(0, ['hit']),
            1: _text(1, ['hit']),
          },
        ),
      );
      addTearDown(w.dispose);
      final local = await w.addPdf();
      w.gateway.addRemoteAsset('remote-asset');
      final note = await w.note([
        _pdfPage(local, 0),
        _pdfPage('remote-asset', 0),
        _pdfPage('remote-asset', 1),
        _pdfPage(local, 1),
      ]);
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      addTearDown(() => FlutterError.onError = previous);

      final events = await _collect(w.service.searchNote(note.id, 'hit'));
      expect(events.last.scannedPages, 4);
      expect(events.last.totalPages, 4);
      expect(_hits(events).map((h) => h.notePageNumber), [1, 4]);
      expect(reports, isEmpty); // a missing original is not an error (6.13)
    },
  );

  test('a broken original is skipped and reported once', () async {
    final w = _World(
      FakePdfEngine(
        texts: {
          0: _text(0, ['hit']),
        },
      ),
    );
    addTearDown(w.dispose);
    final good = await w.addPdf();
    const broken = 'broken-asset';
    w.gateway.arriveBytes(broken, Uint8List.fromList('not a pdf'.codeUnits));
    final note = await w.note([
      _pdfPage(broken, 0),
      _pdfPage(broken, 1),
      _pdfPage(good, 0),
    ]);
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    final events = await _collect(w.service.searchNote(note.id, 'hit'));
    expect(_hits(events).map((h) => h.notePageNumber), [3]);
    expect(events.last.scannedPages, 3);
    expect(reports, hasLength(1));
    expect(reports.single.library, 'pdf_io');
  });

  group('PDF-2-4: rects in NOTE page pt (PdfPageFit)', () {
    late _World w;
    late core.AssetId asset;
    setUp(() async {
      w = _World(
        FakePdfEngine(
          pages: const [
            PdfPageInfo(
              index: 0,
              width: 50,
              height: 50,
              rotationQuarterTurns: 0,
            ),
            PdfPageInfo(
              index: 1,
              width: 612,
              height: 792,
              rotationQuarterTurns: 0,
            ),
          ],
          texts: {
            0: const PdfPageTextData(
              pageIndex: 0,
              text: 'q',
              charRects: [Rect.fromLTWH(10, 10, 5, 5)],
            ),
            1: const PdfPageTextData(
              pageIndex: 1,
              text: 'q',
              charRects: [Rect.fromLTWH(100, 100, 10, 10)],
            ),
          },
        ),
      );
      asset = await w.addPdf();
    });
    tearDown(() => w.dispose());

    test('50×50 PDF page on a 72×72 note page: s ≠ 1 → ×1.44', () async {
      final note = await w.note([
        _pdfPage(asset, 0, size: const core.PageSize(72, 72)),
      ]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'q')))
          .single;
      expect(hit.rects, [
        _rectCloseTo(const Rect.fromLTWH(14.4, 14.4, 7.2, 7.2)),
      ]);
      final state = PdfSearchState(
        noteId: note.id,
        query: 'q',
        status: PdfSearchStatus.done,
        hits: [hit],
        currentIndex: 0,
      );
      expect(state.rectsFor(hit.pageId), hit.rects);
      expect(state.currentFocusRect, hit.rects.single);
    });

    test('Letter PDF page on an A4 note page: the oy margin', () async {
      final note = await w.note([_pdfPage(asset, 1)]);
      final hit = _hits(await _collect(w.service.searchNote(note.id, 'q')))
          .single;
      final fit = PdfPageFit(
        notePageSize: const Size(595.2756, 841.8898),
        pdfPageSize: const Size(612, 792),
      );
      expect(fit.k, closeTo(0.97267, 1e-5));
      expect(fit.oy, closeTo(35.767, 1e-3));
      expect(hit.rects, [
        _rectCloseTo(fit.pdfToNote(const Rect.fromLTWH(100, 100, 10, 10))),
      ]);
      expect(hit.rects.single.top, closeTo(100 * fit.k + 35.767, 1e-3));
    });

    test('the same PDF page on two note pages of different sizes', () async {
      final note = await w.note([
        _pdfPage(asset, 0, size: const core.PageSize(72, 72)),
        _pdfPage(asset, 0, size: const core.PageSize(144, 100)),
      ]);
      final pages = await w.pages(note.id);
      final hits = _hits(await _collect(w.service.searchNote(note.id, 'q')));
      expect(hits.map((h) => h.pageId), [pages[0].id, pages[1].id]);
      // 144×100: k = 2, ox = 22, oy = 0.
      expect(hits[1].rects, [
        _rectCloseTo(const Rect.fromLTWH(42, 20, 10, 10)),
      ]);
      expect(hits[0].rects.single, isNot(hits[1].rects.single));
      final state = PdfSearchState(hits: hits, currentIndex: 1);
      expect(state.rectsFor(pages[0].id), hits[0].rects);
      expect(state.rectsFor(pages[1].id), hits[1].rects);
      expect(state.currentRectsFor(pages[0].id), isEmpty);
      expect(state.currentRectsFor(pages[1].id), hits[1].rects);
    });
  });

  test('progress every 10 pages, or when 100 ms passed', () {
    fakeAsync((async) {
      final engine = FakePdfEngine(
        pageCount: 25,
        texts: {
          for (var i = 0; i < 25; i++) i: _text(i, ['p$i']),
        },
      );
      final w = _World(engine);
      late core.Note note;
      w.addPdf().then(
        (asset) => w
            .note([for (var i = 0; i < 25; i++) _pdfPage(asset, i)])
            .then((n) => note = n),
      );
      async.flushMicrotasks();

      // No time passes: batches of 10 pages.
      final quick = <PdfSearchProgress>[];
      w.service.searchNote(note.id, 'p').listen(quick.add);
      async.flushMicrotasks();
      expect(quick.map((e) => (e.scannedPages, e.isDone)), [
        (0, false), // the page count first
        (10, false),
        (20, false),
        (25, true),
      ]);
      expect(_hits(quick), hasLength(25));

      // 60 ms per page: the 100 ms tick comes first.
      w.service.clearCache();
      engine.beforeLoadText = (_) =>
          Future<void>.delayed(const Duration(milliseconds: 60));
      final slow = <PdfSearchProgress>[];
      w.service.searchNote(note.id, 'p').listen(slow.add);
      async.elapse(const Duration(seconds: 2));
      expect(slow.last.isDone, isTrue);
      expect(slow.first.scannedPages, 0);
      expect(slow.first.totalPages, 25);
      expect(slow[1].scannedPages, 2);
      expect(slow.length, greaterThan(3));
      final scanned = [for (final e in slow) e.scannedPages];
      expect(scanned, orderedEquals([...scanned]..sort()));
      expect(_hits(slow), hasLength(25));
      w.dispose();
      async.flushMicrotasks();
    });
  });

  group('pageText cache', () {
    test('cached per (asset, page); clearCache reloads', () async {
      final engine = FakePdfEngine(
        texts: {
          0: _text(0, ['x']),
        },
      );
      final w = _World(engine);
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      final a = await w.service.pageText(asset, 0);
      final b = await w.service.pageText(asset, 0);
      expect(identical(a, b), isTrue);
      expect(engine.loadTextCalls, [0]);
      w.service.clearCache();
      await w.service.pageText(asset, 0);
      expect(engine.loadTextCalls, [0, 0]);
    });

    test('concurrent requests share one load', () async {
      final engine = FakePdfEngine();
      final w = _World(engine);
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      await Future.wait([
        w.service.pageText(asset, 0),
        w.service.pageText(asset, 0),
      ]);
      expect(engine.loadTextCalls, [0]);
    });

    test('LRU of PdfTuning.textCachePages pages', () async {
      expect(PdfTuning.textCachePages, 600);
      final engine = FakePdfEngine(pageCount: 601);
      final w = _World(engine);
      addTearDown(w.dispose);
      final asset = await w.addPdf();
      for (var i = 0; i < 601; i++) {
        await w.service.pageText(asset, i);
      }
      engine.loadTextCalls.clear();
      await w.service.pageText(asset, 600); // still cached
      await w.service.pageText(asset, 1); // still cached
      expect(engine.loadTextCalls, isEmpty);
      await w.service.pageText(asset, 0); // evicted first
      expect(engine.loadTextCalls, [0]);
    });

    test('missing original → assetMissing, bad page → corrupt', () async {
      final w = _World(FakePdfEngine());
      addTearDown(w.dispose);
      w.gateway.addRemoteAsset('remote');
      await expectLater(
        w.service.pageText('remote', 0),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.assetMissing,
          ),
        ),
      );
      final asset = await w.addPdf();
      await expectLater(
        w.service.pageText(asset, 7),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.corrupt,
          ),
        ),
      );
    });
  });
}
