// PdfSearchNotifier (06-pdf 4.8, 6.10.2 step 7; 8 T11) on the real text service over
// FakePdfEngine + FakePdfNoteGateway: progress into state, first hit selected, a new start
// cancels the previous search, wrap-around selection, clear, errors, and the panel's stop
// (closing the panel cancels its search).
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/text/search_notifier.dart' show stopPdfSearch;
import 'package:pdf_io/testing.dart';

PdfPageTextData _text(int index, String text) => PdfPageTextData(
  pageIndex: index,
  text: text,
  charRects: [
    for (var i = 0; i < text.length; i++)
      Rect.fromLTWH(10 + 5.0 * i, 10, 5, 10),
  ],
);

final class _World {
  _World({int pages = 3}) {
    engine = FakePdfEngine(
      pageCount: pages,
      texts: {for (var i = 0; i < pages; i++) i: _text(i, 'one two one')},
    );
    container = ProviderContainer(
      overrides: [
        pdfEngineProvider.overrideWithValue(engine),
        pdfNoteGatewayProvider.overrideWithValue(gateway),
      ],
    );
  }

  late final FakePdfEngine engine;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final ProviderContainer container;

  PdfSearchNotifier get notifier =>
      container.read(pdfActiveSearchProvider.notifier);
  PdfSearchState get state => container.read(pdfActiveSearchProvider);

  Future<core.Note> note(int pages) async {
    final asset = await gateway.putPdf(
      Uint8List.fromList('%PDF-1.7\n%%EOF\n'.codeUnits),
      fileName: 'a.pdf',
    );
    return gateway.createNote(
      title: 'n',
      pages: [
        for (var i = 0; i < pages; i++)
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: i),
          ),
      ],
    );
  }

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await pumpEventQueue();
      if (state.status != PdfSearchStatus.searching) return;
    }
  }
}

void main() {
  test('start → searching → done, first hit selected', () async {
    final w = _World();
    addTearDown(w.container.dispose);
    final note = await w.note(3);
    final seen = <PdfSearchState>[];
    w.container.listen(pdfActiveSearchProvider, (_, s) => seen.add(s));

    w.notifier.start(note.id, 'One');
    expect(w.state.status, PdfSearchStatus.searching);
    expect(w.state.noteId, note.id);
    expect(w.state.query, 'One');
    expect(w.state.currentIndex, -1);
    await w.settle();

    final s = w.state;
    expect(s.status, PdfSearchStatus.done);
    expect(s.scannedPages, 3);
    expect(s.totalPages, 3);
    expect(s.hits, hasLength(6)); // two per page
    expect(s.currentIndex, 0);
    expect(s.current, s.hits.first);
    expect(s.truncated, isFalse);
    expect(seen.first.status, PdfSearchStatus.searching);
  });

  test('empty or blank query → idle', () async {
    final w = _World();
    addTearDown(w.container.dispose);
    final note = await w.note(1);
    w.notifier.start(note.id, 'one');
    await w.settle();
    expect(w.state.hits, isNotEmpty);
    w.notifier.start(note.id, '  ');
    expect(w.state, PdfSearchState.idle);
  });

  test('a new start cancels the previous search', () async {
    final w = _World();
    addTearDown(w.container.dispose);
    final hold = Completer<void>();
    w.engine.beforeLoadText = (_) => hold.future;
    final note = await w.note(3);
    w.notifier.start(note.id, 'one');
    await pumpEventQueue();
    expect(w.engine.loadTextCalls, [0]);

    w.notifier.start(note.id, 'two');
    w.engine.beforeLoadText = null;
    hold.complete();
    await w.settle();
    expect(w.state.query, 'two');
    expect(w.state.status, PdfSearchStatus.done);
    expect(w.state.hits, hasLength(3));
    // The first search never got past its first page.
    expect(w.engine.loadTextCalls.where((i) => i == 1), hasLength(1));
  });

  test(
    'selectNext / selectPrevious wrap around; select ignores bad indexes',
    () async {
      final w = _World(pages: 1);
      addTearDown(w.container.dispose);
      final note = await w.note(1);
      w.notifier.start(note.id, 'one');
      await w.settle();
      expect(w.state.hits, hasLength(2));
      expect(w.state.currentIndex, 0);
      w.notifier.selectNext();
      expect(w.state.currentIndex, 1);
      w.notifier.selectNext();
      expect(w.state.currentIndex, 0);
      w.notifier.selectPrevious();
      expect(w.state.currentIndex, 1);
      w.notifier.select(5);
      w.notifier.select(-1);
      expect(w.state.currentIndex, 1);
      w.notifier.select(0);
      expect(w.state.currentIndex, 0);
      expect(w.state.currentFocusRect, w.state.hits.first.rects.single);
    },
  );

  test('clear() cancels a running search and goes idle', () async {
    final w = _World();
    addTearDown(w.container.dispose);
    final hold = Completer<void>();
    w.engine.beforeLoadText = (_) => hold.future;
    final note = await w.note(3);
    w.notifier.start(note.id, 'one');
    await pumpEventQueue();
    w.notifier.clear();
    expect(w.state, PdfSearchState.idle);
    hold.complete();
    await pumpEventQueue();
    expect(w.state, PdfSearchState.idle);
    expect(w.engine.loadTextCalls, [0]);
  });

  test('unknown note → failed with noteNotFound', () async {
    final w = _World();
    addTearDown(w.container.dispose);
    w.notifier.start('note-404', 'one');
    await w.settle();
    expect(w.state.status, PdfSearchStatus.failed);
    expect(w.state.error?.code, PdfErrorCode.noteNotFound);
  });

  test(
    'stopPdfSearch (panel closed): keeps the hits so far, status idle',
    () async {
      final w = _World();
      addTearDown(w.container.dispose);
      final hold = Completer<void>();
      final note = await w.note(3);
      w.engine.beforeLoadText = (i) => i == 1 ? hold.future : Future.value();
      w.notifier.start(note.id, 'one');
      // Page 0 is scanned; its hits arrive with the first progress (or at the end).
      await pumpEventQueue();
      stopPdfSearch(w.notifier);
      final stopped = w.state;
      expect(stopped.status, PdfSearchStatus.idle);
      expect(stopped.noteId, note.id);
      expect(stopped.query, 'one');
      hold.complete();
      await pumpEventQueue();
      expect(w.state, stopped);
      expect(w.engine.loadTextCalls, [0, 1]);

      // A finished search is left alone.
      w.engine.beforeLoadText = null;
      w.notifier.start(note.id, 'one');
      await w.settle();
      final done = w.state;
      stopPdfSearch(w.notifier);
      expect(w.state, done);
    },
  );
}
