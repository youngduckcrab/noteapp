// Single export flow runPdfExportFlow (06-pdf 4.11, 6.11.2, 6.11.9, 6.12; 8 T16): option
// defaults, '선택한 페이지' disabled without a selection and the default with one, 현재
// 페이지, progress and '취소' (closes at once, no result sheet), result buttons = the sink's
// availableActions in purpose order, deliver called synchronously inside the tap handler,
// the needsUserGesture notice, the missing-original warning, the web large-original
// warning of the options sheet, and the storage-delay text while CORE retries a commit
// (PDF-3-1). Every test runs on an iPad Pro 13" view (contract 7.4.8); the options sheet
// (with and without the large-original warning), the progress dialog and the result sheet
// (each set of actions, the retry notice, the missing-original warning) meet the 44×44 /
// labeled tap-target guidelines, also in landscape.
//
// (2차, m5-7/06-pdf T26) v2: the result sheet lines of the three object warnings (images left
// out, text boxes as pictures, formulas left out) in portrait and landscape with the
// guidelines, and the web stop without fonts (S-12) → the fonts message, no result sheet — on
// the src-only createPdfExportService with fake raster ports and a fake font wait.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_service.dart';
import 'package:pdf_io/src/ui/export_sheets.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart';
import '../support/fake_rasterizers.dart';
import '../support/ipad.dart';

const String _delayText = '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.';

final class _World {
  /// (2차) [objects]: the export service is createPdfExportService over [objectsGateway] (page
  /// objects) with fake raster ports ([math] — formula 'm-bad' has no layout) and a fake font
  /// wait that ends with [fontsReady]; [web] runs the web rules.
  _World({
    FakePdfOutputSink? sink,
    core.NoteStore? store,
    PdfNoteGateway? gateway,
    bool objects = false,
    bool web = false,
    bool fontsReady = true,
  }) : sink = sink ?? FakePdfOutputSink(),
       store = store ?? core_testing.createFakeNoteStore() {
    this.gateway = gateway ?? FakePdfNoteGateway();
    container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(this.store),
        pdfNoteGatewayProvider.overrideWithValue(this.gateway),
        pdfComposeBackendProvider.overrideWithValue(backend),
        pdfInkVectorizerProvider.overrideWithValue(const BoxInkVectorizer()),
        pdfOutputSinkProvider.overrideWithValue(this.sink),
        if (objects)
          pdfExportServiceProvider.overrideWithValue(
            createPdfExportService(
              gateway: objectsGateway,
              vectorizer: const BoxInkVectorizer(),
              backend: backend,
              math: FakeMathRasterizer(layoutSizes: {'m-bad': null}),
              text: FakeTextRasterizer(),
              loadFonts: () async {
                if (!fontsReady) throw TimeoutException('fake font load');
              },
              fontBytes: FakeFontSource().call,
              web: web,
            ),
          ),
      ],
    );
  }

  late final ObjectsGateway objectsGateway = ObjectsGateway(fake);

  final FakePdfOutputSink sink;
  final core.NoteStore store;
  final RecordingComposeBackend backend = RecordingComposeBackend();
  late final PdfNoteGateway gateway;
  late final ProviderContainer container;
  late BuildContext context;

  FakePdfNoteGateway get fake => gateway as FakePdfNoteGateway;

  PdfJobState<PdfExportResult> get job => container.read(pdfExportJobProvider);

  /// A note of [pageCount] blank pages with one stroke each; returns its id and page ids.
  Future<(core.NoteId, List<core.PageId>)> note(
    String title, {
    int pageCount = 3,
  }) async {
    final note = await gateway.createNote(
      title: title,
      pages: [for (var i = 0; i < pageCount; i++) blankDraft],
    );
    final pages = await gateway.pagesOf(note.id);
    for (final page in pages) {
      fake.addStrokes(page.id, [testStroke('s-${page.id}', page.id)]);
    }
    return (note.id, [for (final p in pages) p.id]);
  }

  /// [screenTheme]: a Theme around the calling screen only (v2.14-ui split: the
  /// editor's style inside a note) — the progress dialog must take it, not the app's.
  Widget app({ThemeData? screenTheme}) {
    Widget screen = Builder(
      builder: (context) {
        this.context = context;
        return const SizedBox.expand();
      },
    );
    if (screenTheme != null) screen = Theme(data: screenTheme, child: screen);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: screen)),
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await store.close();
  }
}

/// Lets sheets / dialogs animate in or out.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _inSheet(Finder finder) =>
    find.descendant(of: find.byType(BottomSheet), matching: finder);

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

RadioListTile<Object?> _radio(WidgetTester tester, String label) =>
    tester.widget(
      find.ancestor(
        of: _inSheet(find.text(label)),
        matching: find.byWidgetPredicate((w) => w is RadioListTile<Object?>),
      ),
    ) as RadioListTile<Object?>;

/// The range chosen on the options sheet ('all' / 'current' / 'selected').
String _chosenRange(WidgetTester tester) {
  final group = tester.widget(
    _inSheet(find.byWidgetPredicate((w) => w is RadioGroup<Object?>)),
  ) as RadioGroup<Object?>;
  return (group.groupValue! as Enum).name;
}

bool _switchOn(WidgetTester tester, String label) => tester
    .widget<SwitchListTile>(
      _inSheet(find.widgetWithText(SwitchListTile, label)),
    )
    .value;

/// A tap delivered synchronously (no await between the pointer events and the check), so
/// whatever the tap handler does before its first await has happened when this returns.
void _tapNow(WidgetTester tester, Finder finder) {
  final at = tester.getCenter(finder);
  tester.binding.handlePointerEvent(
    PointerDownEvent(pointer: 77, position: at),
  );
  tester.binding.handlePointerEvent(PointerUpEvent(pointer: 77, position: at));
}

/// Opens the options sheet, taps '내보내기' and lets the export run to its result sheet.
Future<Future<PdfExportResult?>> _export(
  WidgetTester tester,
  _World w,
  core.NoteId noteId, {
  String? currentPageId,
  List<String> selectedPageIds = const [],
  PdfExportPurpose purpose = PdfExportPurpose.save,
  String? range,
}) async {
  final flow = runPdfExportFlow(
    w.context,
    noteId: noteId,
    currentPageId: currentPageId,
    selectedPageIds: selectedPageIds,
    purpose: purpose,
  );
  await _settle(tester);
  if (range != null) {
    await tester.tap(_inSheet(find.text(range)));
    await tester.pump();
  }
  await tester.tap(_inSheet(find.text('내보내기')));
  await _settle(tester);
  return flow;
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tap(_inSheet(find.text('닫기')));
  await _settle(tester);
}

void main() {
  testWidgets('defaults: 노트 전체, 필기·속지 포함; without selection or current page '
      'those ranges are disabled', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('미적분 3강');

    final flow = runPdfExportFlow(w.context, noteId: id);
    await _settle(tester);
    expect(_inSheet(find.text('PDF로 내보내기')), findsOneWidget);
    expect(_inSheet(find.text('미적분 3강')), findsOneWidget);
    expect(_chosenRange(tester), 'all');
    expect(_inSheet(find.text('3쪽')), findsOneWidget);
    expect(_radio(tester, '노트 전체').enabled, isNot(isFalse));
    expect(_radio(tester, '현재 페이지').enabled, isFalse);
    expect(_radio(tester, '선택한 페이지').enabled, isFalse);
    expect(_switchOn(tester, '필기 포함'), isTrue);
    expect(_switchOn(tester, '속지 포함'), isTrue);
    await expectTapTargetGuidelines(tester);
    // A disabled range cannot be chosen.
    await tester.tap(_inSheet(find.text('선택한 페이지')));
    await tester.pump();
    expect(_chosenRange(tester), 'all');

    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_inSheet(find.text('PDF를 만들었어요')), findsOneWidget);
    expect(_inSheet(find.textContaining('미적분 3강.pdf')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    expect(w.backend.plans.single.pages, hasLength(3));
    expect(w.backend.chunks, isNotEmpty, reason: 'ink included');
    await _closeSheet(tester);
    final result = await flow;
    expect(result!.fileName, '미적분 3강.pdf');
    expect(result.pageCount, 3);
    expect(w.job, PdfJobSucceeded<PdfExportResult>(result));
  });

  testWidgets('a selection is the default range (note order); 현재 페이지 → (p{n})', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, pages) = await w.note('n', pageCount: 4);

    final flow = runPdfExportFlow(
      w.context,
      noteId: id,
      currentPageId: pages[2],
      selectedPageIds: [pages[3], 'not-a-page', pages[1]],
    );
    await _settle(tester);
    expect(_chosenRange(tester), 'selected');
    expect(_radio(tester, '선택한 페이지').enabled, isNot(isFalse));
    expect(_inSheet(find.text('2쪽')), findsOneWidget); // two pages selected
    expect(
      _inSheet(find.text('3쪽')),
      findsOneWidget,
    ); // the current page number
    await expectTapTargetGuidelines(tester);
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(_inSheet(find.textContaining('n (선택 2쪽).pdf')), findsOneWidget);
    expect(w.backend.plans.single.pages, hasLength(2));
    await _closeSheet(tester);
    expect((await flow)!.fileName, 'n (선택 2쪽).pdf');

    final current = await _export(
      tester,
      w,
      id,
      currentPageId: pages[2],
      range: '현재 페이지',
    );
    expect(_inSheet(find.textContaining('n (p3).pdf')), findsOneWidget);
    await _closeSheet(tester);
    expect((await current)!.pageCount, 1);

    // Only ids that are not pages of the note: 선택한 페이지 disabled, 노트 전체 default.
    final none = runPdfExportFlow(
      w.context,
      noteId: id,
      selectedPageIds: const ['elsewhere'],
    );
    await _settle(tester);
    expect(_chosenRange(tester), 'all');
    expect(_radio(tester, '선택한 페이지').enabled, isFalse);
    await tester.tap(_inSheet(find.text('취소')));
    await _settle(tester);
    expect(await none, isNull);
  });

  testWidgets('필기 포함 off → no ink ops', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('n', pageCount: 2);
    final flow = runPdfExportFlow(w.context, noteId: id);
    await _settle(tester);
    await tester.tap(_inSheet(find.text('필기 포함')));
    await tester.pump();
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(w.backend.chunks, isEmpty);
    await _closeSheet(tester);
    await flow;
  });

  testWidgets('progress, then 취소: the dialog closes at once, no result sheet', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('n');
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;

    final flow = runPdfExportFlow(w.context, noteId: id);
    await _settle(tester);
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(_inDialog(find.text('PDF 만드는 중')), findsOneWidget);
    expect(_inDialog(find.textContaining('페이지 합성 중')), findsOneWidget);
    expect(_inDialog(find.text('취소')), findsOneWidget);
    expect(_inDialog(find.text('닫기')), findsNothing);
    expect(find.text(_delayText), findsNothing);
    await expectTapTargetGuidelines(tester);

    await tester.tap(_inDialog(find.text('취소')));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    await _settle(tester);
    expect(await flow, isNull);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      w.job,
      const PdfJobFailed<PdfExportResult>(
        PdfIoException(PdfErrorCode.cancelled),
      ),
    );
    expect(w.backend.events, contains('abort#1'));
    expect(w.backend.openJobCount, 0);
    hold.complete();
  });

  testWidgets(
    'result buttons = availableActions; deliver runs inside the tap handler',
    (tester) async {
      final w = _World(sink: FakePdfOutputSink(canShare: false));
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app());
      final (id, _) = await w.note('n');
      final flow = await _export(tester, w, id);

      // Desktop Chrome: no file sharing.
      expect(_inSheet(find.text('공유')), findsNothing);
      expect(_inSheet(find.text('다운로드')), findsOneWidget);
      expect(_inSheet(find.text('새 탭에서 열기')), findsOneWidget);
      expect(w.sink.availableActionsCalls.last.single.fileName, 'n.pdf');
      await expectTapTargetGuidelines(tester);

      _tapNow(tester, _inSheet(find.text('다운로드')));
      // No pump, no await: the sink got the file during the tap itself (6.12).
      expect(w.sink.deliveries, hasLength(1));
      expect(w.sink.deliveries.single.$2, PdfOutputAction.download);
      expect(w.sink.deliveries.single.$1.single.fileName, 'n.pdf');
      await tester.pump();
      _tapNow(tester, _inSheet(find.text('새 탭에서 열기')));
      expect(w.sink.deliveries.last.$2, PdfOutputAction.openInNewTab);
      await tester.pump();
      await _closeSheet(tester);
      await flow;
    },
  );

  testWidgets('iPad Safari: 공유 first; needsUserGesture → 한 번 더 눌러 주세요', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('n');
    final flow = await _export(tester, w, id);
    double x(String label) => tester.getTopLeft(_inSheet(find.text(label))).dx;
    expect(x('공유'), lessThan(x('다운로드')));
    expect(x('다운로드'), lessThan(x('새 탭에서 열기')));
    await expectTapTargetGuidelines(tester);

    w.sink.enqueueOutcome(PdfOutputOutcome.needsUserGesture);
    await tester.tap(_inSheet(find.text('공유')));
    await tester.pump();
    expect(_inSheet(find.text('한 번 더 눌러 주세요')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    w.sink.enqueueOutcome(PdfOutputOutcome.dismissedByUser);
    await tester.tap(_inSheet(find.text('공유')));
    await tester.pump();
    expect(_inSheet(find.text('한 번 더 눌러 주세요')), findsNothing);
    w.sink.enqueueOutcome(PdfOutputOutcome.failed);
    await tester.tap(_inSheet(find.text('다운로드')));
    await tester.pump();
    expect(_inSheet(find.text('파일을 넘기지 못했어요. 다시 시도해 주세요.')), findsOneWidget);
    expect(
      [for (final d in w.sink.deliveries) d.$2],
      [PdfOutputAction.share, PdfOutputAction.share, PdfOutputAction.download],
    );
    await _closeSheet(tester);
    await flow;
  });

  testWidgets('print: 공유 with the print hint, then 새 탭에서 열기', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('n');
    final flow = runPdfExportFlow(
      w.context,
      noteId: id,
      purpose: PdfExportPurpose.print,
    );
    await _settle(tester);
    expect(_inSheet(find.text('인쇄')), findsOneWidget);
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(_inSheet(find.text('공유 시트에서 프린트를 고르세요')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    double x(String label) => tester.getTopLeft(_inSheet(find.text(label))).dx;
    expect(x('공유'), lessThan(x('새 탭에서 열기')));
    expect(x('새 탭에서 열기'), lessThan(x('다운로드')));
    await _closeSheet(tester);
    await flow;

    // No file sharing: print from the PDF opened in a new tab.
    w.sink.canShare = false;
    final again = await _export(tester, w, id, purpose: PdfExportPurpose.print);
    expect(_inSheet(find.text('새 탭에서 PDF를 열어 인쇄하세요')), findsOneWidget);
    expect(x('새 탭에서 열기'), lessThan(x('다운로드')));
    await _closeSheet(tester);
    await again;

    // share purpose: the title only differs.
    final share = runPdfExportFlow(
      w.context,
      noteId: id,
      purpose: PdfExportPurpose.share,
    );
    await _settle(tester);
    expect(_inSheet(find.text('PDF 공유')), findsOneWidget);
    await tester.tap(_inSheet(find.text('취소')));
    await _settle(tester);
    expect(await share, isNull);
  });

  testWidgets('missing originals: the warning line under the file', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    const remote = 'f00dfeed';
    w.fake.addRemoteAsset(remote, fileName: 'remote.pdf');
    final note = await w.gateway.createNote(
      title: 'n',
      pages: const [
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.PdfBackground(assetId: remote, pdfPageIndex: 0),
        ),
        blankDraft,
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.PdfBackground(assetId: remote, pdfPageIndex: 1),
        ),
      ],
    );
    final flow = await _export(tester, w, note.id);
    expect(_inSheet(find.text('PDF를 만들었어요')), findsOneWidget);
    expect(_inSheet(find.text('1, 3쪽은 원본이 없어 빈 페이지로 넣었어요')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await _closeSheet(tester);
    final result = await flow;
    expect(result!.warnings.single, isA<PdfExportBlankedMissingAsset>());
  });

  testWidgets(
    'web large-original warning of the options sheet follows the range',
    (tester) async {
      final w = _World();
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app());
      const big = 'b16b16';
      w.fake.addRemoteAsset(big, fileName: 'big.pdf');
      final note = await w.gateway.createNote(
        title: 'n',
        pages: const [
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: big, pdfPageIndex: 0),
          ),
          blankDraft,
        ],
      );
      final pages = await w.gateway.pagesOf(note.id);
      const warning = '원본 PDF가 151MB예요. 기기 메모리가 부족하면 내보내기가 멈출 수 있어요.';
      final options = showPdfExportOptionsSheet(
        w.context,
        title: 'PDF로 내보내기',
        pages: pages,
        currentPageId: pages[1].id,
        sourceSizes: const {big: 151 * 1024 * 1024},
      );
      await _settle(tester);
      expect(_inSheet(find.text(warning)), findsOneWidget);
      await expectTapTargetGuidelines(tester);
      // The current page has no PDF original.
      await tester.tap(_inSheet(find.text('현재 페이지')));
      await tester.pump();
      expect(_inSheet(find.text(warning)), findsNothing);
      await tester.tap(_inSheet(find.text('노트 전체')));
      await tester.pump();
      // A warning only: 내보내기 still works.
      await tester.tap(_inSheet(find.text('내보내기')));
      await _settle(tester);
      final chosen = await options;
      expect(chosen!.range, isA<PdfExportAllPages>());
      expect(chosen.includeInk, isTrue);
      expect(chosen.includeTemplates, isTrue);
      expect(chosen.missingAssetPolicy, PdfMissingAssetPolicy.blankPage);
      expect(chosen.fileName, isNull);

      // At the limit: no warning.
      final atLimit = showPdfExportOptionsSheet(
        w.context,
        title: 'PDF로 내보내기',
        pages: pages,
        sourceSizes: const {big: 150 * 1024 * 1024},
      );
      await _settle(tester);
      expect(_inSheet(find.textContaining('원본 PDF가')), findsNothing);
      await tester.tap(_inSheet(find.text('취소')));
      await _settle(tester);
      expect(await atLimit, isNull);
    },
  );

  testWidgets('busy and a missing note → a snack bar, no sheet', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('n');

    expect(await runPdfExportFlow(w.context, noteId: 'note-404'), isNull);
    await tester.pump();
    expect(find.text('노트를 찾을 수 없어요.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await _settle(tester);
    ScaffoldMessenger.of(w.context).removeCurrentSnackBar();
    await _settle(tester);

    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;
    final batch = w.container.read(pdfBatchExportJobProvider.notifier).run([
      id,
    ], const PdfExportOptions());
    await tester.pump();
    expect(await runPdfExportFlow(w.context, noteId: id), isNull);
    await tester.pump();
    expect(find.text('다른 PDF 작업이 진행 중이에요.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    hold.complete();
    await tester.pump();
    await batch;
  });

  testWidgets('the caller unmounted midway → quietly null, job cancelled', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final (id, _) = await w.note('n');
    final navigator = Navigator.of(w.context);
    late BuildContext pageContext;
    final page = MaterialPageRoute<void>(
      builder: (context) {
        pageContext = context;
        return const Scaffold(body: SizedBox.expand());
      },
    );
    unawaited(navigator.push(page));
    await _settle(tester);
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;
    final flow = runPdfExportFlow(pageContext, noteId: id);
    await _settle(tester);
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(_inDialog(find.text('PDF 만드는 중')), findsOneWidget);

    navigator.removeRoute(page);
    await _settle(tester);
    expect(await flow, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      w.job,
      const PdfJobFailed<PdfExportResult>(
        PdfIoException(PdfErrorCode.cancelled),
      ),
    );
    expect(w.backend.openJobCount, 0);
    expect(tester.takeException(), isNull);
    hold.complete();
  });

  testWidgets(
    'PDF-3-1 storage delay: delay text while the flush waits, no 닫기; 취소 closes',
    (tester) async {
      final faults = core_testing.FakeNoteStoreFaults();
      final store = core_testing.createFakeNoteStore(faults: faults);
      final w = _World(store: store, gateway: CorePdfNoteGateway(store));
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app());
      final note = await w.gateway.createNote(
        title: 'n',
        pages: const [blankDraft],
      );

      final flow = runPdfExportFlow(w.context, noteId: note.id);
      await _settle(tester);
      // Every commit fails for a while: a write waits, and so does the pre-export flush.
      faults.failNextCommits(5);
      unawaited(
        w.gateway
            .createNote(title: 'later', pages: const [blankDraft])
            .then((_) {}),
      );
      await tester.tap(_inSheet(find.text('내보내기')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_inDialog(find.text('PDF 만드는 중')), findsOneWidget);
      expect(_inDialog(find.text('내보낼 준비 중')), findsOneWidget);
      expect(find.text(_delayText), findsOneWidget);
      expect(_inDialog(find.text('닫기')), findsNothing);
      await expectTapTargetGuidelines(tester);

      await tester.tap(_inDialog(find.text('취소')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      await _settle(tester);
      expect(await flow, isNull);
      expect(find.byType(BottomSheet), findsNothing);
      expect(w.backend.plans, isEmpty);
      expect(
        w.job,
        const PdfJobFailed<PdfExportResult>(
          PdfIoException(PdfErrorCode.cancelled),
        ),
      );
      await tester.pump(
        const Duration(seconds: 15),
      ); // CORE's retry succeeds later
      await _settle(tester);
    },
  );

  testWidgets('landscape 1376×1032: options, progress and result meet the '
      'tap-target guidelines', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app(), landscape: true);
    expect(
      tester.view.physicalSize / tester.view.devicePixelRatio,
      ipad13Landscape,
    );
    final (id, pages) = await w.note('n', pageCount: 3);
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;

    final flow = runPdfExportFlow(
      w.context,
      noteId: id,
      currentPageId: pages[0],
      selectedPageIds: [pages[1]],
    );
    await _settle(tester);
    expect(_inSheet(find.text('PDF로 내보내기')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(_inDialog(find.text('PDF 만드는 중')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    hold.complete();
    await _settle(tester);
    expect(_inSheet(find.text('PDF를 만들었어요')), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await _closeSheet(tester);
    expect(await flow, isNotNull);
  });

  group('(2차) object warnings and the fonts stop (T26)', () {
    /// Page 1: a box NoteSans does not cover (raster), page 2: an image without bytes, page 3:
    /// an invalid formula, page 4: an ordinary box.
    Future<core.NoteId> objectNote(_World w) async {
      w.fake.addRemoteAsset('remote');
      final note = await w.gateway.createNote(
        title: '객체 노트',
        pages: [for (var i = 0; i < 4; i++) blankDraft],
      );
      final pages = await w.gateway.pagesOf(note.id);
      core.ElementFrame frame(double top) =>
          core.ElementFrame(core.PageRect(60, top, 360, top + 60));
      w.objectsGateway
        ..addObjects(pages[0].id, [
          core.TextBoxObject(
            id: 't-emoji',
            pageId: pages[0].id,
            frame: frame(100),
            text: '웃음 \u{1F600}',
            style: const core.TextBoxStyle(),
            createdAt: 1,
          ),
        ])
        ..addObjects(pages[1].id, [
          core.ImageObject(
            id: 'i',
            pageId: pages[1].id,
            frame: frame(100),
            assetId: 'remote',
            pixelWidth: 64,
            pixelHeight: 48,
            createdAt: 2,
          ),
        ])
        ..addObjects(pages[2].id, [
          core.MathObject(
            id: 'm-bad',
            pageId: pages[2].id,
            frame: frame(100),
            latex: r'\frac{',
            style: const core.MathStyle(),
            createdAt: 3,
          ),
        ])
        ..addObjects(pages[3].id, [
          core.TextBoxObject(
            id: 't-ok',
            pageId: pages[3].id,
            frame: frame(100),
            text: '보통 글자',
            style: const core.TextBoxStyle(),
            createdAt: 4,
          ),
        ]);
      return note.id;
    }

    const lines = [
      '2쪽의 이미지는 이 기기에 원본이 없거나 읽지 못해 빠졌어요',
      '1쪽의 텍스트 상자 일부는 그림으로 넣었어요 — PDF에서 검색되지 않아요',
      '3쪽의 수식 일부를 그리지 못해 빠졌어요',
    ];

    for (final landscape in [false, true]) {
      testWidgets('the three warning lines under the file '
          '(${landscape ? 'landscape' : 'portrait'}), guidelines met', (
        tester,
      ) async {
        final w = _World(objects: true);
        addTearDown(w.dispose);
        await pumpOnIpad(tester, w.app(), landscape: landscape);
        final id = await objectNote(w);
        final flow = await _export(tester, w, id);
        expect(_inSheet(find.text('PDF를 만들었어요')), findsOneWidget);
        // the file's subtitle: one line per warning (6.16 · 1차 warningLines)
        expect(_inSheet(find.text(lines.join('\n'))), findsOneWidget);
        await expectTapTargetGuidelines(tester);
        await _closeSheet(tester);
        final result = await flow;
        expect(warningLines(result!), lines);
        expect(
          [for (final p in w.backend.parts) p.texts],
          [
            <String>[],
            ['보통 글자'],
          ],
          reason: 'the raster, then the text object of page 4',
        );
      });
    }

    testWidgets('web without fonts, a Hangul box → the fonts message, no '
        'result sheet, nothing composed (S-12)', (tester) async {
      final w = _World(objects: true, web: true, fontsReady: false);
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app());
      final id = await objectNote(w);
      final flow = runPdfExportFlow(w.context, noteId: id);
      await _settle(tester);
      await tester.tap(_inSheet(find.text('내보내기')));
      await _settle(tester);
      expect(await flow, isNull);
      expect(
        find.text('글꼴을 받지 못해 내보낼 수 없어요. 인터넷에 연결한 뒤 다시 해 주세요.'),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(w.backend.events, isEmpty);
      expect(
        w.job,
        const PdfJobFailed<PdfExportResult>(
          PdfIoException(
            PdfErrorCode.exportFailed,
            detail: 'fonts-unavailable',
          ),
        ),
      );
      await expectTapTargetGuidelines(tester);
      await _settle(tester);
    });
  });

  test('VM platform sink = the native sink: 저장 (download) for one file, '
      '공유 only with the app\'s share', () {
    final result = PdfExportResult(
      bytes: Uint8List(4),
      fileName: 'n.pdf',
      pageCount: 1,
      elapsed: Duration.zero,
    );
    final sink = createPlatformOutputSink();
    expect(sink.availableActions([result]), {PdfOutputAction.download});
    expect(sink.availableActions([result, result]), isEmpty);
    expect(
      () => sink.deliver([result], PdfOutputAction.openInNewTab),
      throwsArgumentError,
    );
    final sharing = createPlatformOutputSink(
      share: (_) async => PdfOutputOutcome.done,
    );
    expect(sharing.availableActions([result]), {
      PdfOutputAction.share,
      PdfOutputAction.download,
    });
  });

  testWidgets(
    '(v2.14-ui) the progress dialog takes the calling screen\'s theme',
    (tester) async {
      final w = _World();
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app(screenTheme: _screenTheme));
      final (id, _) = await w.note('n');
      final hold = Completer<void>();
      w.backend.beforeAddPages = () => hold.future;

      final flow = runPdfExportFlow(w.context, noteId: id);
      await _settle(tester);
      await tester.tap(_inSheet(find.text('내보내기')));
      await _settle(tester);
      expect(find.byType(PdfExportProgressDialog), findsOneWidget);
      expect(
        _dialogScheme(tester, PdfExportProgressDialog).primary,
        _screenTheme.colorScheme.primary,
      );
      await tester.tap(_inDialog(find.text('취소')));
      await _settle(tester);
      expect(await flow, isNull);
      hold.complete();
    },
  );
}

/// (v2.14-ui split) A screen theme unlike the app's default one.
final ThemeData _screenTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
);

/// The colour scheme the progress dialog [type] is drawn with.
ColorScheme _dialogScheme(WidgetTester tester, Type type) =>
    Theme.of(tester.element(find.byType(type))).colorScheme;
