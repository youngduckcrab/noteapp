// Search value equality (06-pdf 4.8, PDF-3-2, contract 7.4.4; 8 T11): PdfSearchHit and
// PdfSearchState compare by value (rects / hits deep, error by code + detail), and equal
// states notify nobody — pdfActiveSearchProvider (Riverpod 3.4.3: previous != next) and the
// pdfSearchHighlightsProvider ValueNotifier.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

PdfSearchHit _hit({
  String pageId = 'page-1',
  List<Rect>? rects,
  String snippet = 'a hit here',
}) => PdfSearchHit(
  pageId: pageId,
  notePageNumber: 1,
  assetId: 'asset-1',
  pdfPageIndex: 0,
  rects:
      rects ??
      [const Rect.fromLTWH(1, 2, 3, 4), const Rect.fromLTWH(5, 6, 7, 8)],
  snippet: snippet,
  matchStart: 2,
  matchLength: 3,
);

void main() {
  group('PdfSearchHit', () {
    test('equal values in different lists → == and same hashCode', () {
      final a = _hit();
      final b = _hit();
      expect(identical(a.rects, b.rects), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('one rect different → not equal', () {
      final a = _hit();
      final b = _hit(
        rects: [
          const Rect.fromLTWH(1, 2, 3, 4),
          const Rect.fromLTWH(5, 6, 7, 9),
        ],
      );
      expect(a, isNot(b));
      expect(_hit(rects: const []), isNot(a));
    });

    test('every other field counts', () {
      expect(_hit(pageId: 'page-2'), isNot(_hit()));
      expect(_hit(snippet: 'other'), isNot(_hit()));
    });
  });

  group('PdfSearchState', () {
    test('hits compared deeply', () {
      final a = PdfSearchState(
        noteId: 'note-1',
        query: 'hit',
        status: PdfSearchStatus.done,
        scannedPages: 3,
        totalPages: 3,
        hits: [
          _hit(),
          _hit(pageId: 'page-2'),
        ],
        currentIndex: 0,
      );
      final b = PdfSearchState(
        noteId: 'note-1',
        query: 'hit',
        status: PdfSearchStatus.done,
        scannedPages: 3,
        totalPages: 3,
        hits: [
          _hit(),
          _hit(pageId: 'page-2'),
        ],
        currentIndex: 0,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          PdfSearchState(
            noteId: 'note-1',
            query: 'hit',
            status: PdfSearchStatus.done,
            scannedPages: 3,
            totalPages: 3,
            hits: [
              _hit(),
              _hit(pageId: 'page-3'),
            ],
            currentIndex: 0,
          ),
        ),
      );
    });

    test('error compared by code and detail (not cause)', () {
      PdfSearchState failed(PdfIoException e) =>
          PdfSearchState(status: PdfSearchStatus.failed, error: e);
      final a = failed(
        PdfIoException(PdfErrorCode.noteNotFound, detail: 'n', cause: Object()),
      );
      final b = failed(
        PdfIoException(PdfErrorCode.noteNotFound, detail: 'n', cause: Object()),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(failed(const PdfIoException(PdfErrorCode.noteNotFound))));
    });

    test('idle constant equals a default state', () {
      // ignore: use_named_constants
      expect(PdfSearchState.idle, const PdfSearchState());
    });
  });

  group('equal states notify nobody (ProviderContainer)', () {
    late ProviderContainer container;
    late core.NoteId noteId;

    setUp(() async {
      final gateway = FakePdfNoteGateway();
      final engine = FakePdfEngine(
        pageCount: 2,
        texts: {
          0: const PdfPageTextData(
            pageIndex: 0,
            text: 'hit',
            charRects: [
              Rect.fromLTWH(10, 10, 5, 10),
              Rect.fromLTWH(15, 10, 5, 10),
              Rect.fromLTWH(20, 10, 5, 10),
            ],
          ),
        },
      );
      container = ProviderContainer(
        overrides: [
          pdfEngineProvider.overrideWithValue(engine),
          pdfNoteGatewayProvider.overrideWithValue(gateway),
        ],
      );
      final asset = await gateway.putPdf(
        Uint8List.fromList('%PDF-1.7\n%%EOF\n'.codeUnits),
        fileName: 'a.pdf',
      );
      final note = await gateway.createNote(
        title: 'n',
        pages: [
          for (var i = 0; i < 2; i++)
            core.PageDraft(
              size: core.PageSize.a4Portrait,
              background: core.PdfBackground(
                assetId: asset.id,
                pdfPageIndex: 0,
              ),
            ),
        ],
      );
      noteId = note.id;
    });
    tearDown(() => container.dispose());

    Future<void> searchToEnd() async {
      container.read(pdfActiveSearchProvider.notifier).start(noteId, 'hit');
      for (var i = 0; i < 20; i++) {
        await pumpEventQueue();
        if (container.read(pdfActiveSearchProvider).status ==
            PdfSearchStatus.done) {
          return;
        }
      }
      fail('the search did not finish');
    }

    test('select(0) twice after the search: no notification', () async {
      final highlights = container.read(pdfSearchHighlightsProvider);
      final changes = <PdfSearchState>[];
      container.listen(pdfActiveSearchProvider, (_, next) => changes.add(next));
      var highlightCalls = 0;
      highlights.addListener(() => highlightCalls++);

      await searchToEnd();
      final done = container.read(pdfActiveSearchProvider);
      expect(done.hits, hasLength(2));
      expect(done.currentIndex, 0); // first hit selected on arrival
      final n = changes.length;
      final h = highlightCalls;
      expect(highlights.value, done);

      final notifier = container.read(pdfActiveSearchProvider.notifier);
      notifier.select(0); // a new state object equal to the current one
      notifier.select(0);
      expect(changes.length, n);
      expect(highlightCalls, h);

      notifier.select(1);
      expect(changes.length, n + 1);
      expect(highlightCalls, h + 1);
      notifier.select(1);
      expect(changes.length, n + 1);
      expect(highlightCalls, h + 1);
      expect(highlights.value.currentIndex, 1);
    });
  });
}
