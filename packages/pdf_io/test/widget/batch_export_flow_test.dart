// Bulk export flow exportNotesAsPdf (06-pdf 4.11, 6.12, 6.12.1; 8 T15b, PDF-S3): empty list
// → nothing, options sheet → progress dialog → result sheet, '모두 공유' hands every file to
// the sink in one call, per-file '다운로드' without file sharing, the failed-note list, one
// note → its title and the single-file buttons, cancel keeps the files made, an unmounted
// context ends quietly, and the storage-delay text while CORE retries a commit (PDF-3-1).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
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

  PdfBatchJobState get job => container.read(pdfBatchExportJobProvider);

  /// Notes of one blank page with one stroke each.
  Future<List<core.NoteId>> notes(List<String> titles) async {
    final ids = <core.NoteId>[];
    for (final title in titles) {
      final note = await gateway.createNote(
        title: title,
        pages: const [blankDraft],
      );
      final page = (await gateway.pagesOf(note.id)).single;
      fake.addStrokes(page.id, [testStroke('s-${note.id}', page.id)]);
      ids.add(note.id);
    }
    return ids;
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

/// Opens the options sheet of [ids] and taps '내보내기'.
Future<(Future<void>,)> _start(
  WidgetTester tester,
  _World w,
  List<String> ids, {
  BuildContext? context,
}) async {
  final flow = exportNotesAsPdf(context ?? w.context, ids);
  await _settle(tester);
  await tester.tap(_inSheet(find.text('내보내기')));
  await _settle(tester);
  return (flow,);
}

void main() {
  testWidgets('an empty list does nothing', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    await exportNotesAsPdf(w.context, const []);
    await _settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(w.fake.calls, isEmpty);
    expect(w.job, const PdfBatchJobIdle());
  });

  testWidgets('options → progress → result; 모두 공유 hands all three files over', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['수학', '영어', '과학']);
    final hold = Completer<void>();
    w.backend.beforeFinish = () =>
        w.backend.plans.length == 1 ? hold.future : Future<void>.value();

    final flow = exportNotesAsPdf(w.context, ids);
    await _settle(tester);
    expect(_inSheet(find.text('PDF로 내보내기 · 노트 3개')), findsOneWidget);
    expect(_inSheet(find.text('필기 포함')), findsOneWidget);
    expect(_inSheet(find.text('속지 포함')), findsOneWidget);
    // '필기 포함' off → no ink ops.
    await tester.tap(_inSheet(find.text('필기 포함')));
    await tester.pump();
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);

    expect(_inDialog(find.text('PDF 만드는 중')), findsOneWidget);
    expect(_inDialog(find.text('노트 1/3 · PDF 마무리 중 (1/1)')), findsOneWidget);
    expect(_inDialog(find.text('취소')), findsOneWidget);
    expect(find.text(_delayText), findsNothing);
    hold.complete();
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(w.backend.chunks, isEmpty, reason: 'includeInk false');
    expect(_inSheet(find.text('노트 3개 중 3개를 PDF로 만들었어요')), findsOneWidget);
    for (final name in ['수학.pdf', '영어.pdf', '과학.pdf']) {
      expect(_inSheet(find.textContaining(name)), findsOneWidget);
    }
    expect(_inSheet(find.text('다운로드')), findsNWidgets(3));
    await tester.tap(_inSheet(find.text('모두 공유')));
    await tester.pump();
    final (results, action) = w.sink.deliveries.single;
    expect(action, PdfOutputAction.share);
    expect(
      [for (final r in results) r.fileName],
      ['수학.pdf', '영어.pdf', '과학.pdf'],
    );
    // The sink was asked about the whole list (navigator.canShare with every file).
    expect(w.sink.availableActionsCalls.first, hasLength(3));

    await tester.tap(_inSheet(find.text('닫기')));
    await _settle(tester);
    await flow;
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('no file sharing → a 다운로드 button per file, one file per tap', (
    tester,
  ) async {
    final w = _World(sink: FakePdfOutputSink(canShare: false));
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['a', 'b', 'c']);
    final (flow,) = await _start(tester, w, ids);
    expect(_inSheet(find.text('모두 공유')), findsNothing);
    expect(_inSheet(find.text('공유')), findsNothing);
    expect(_inSheet(find.text('다운로드')), findsNWidgets(3));
    await tester.tap(_inSheet(find.text('다운로드')).at(1));
    await tester.pump();
    final (results, action) = w.sink.deliveries.single;
    expect(action, PdfOutputAction.download);
    expect(results.single.fileName, 'b.pdf');
    await tester.tap(_inSheet(find.text('닫기')));
    await _settle(tester);
    await flow;
  });

  testWidgets('failed notes are listed under the summary', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['a']);
    final (flow,) = await _start(tester, w, [ids.single, 'note-404']);
    expect(_inSheet(find.text('노트 2개 중 1개를 PDF로 만들었어요')), findsOneWidget);
    expect(_inSheet(find.text('만들지 못한 노트')), findsOneWidget);
    expect(_inSheet(find.text('노트: 노트를 찾을 수 없어요.')), findsOneWidget);
    // One file left: still the bulk layout (2 notes asked) — share it or download it.
    expect(_inSheet(find.textContaining('a.pdf')), findsOneWidget);
    await tester.tap(_inSheet(find.text('닫기')));
    await _settle(tester);
    await flow;
  });

  testWidgets('one note: its title, then the single-file buttons', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['미적분 3강']);
    final flow = exportNotesAsPdf(w.context, ids);
    await _settle(tester);
    expect(_inSheet(find.text('미적분 3강')), findsOneWidget);
    await tester.tap(_inSheet(find.text('내보내기')));
    await _settle(tester);

    expect(_inSheet(find.text('PDF를 만들었어요')), findsOneWidget);
    expect(_inSheet(find.textContaining('미적분 3강.pdf')), findsOneWidget);
    expect(_inSheet(find.text('공유')), findsOneWidget);
    expect(_inSheet(find.text('다운로드')), findsOneWidget);
    expect(_inSheet(find.text('새 탭에서 열기')), findsOneWidget);
    expect(_inSheet(find.text('모두 공유')), findsNothing);

    // Safari: the user activation expired → '한 번 더 눌러 주세요'.
    w.sink.enqueueOutcome(PdfOutputOutcome.needsUserGesture);
    await tester.tap(_inSheet(find.text('공유')));
    await tester.pump();
    expect(_inSheet(find.text('한 번 더 눌러 주세요')), findsOneWidget);
    await tester.tap(_inSheet(find.text('새 탭에서 열기')));
    await tester.pump();
    expect(_inSheet(find.text('한 번 더 눌러 주세요')), findsNothing);
    expect(
      [for (final d in w.sink.deliveries) d.$2],
      [PdfOutputAction.share, PdfOutputAction.openInNewTab],
    );
    expect(w.sink.deliveries.last.$1.single.fileName, '미적분 3강.pdf');
    await tester.tap(_inSheet(find.text('닫기')));
    await _settle(tester);
    await flow;
  });

  testWidgets('취소 keeps the files made: result sheet with the cancel notice', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['a', 'b', 'c']);
    final hold = Completer<void>();
    w.backend.beforeAddPages = () =>
        w.backend.plans.length == 2 ? hold.future : Future<void>.value();
    final (flow,) = await _start(tester, w, ids);
    expect(_inDialog(find.textContaining('노트 2/3')), findsOneWidget);
    await tester.tap(_inDialog(find.text('취소')));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(_inSheet(find.text('노트 3개 중 1개를 PDF로 만들었어요')), findsOneWidget);
    expect(_inSheet(find.text('취소해서 나머지 2개는 만들지 않았어요')), findsOneWidget);
    expect(w.backend.events, contains('abort#2'));
    await tester.tap(_inSheet(find.text('닫기')));
    await _settle(tester);
    await flow;
    hold.complete();
  });

  testWidgets('취소 before any file → no result sheet', (tester) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['a', 'b']);
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;
    final (flow,) = await _start(tester, w, ids);
    await tester.tap(_inDialog(find.text('취소')));
    await _settle(tester);
    await flow;
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(w.job, isA<PdfBatchJobFinished>());
    hold.complete();
  });

  testWidgets(
    'the caller unmounted midway → the flow ends quietly, job cancelled',
    (tester) async {
      final w = _World();
      addTearDown(w.dispose);
      await tester.pumpWidget(w.app());
      final ids = await w.notes(['a', 'b']);
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
      final (flow,) = await _start(tester, w, ids, context: pageContext);
      expect(_inDialog(find.text('PDF 만드는 중')), findsOneWidget);

      navigator.removeRoute(page);
      await _settle(tester);
      await flow;
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      final job = w.job;
      expect(job, isA<PdfBatchJobFinished>());
      expect((job as PdfBatchJobFinished).result.cancelled, isTrue);
      expect(w.backend.openJobCount, 0);
      expect(tester.takeException(), isNull);
      hold.complete();
    },
  );

  testWidgets('busy: another PDF job runs → a snack bar, no sheet', (
    tester,
  ) async {
    final w = _World();
    addTearDown(w.dispose);
    await tester.pumpWidget(w.app());
    final ids = await w.notes(['a']);
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;
    final single = w.container
        .read(pdfExportJobProvider.notifier)
        .run(ids.single, const PdfExportOptions());
    await tester.pump();
    await exportNotesAsPdf(w.context, ids);
    await tester.pump();
    expect(find.text('다른 PDF 작업이 진행 중이에요.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    hold.complete();
    await tester.pump();
    await single;
  });

  testWidgets(
    'PDF-3-1 storage delay: delay text while the flush waits; 취소 ends it',
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

      final flow = exportNotesAsPdf(w.context, [note.id]);
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
      expect(find.text(_delayText), findsOneWidget);
      expect(_inDialog(find.text('닫기')), findsNothing);

      await tester.tap(_inDialog(find.text('취소')));
      await tester.pump();
      await _settle(tester);
      await flow;
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(w.backend.plans, isEmpty);
      expect((w.job as PdfBatchJobFinished).result.cancelled, isTrue);
      await tester.pump(
        const Duration(seconds: 15),
      ); // CORE's retry succeeds later
      await _settle(tester);
    },
  );
}
