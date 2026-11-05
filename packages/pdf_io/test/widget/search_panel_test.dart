// Search panel (06-pdf 4.11 showPdfSearchPanel, 6.10.2; 8 T11): 250 ms debounce, progress,
// hit tap → select + onNavigate(pageId, focusRectPt) with focusRectPt == currentFocusRect ==
// the union of the hit's rects (note pt, s ≠ 1 included), a hit without rects →
// onNavigate(pageId, null), previous / next, the storage-delay text while the pre-search
// flush waits on CORE retries (PDF-3-1), and closing the panel cancels its search.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

const String _delayText = '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.';

Uint8List _pdf([String body = 'body']) =>
    Uint8List.fromList('%PDF-1.7\n% $body\n%%EOF\n'.codeUnits);

/// One line of [text] at y 10, 5 pt per character from x 10.
PdfPageTextData _line(int index, String text) => PdfPageTextData(
  pageIndex: index,
  text: text,
  charRects: [
    for (var i = 0; i < text.length; i++)
      Rect.fromLTWH(10 + 5.0 * i, 10, 5, 10),
  ],
);

final class _World {
  _World({
    FakePdfEngine? engine,
    PdfNoteGateway? gateway,
    core.NoteStore? store,
  }) : engine = engine ?? FakePdfEngine(),
       store = store ?? core_testing.createFakeNoteStore() {
    this.gateway = gateway ?? FakePdfNoteGateway();
    container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(this.store),
        pdfEngineProvider.overrideWithValue(this.engine),
        pdfNoteGatewayProvider.overrideWithValue(this.gateway),
      ],
    );
  }

  final FakePdfEngine engine;
  final core.NoteStore store;
  late final PdfNoteGateway gateway;
  late final ProviderContainer container;
  late BuildContext context;
  final List<(String, Rect?)> navigations = [];

  PdfSearchState get search => container.read(pdfActiveSearchProvider);

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            this.context = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );

  Future<void> open(String noteId) {
    final panel = showPdfSearchPanel(
      context,
      noteId: noteId,
      onNavigate: (pageId, rect) => navigations.add((pageId, rect)),
    );
    return panel;
  }

  /// A note whose pages show pages [pdfPages] of one stored PDF at [size].
  Future<core.Note> pdfNote(
    List<int> pdfPages, {
    core.PageSize size = core.PageSize.a4Portrait,
  }) async {
    final asset = await gateway.putPdf(_pdf(), fileName: 'a.pdf');
    return gateway.createNote(
      title: 'n',
      pages: [
        for (final i in pdfPages)
          core.PageDraft(
            size: size,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: i),
          ),
      ],
    );
  }

  bool _disposed = false;

  /// Ends the test inside its fake zone: the pool's idle timers (60 s) go with the container.
  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    _disposeContainer();
    await tester.pump();
  }

  void _disposeContainer() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  Future<void> dispose() async {
    _disposeContainer();
    await store.close();
  }
}

/// No pumpAndSettle: the indeterminate progress bar never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Real async work (the fake gateway / engine futures) between frames.
Future<void> _run(WidgetTester tester) async {
  await tester.runAsync(pumpEventQueue);
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

void main() {
  testWidgets('250 ms debounce, progress, results, tap → onNavigate', (
    tester,
  ) async {
    final hold = Completer<void>();
    final engine = FakePdfEngine(
      pageCount: 12,
      texts: {for (var i = 0; i < 12; i++) i: _line(i, 'page $i alpha')},
    );
    final w = _World(engine: engine);
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final note = await tester.runAsync(
      () => w.pdfNote([for (var i = 0; i < 12; i++) i]),
    );
    final pages = (await tester.runAsync(() => w.gateway.pagesOf(note!.id)))!;
    engine.beforeLoadText = (i) => i == 11 ? hold.future : Future.value();

    final panel = w.open(note!.id);
    await _settle(tester);
    expect(find.text('찾을 내용'), findsOneWidget);
    final fake = w.gateway as FakePdfNoteGateway;
    fake.calls.clear();

    await _type(tester, 'a');
    await tester.pump(const Duration(milliseconds: 200));
    await _type(tester, 'alpha');
    await tester.pump(const Duration(milliseconds: 200));
    expect(fake.calls, isNot(contains('flush'))); // still debouncing
    expect(w.search.status, PdfSearchStatus.idle);
    await tester.pump(const Duration(milliseconds: 60));
    expect(w.search.status, PdfSearchStatus.searching);
    expect(w.search.query, 'alpha');
    await _run(tester);
    expect(fake.calls.where((c) => c == 'flush'), hasLength(1));

    // Held at the 12th page: 10 pages reported so far.
    expect(find.text('찾는 중 (10/12쪽)'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(10 / 12, 1e-9));
    expect(find.text(_delayText), findsNothing);

    hold.complete();
    await _run(tester);
    expect(w.search.status, PdfSearchStatus.done);
    expect(find.text('결과 12개 중 1번째'), findsOneWidget);
    expect(find.text('1쪽'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('2쪽'));
    await tester.pump();
    expect(w.search.currentIndex, 1);
    final hit = w.search.hits[1];
    expect(w.navigations, [(pages[1].id, w.search.currentFocusRect)]);
    expect(w.navigations.single.$2, hit.rects.single);
    expect(find.text('결과 12개 중 2번째'), findsOneWidget);

    // Next / previous navigate too (wrapping).
    await tester.tap(find.byTooltip('다음 결과'));
    await tester.pump();
    expect(w.navigations.last.$1, pages[2].id);
    await tester.tap(find.byTooltip('이전 결과'));
    await tester.tap(find.byTooltip('이전 결과'));
    await tester.tap(find.byTooltip('이전 결과'));
    await tester.pump();
    expect(w.search.currentIndex, 11);
    expect(w.navigations.last.$1, pages[11].id);

    await tester.tap(find.byTooltip('닫기'));
    await _settle(tester);
    await panel;
    expect(find.byType(TextField), findsNothing);
    // A finished search stays (highlights) after the panel closes.
    expect(w.search.status, PdfSearchStatus.done);
    await w.end(tester);
  });

  testWidgets('focusRectPt = union of the hit rects in NOTE pt (s ≠ 1)', (
    tester,
  ) async {
    // 50 × 50 pt PDF page on a 72 × 72 note page (k = 1.44); the match spans two lines.
    final engine = FakePdfEngine(
      pageSize: const Size(50, 50),
      texts: {
        0: const PdfPageTextData(
          pageIndex: 0,
          text: 'ab\r\ncd',
          charRects: [
            Rect.fromLTWH(10, 10, 5, 5),
            Rect.fromLTWH(15, 10, 5, 5),
            Rect.zero,
            Rect.zero,
            Rect.fromLTWH(5, 20, 5, 5),
            Rect.fromLTWH(10, 20, 5, 5),
          ],
        ),
      },
    );
    final w = _World(engine: engine);
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final note = await tester.runAsync(
      () => w.pdfNote([0], size: const core.PageSize(72, 72)),
    );
    unawaited(w.open(note!.id));
    await _settle(tester);
    await _type(tester, 'b c');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _run(tester);
    expect(w.search.status, PdfSearchStatus.done);
    final hit = w.search.hits.single;
    expect(hit.rects, hasLength(2));
    await tester.tap(find.text('1쪽'));
    await tester.pump();
    final focus = w.navigations.single.$2!;
    // Union of (15,10,5,5) and (5,20,5,5) in PDF pt = (5,10)-(20,25) → ×1.44.
    expect(focus.left, closeTo(7.2, 1e-6));
    expect(focus.top, closeTo(14.4, 1e-6));
    expect(focus.right, closeTo(28.8, 1e-6));
    expect(focus.bottom, closeTo(36, 1e-6));
    expect(focus, w.search.currentFocusRect);
    expect(focus, hit.rects[0].expandToInclude(hit.rects[1]));
    // The highlight of that page uses the same rects.
    expect(w.search.currentRectsFor(hit.pageId), hit.rects);
    await w.end(tester);
  });

  testWidgets('a hit without rects → onNavigate(pageId, null)', (tester) async {
    final engine = FakePdfEngine(
      texts: {
        0: const PdfPageTextData(
          pageIndex: 0,
          text: 'abc',
          charRects: [], // PDFium gave no boxes
        ),
      },
    );
    final w = _World(engine: engine);
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final note = await tester.runAsync(() => w.pdfNote([0]));
    unawaited(w.open(note!.id));
    await _settle(tester);
    await _type(tester, 'b');
    await tester.pump(const Duration(milliseconds: 300));
    await _run(tester);
    final hit = w.search.hits.single;
    expect(hit.rects, isEmpty);
    await tester.tap(find.text('1쪽'));
    await tester.pump();
    expect(w.navigations, [(hit.pageId, null)]);
    await w.end(tester);
  });

  testWidgets('no results / no PDF pages', (tester) async {
    final w = _World(engine: FakePdfEngine(texts: {0: _line(0, 'abc')}));
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final note = await tester.runAsync(() => w.pdfNote([0]));
    unawaited(w.open(note!.id));
    await _settle(tester);
    await _type(tester, 'zzz');
    await tester.pump(const Duration(milliseconds: 300));
    await _run(tester);
    expect(find.text('찾는 내용이 없어요'), findsOneWidget);

    final blank = await tester.runAsync(
      () => w.gateway.createNote(title: 'b', pages: [core.PageDraft.blankA4]),
    );
    await tester.tap(find.byTooltip('닫기'));
    await _settle(tester);
    unawaited(w.open(blank!.id));
    await _settle(tester);
    expect(find.text('찾는 내용이 없어요'), findsNothing); // another note's state
    await _type(tester, 'abc');
    await tester.pump(const Duration(milliseconds: 300));
    await _run(tester);
    expect(find.text('이 노트에는 PDF 페이지가 없어요'), findsOneWidget);
    await w.end(tester);
  });

  testWidgets('closing the panel cancels its search; reopening runs it again', (
    tester,
  ) async {
    final hold = Completer<void>();
    final engine = FakePdfEngine(
      pageCount: 3,
      texts: {for (var i = 0; i < 3; i++) i: _line(i, 'hit')},
    );
    final w = _World(engine: engine);
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final note = await tester.runAsync(() => w.pdfNote([0, 1, 2]));
    engine.beforeLoadText = (i) => i == 1 ? hold.future : Future.value();
    final panel = w.open(note!.id);
    await _settle(tester);
    await _type(tester, 'hit');
    await tester.pump(const Duration(milliseconds: 300));
    await _run(tester);
    expect(w.search.status, PdfSearchStatus.searching);
    expect(engine.loadTextCalls, [0, 1]);

    await tester.tap(find.byTooltip('닫기'));
    await _settle(tester);
    await panel;
    expect(w.search.status, PdfSearchStatus.idle);
    expect(w.search.query, 'hit');
    hold.complete();
    await _run(tester);
    expect(engine.loadTextCalls, [0, 1]); // page 3 never read
    expect(w.search.status, PdfSearchStatus.idle);

    // Reopened for the same note: the query is back and the search runs again.
    engine.beforeLoadText = null;
    unawaited(w.open(note.id));
    await _settle(tester);
    await _run(tester);
    expect(find.text('hit'), findsWidgets);
    expect(w.search.status, PdfSearchStatus.done);
    expect(w.search.hits, hasLength(3));
    await w.end(tester);
  });

  testWidgets(
    'PDF-3-1: delay text under 찾는 중 while the flush waits; closing cancels',
    (tester) async {
      final faults = core_testing.FakeNoteStoreFaults();
      final store = core_testing.createFakeNoteStore(faults: faults);
      final gateway = CorePdfNoteGateway(store);
      final w = _World(store: store, gateway: gateway);
      addTearDown(w.dispose);
      await tester.pumpWidget(w.app());
      final note = (await tester.runAsync(
        () => gateway.createNote(title: 'n', pages: [core.PageDraft.blankA4]),
      ))!;

      // A write that keeps failing: the pre-search flush waits behind it.
      faults.failNextCommits(5);
      final pendingWrite = gateway.createNote(
        title: 'later',
        pages: [core.PageDraft.blankA4],
      );
      final panel = w.open(note.id);
      await _settle(tester);
      await _type(tester, 'x');
      await tester.pump(const Duration(milliseconds: 300));
      expect(w.search.status, PdfSearchStatus.searching);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.textContaining('찾는 중'), findsOneWidget);
      expect(find.text(_delayText), findsOneWidget);
      // Below the progress text.
      expect(
        tester.getTopLeft(find.text(_delayText)).dy,
        greaterThan(tester.getTopLeft(find.textContaining('찾는 중')).dy),
      );

      await tester.tap(find.byTooltip('닫기'));
      await _settle(tester);
      await panel;
      expect(w.search.status, PdfSearchStatus.idle);

      // CORE's retry succeeds later; the cancelled search stays cancelled.
      await tester.pump(const Duration(seconds: 15));
      await pendingWrite;
      await _settle(tester);
      expect(w.search.status, PdfSearchStatus.idle);
      expect(w.engine.loadTextCalls, isEmpty);
      await w.end(tester);
    },
  );
}
