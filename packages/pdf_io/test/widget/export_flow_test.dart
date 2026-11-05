// Single export flow runPdfExportFlow (06-pdf 4.11, 6.11.2, 6.11.9, 6.12; 8 T16): option
// defaults, '선택한 페이지' disabled without a selection and the default with one, 현재
// 페이지, progress and '취소' (closes at once, no result sheet), result buttons = the sink's
// availableActions in purpose order, deliver called synchronously inside the tap handler,
// the needsUserGesture notice, the missing-original warning, the web large-original
// warning of the options sheet, and the storage-delay text while CORE retries a commit
// (PDF-3-1).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/ui/export_sheets.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart';

const String _delayText = '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.';

final class _World {
  _World({
    FakePdfOutputSink? sink,
    core.NoteStore? store,
    PdfNoteGateway? gateway,
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
      ],
    );
  }

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
    await tester.pumpWidget(w.app());
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
    // A disabled range cannot be chosen.
    await tester.tap(_inSheet(find.text('선택한 페이지')));
    await tester.pump();
    expect(_chosenRange(tester), 'all');

    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_inSheet(find.text('PDF를 만들었어요')), findsOneWidget);
    expect(_inSheet(find.textContaining('미적분 3강.pdf')), findsOneWidget);
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
    await tester.pumpWidget(w.app());
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
    await tester.pumpWidget(w.app());
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
    await tester.pumpWidget(w.app());
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
      await tester.pumpWidget(w.app());
      final (id, _) = await w.note('n');
      final flow = await _export(tester, w, id);

      // Desktop Chrome: no file sharing.
      expect(_inSheet(find.text('공유')), findsNothing);
      expect(_inSheet(find.text('다운로드')), findsOneWidget);
      expect(_inSheet(find.text('새 탭에서 열기')), findsOneWidget);
      expect(w.sink.availableActionsCalls.last.single.fileName, 'n.pdf');

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
    await tester.pumpWidget(w.app());
    final (id, _) = await w.note('n');
    final flow = await _export(tester, w, id);
    double x(String label) => tester.getTopLeft(_inSheet(find.text(label))).dx;
    expect(x('공유'), lessThan(x('다운로드')));
    expect(x('다운로드'), lessThan(x('새 탭에서 열기')));

    w.sink.enqueueOutcome(PdfOutputOutcome.needsUserGesture);
    await tester.tap(_inSheet(find.text('공유')));
    await tester.pump();
    expect(_inSheet(find.text('한 번 더 눌러 주세요')), findsOneWidget);
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
    await tester.pumpWidget(w.app());
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
    await tester.pumpWidget(w.app());
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
    await _closeSheet(tester);
    final result = await flow;
    expect(result!.warnings.single, isA<PdfExportBlankedMissingAsset>());
  });

  testWidgets(
    'web large-original warning of the options sheet follows the range',
    (tester) async {
      final w = _World();
      addTearDown(w.dispose);
      await tester.pumpWidget(w.app());
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
    await tester.pumpWidget(w.app());
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
    await tester.pumpWidget(w.app());
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
      await tester.pumpWidget(w.app());
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

  test('VM platform sink: nothing to deliver → unsupported', () async {
    final sink = createPlatformOutputSink();
    final result = PdfExportResult(
      bytes: Uint8List(4),
      fileName: 'n.pdf',
      pageCount: 1,
      elapsed: Duration.zero,
    );
    expect(sink.availableActions([result]), isEmpty);
    expect(
      await sink.deliver([result], PdfOutputAction.download),
      PdfOutputOutcome.unsupported,
    );
  });
}
