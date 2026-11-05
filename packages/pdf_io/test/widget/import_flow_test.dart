// Import flow (06-pdf 4.11, 6.3, 6.4; 8 T6): sheet → picker → password → range → progress →
// result, picker cancel, cancel during progress, large-file confirmation, busy,
// importPdfAsNewNote (folderId, note id, unmounted context), the composed file name, and the
// storage delay (PDF-3-1): delay text + '닫기' while CORE retries, the job keeps running.
// Every test runs on an iPad Pro 13" view (contract 7.4.8); the sheet, the password dialog,
// the options, the large-file confirmation and the progress dialog (with and without
// '닫기') meet the 44×44 / labeled tap-target guidelines, also in landscape.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/ipad.dart';
import '../support/render_doubles.dart';

const String _delayText = '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.';

Uint8List _pdf([String body = 'body']) =>
    Uint8List.fromList('%PDF-1.7\n% $body\n%%EOF\n'.codeUnits);

/// '강의자료.PDF' in NFD (conjoining jamo).
const String _nfdName = '강의자료.PDF';

final class _World {
  _World({
    FakePdfEngine? engine,
    PdfNoteGateway? gateway,
    core.NoteStore? store,
    List<PickedPdfFile?> files = const [],
    PdfIoConfig config = const PdfIoConfig(),
  }) : engine = engine ?? FakePdfEngine(pageCount: 3),
       store = store ?? core_testing.createFakeNoteStore(),
       files = FakePdfFileSource(files: files) {
    this.gateway = gateway ?? FakePdfNoteGateway();
    container = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(this.store),
        core.pageThumbnailRendererProvider.overrideWithValue(thumbnails),
        pdfIoConfigProvider.overrideWithValue(config),
        pdfEngineProvider.overrideWithValue(this.engine),
        pdfNoteGatewayProvider.overrideWithValue(this.gateway),
        pdfDocumentPoolProvider.overrideWithValue(RecordingDocumentPool()),
        pdfPageRendererProvider.overrideWithValue(SolidThumbnailRenderer()),
        pdfFileSourceProvider.overrideWithValue(this.files),
      ],
    );
  }

  final FakePdfEngine engine;
  final core.NoteStore store;
  final FakePdfFileSource files;
  final ScriptedThumbnailRenderer thumbnails = ScriptedThumbnailRenderer();
  late final PdfNoteGateway gateway;
  late final ProviderContainer container;
  late BuildContext context;

  FakePdfNoteGateway get fakeGateway => gateway as FakePdfNoteGateway;

  PdfJobState<PdfImportResult> get job => container.read(pdfImportJobProvider);

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

/// Lets sheets / dialogs animate in or out. No pumpAndSettle: the indeterminate progress
/// bars never settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

/// Opens the sheet and picks the queued file.
Future<void> _pick(WidgetTester tester) async {
  await _settle(tester);
  expect(find.text('PDF 파일 선택'), findsOneWidget);
  await tester.tap(find.text('PDF 파일 선택'));
  await _settle(tester);
}

void main() {
  testWidgets('pick → wrong password → again → range 2-3 → progress → result', (
    tester,
  ) async {
    final w = _World(
      engine: FakePdfEngine(pageCount: 4, userPassword: 'pw'),
      files: [PickedPdfFile.fromBytes('locked.pdf', _pdf())],
    );
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = runPdfImportFlow(
      w.context,
      const PdfImportAsNewNote(folderId: 'folder-1'),
    );
    await _settle(tester);
    await expectTapTargetGuidelines(tester); // the sheet, nothing picked yet
    await _pick(tester);
    expect(w.files.pickCalls, 1);

    // First password request.
    expect(find.text('PDF 암호'), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    expect(find.text('암호가 틀렸어요. 다시 입력해 주세요.'), findsNothing);
    expect(find.text('암호를 푼 사본이 노트에 저장돼요'), findsOneWidget);
    await tester.enterText(_inDialog(find.byType(TextField)), 'nope');
    await tester.tap(_inDialog(find.text('확인')));
    await _settle(tester);

    // Second request says the first one was wrong.
    expect(find.text('암호가 틀렸어요. 다시 입력해 주세요.'), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await tester.enterText(_inDialog(find.byType(TextField)), 'pw');
    await tester.tap(_inDialog(find.text('확인')));
    await _settle(tester);
    expect(find.text('PDF 암호'), findsNothing);
    expect(w.engine.passwordRequests.map((r) => r.attempt), [1, 2]);

    // Options: an invalid range is refused in place, then '2-3'.
    expect(find.textContaining('4쪽'), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text('가져오기'));
    await tester.pump();
    expect(find.text("'9'쪽이 없어요. 1–4쪽 중에서 골라 주세요."), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    expect(w.fakeGateway.calls, isEmpty);
    await tester.enterText(find.byType(TextField), '2-3');
    await tester.tap(find.text('가져오기'));
    await _settle(tester);

    final result = await flow;
    expect(result, isNotNull);
    expect(result!.insertedPageIds, hasLength(2));
    expect(result.storedDecryptedCopy, isTrue);
    expect(result.createdNewNote, isTrue);
    final pages = await w.gateway.pagesOf(result.noteId);
    expect(
      [
        for (final p in pages)
          (p.background as core.PdfBackground).pdfPageIndex,
      ],
      [1, 2],
    );
    expect((await w.gateway.getNote(result.noteId))!.folderId, 'folder-1');
    expect(w.job, PdfJobSucceeded<PdfImportResult>(result));
    expect(find.text('PDF 가져오는 중'), findsNothing);
    expect(find.text('2쪽을 가져왔어요'), findsOneWidget);
    // The session ended with the job: its document went to the pool or was closed.
    expect(w.engine.openDocumentCount, 0); // decrypted copy → closed
  });

  testWidgets('cancelling the file picker → null, nothing opened', (
    tester,
  ) async {
    final w = _World(); // empty queue: the picker answers null
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    expect(await flow, isNull);
    expect(find.text('PDF 파일 선택'), findsNothing);
    expect(w.engine.openCalls, isEmpty);
    expect(w.job, const PdfJobIdle<PdfImportResult>());
  });

  testWidgets('closing the sheet after opening disposes the session', (
    tester,
  ) async {
    final w = _World(files: [PickedPdfFile.fromBytes('a.pdf', _pdf())]);
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    expect(w.engine.openDocumentCount, 1);
    await tester.tap(find.text('취소'));
    await _settle(tester);
    expect(await flow, isNull);
    expect(w.engine.openDocumentCount, 0);
  });

  testWidgets('a file that is not a PDF shows the message in the sheet', (
    tester,
  ) async {
    final w = _World(
      files: [
        PickedPdfFile.fromBytes('x.pdf', Uint8List.fromList('hello'.codeUnits)),
      ],
    );
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    expect(find.text('PDF 파일이 아니에요.'), findsOneWidget);
    expect(find.text('다른 파일 선택'), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await tester.tap(find.text('취소'));
    await _settle(tester);
    expect(await flow, isNull);
  });

  testWidgets('cancel during progress → null, job cancelled, no message', (
    tester,
  ) async {
    final w = _World(files: [PickedPdfFile.fromBytes('a.pdf', _pdf())]);
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    w.fakeGateway.holdWrites(); // putPdf stays pending
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    expect(find.text('PDF 가져오는 중'), findsOneWidget);
    expect(find.text('저장 중'), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    // No storage failure injected: neither the delay text nor '닫기'.
    expect(find.text(_delayText), findsNothing);
    expect(find.text('닫기'), findsNothing);
    expect(w.job, isA<PdfJobRunning<PdfImportResult>>());
    await tester.tap(_inDialog(find.text('취소')));
    await _settle(tester);
    expect(await flow, isNull);
    expect(find.text('PDF 가져오는 중'), findsNothing);
    expect(
      w.job,
      const PdfJobFailed<PdfImportResult>(
        PdfIoException(PdfErrorCode.cancelled),
      ),
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(w.fakeGateway.calls, ['putPdf']);
    expect(w.engine.openDocumentCount, 0);
    w.fakeGateway.releaseWrites();
    await _settle(tester);
    expect(w.fakeGateway.calls, ['putPdf']);
  });

  testWidgets('large file → confirmation; 취소 ends the flow', (tester) async {
    final bytes = _pdf('large');
    final w = _World(
      files: [
        PickedPdfFile.fromBytes('big.pdf', bytes),
        PickedPdfFile.fromBytes('big.pdf', bytes),
      ],
      config: PdfIoConfig(limits: PdfImportLimits(warnBytes: bytes.length - 1)),
    );
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());

    var flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    expect(find.text('큰 PDF예요'), findsOneWidget);
    await expectTapTargetGuidelines(tester);
    await tester.tap(_inDialog(find.text('취소')));
    await _settle(tester);
    expect(await flow, isNull);
    expect(w.fakeGateway.calls, isEmpty);
    expect(w.engine.openDocumentCount, 0);

    flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    expect(find.text('큰 PDF예요'), findsOneWidget);
    await tester.tap(_inDialog(find.text('가져오기')));
    await _settle(tester);
    expect(await flow, isNotNull);
  });

  testWidgets('busy: a second import while one runs → busy message, null', (
    tester,
  ) async {
    final w = _World(files: [PickedPdfFile.fromBytes('a.pdf', _pdf())]);
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final first = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    w.fakeGateway.holdWrites();
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    expect(w.container.read(pdfImportJobProvider.notifier).isBusy, isTrue);

    final second = await runPdfImportFlow(
      w.context,
      const PdfImportAsNewNote(),
    );
    await tester.pump();
    expect(second, isNull);
    expect(find.text('다른 PDF 작업이 진행 중이에요.'), findsOneWidget);
    expect(w.files.pickCalls, 1); // no second sheet / picker

    w.fakeGateway.releaseWrites();
    await _settle(tester);
    expect(await first, isNotNull);
    expect(w.container.read(pdfImportJobProvider.notifier).isBusy, isFalse);
  });

  testWidgets('importPdfAsNewNote: folderId passed, note id returned', (
    tester,
  ) async {
    final w = _World(files: [PickedPdfFile.fromBytes('a.pdf', _pdf())]);
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = importPdfAsNewNote(w.context, folderId: 'folder-7');
    await _pick(tester);
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    final noteId = await flow;
    expect(noteId, isNotNull);
    final note = (await w.gateway.getNote(noteId!))!;
    expect(note.folderId, 'folder-7');
    expect(note.title, 'a');
    // Cover through the injected renderer (core.pageThumbnailRendererProvider).
    expect(w.thumbnails.calls.single.$2, 512);
  });

  testWidgets('importPdfAsNewNote: context unmounted midway → null, quietly', (
    tester,
  ) async {
    final w = _World(files: [PickedPdfFile.fromBytes('a.pdf', _pdf())]);
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
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
    final flow = importPdfAsNewNote(pageContext);
    // The page under the sheet goes away while the picker is open.
    w.files.beforePick = () async => navigator.removeRoute(page);
    await _pick(tester);
    expect(pageContext.mounted, isFalse);
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    expect(await flow, isNull);
    expect(tester.takeException(), isNull);
    expect(find.text('PDF 가져오는 중'), findsNothing);
    expect(w.fakeGateway.calls, isEmpty);
    expect(w.engine.openDocumentCount, 0);
  });

  testWidgets('the sheet shows the composed (NFC) file name', (tester) async {
    final w = _World(files: [PickedPdfFile.fromBytes(_nfdName, _pdf())]);
    addTearDown(w.dispose);
    await pumpOnIpad(tester, w.app());
    final flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
    await _pick(tester);
    expect(find.text('강의자료.PDF'), findsOneWidget);
    expect(find.text(_nfdName), findsNothing);
    await tester.tap(find.text('가져오기'));
    await _settle(tester);
    final result = await flow;
    expect((await w.gateway.getNote(result!.noteId))!.title, '강의자료');
  });

  testWidgets(
    'PDF-3-1 storage delay: delay text and 닫기, the job keeps running',
    (tester) async {
      final faults = core_testing.FakeNoteStoreFaults();
      final store = core_testing.createFakeNoteStore(faults: faults);
      final w = _World(
        store: store,
        gateway: CorePdfNoteGateway(store),
        files: [PickedPdfFile.fromBytes('slow.pdf', _pdf('slow'))],
      );
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app());
      final flow = importPdfAsNewNote(w.context, folderId: null);
      await _pick(tester);
      faults.failNextCommits(5);
      await tester.tap(find.text('가져오기'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('PDF 가져오는 중'), findsOneWidget);
      expect(find.text(_delayText), findsOneWidget);
      expect(_inDialog(find.text('닫기')), findsOneWidget);
      expect(_inDialog(find.text('취소')), findsOneWidget); // still storing
      await expectTapTargetGuidelines(tester);

      await tester.tap(_inDialog(find.text('닫기')));
      await tester.pump();
      expect(await flow, isNull);
      await _settle(tester);
      expect(find.text('PDF 가져오는 중'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(w.job, isA<PdfJobRunning<PdfImportResult>>());

      // Meanwhile another import is busy.
      final second = await runPdfImportFlow(
        w.context,
        const PdfImportAsNewNote(),
      );
      await tester.pump();
      expect(second, isNull);
      expect(find.text('다른 PDF 작업이 진행 중이에요.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 15));
      await _settle(tester);
      final job = w.job;
      expect(job, isA<PdfJobSucceeded<PdfImportResult>>());
      final noteId = (job as PdfJobSucceeded<PdfImportResult>).result.noteId;
      final note = await store.library.getNote(noteId);
      expect(note, isNotNull);
      expect(note!.title, 'slow');
      // No result UI after '닫기'.
      expect(find.textContaining('쪽을 가져왔어요'), findsNothing);
    },
  );

  testWidgets(
    'landscape 1376×1032: sheet, password, options and progress meet the '
    'tap-target guidelines',
    (tester) async {
      final w = _World(
        engine: FakePdfEngine(pageCount: 4, userPassword: 'pw'),
        files: [PickedPdfFile.fromBytes('locked.pdf', _pdf())],
      );
      addTearDown(w.dispose);
      await pumpOnIpad(tester, w.app(), landscape: true);
      expect(
        tester.view.physicalSize / tester.view.devicePixelRatio,
        ipad13Landscape,
      );
      final flow = runPdfImportFlow(w.context, const PdfImportAsNewNote());
      await _settle(tester);
      expect(find.text('PDF 파일 선택'), findsOneWidget);
      await expectTapTargetGuidelines(tester);
      await _pick(tester);
      expect(find.text('PDF 암호'), findsOneWidget);
      await expectTapTargetGuidelines(tester);
      await tester.enterText(_inDialog(find.byType(TextField)), 'pw');
      await tester.tap(_inDialog(find.text('확인')));
      await _settle(tester);
      expect(find.textContaining('4쪽'), findsOneWidget);
      await expectTapTargetGuidelines(tester);
      w.fakeGateway
          .holdWrites(); // putPdf stays pending: the progress dialog stays up
      await tester.tap(find.text('가져오기'));
      await _settle(tester);
      expect(find.text('PDF 가져오는 중'), findsOneWidget);
      await expectTapTargetGuidelines(tester);
      await tester.tap(_inDialog(find.text('취소')));
      await _settle(tester);
      expect(await flow, isNull);
      w.fakeGateway.releaseWrites();
      await _settle(tester);
    },
  );
}
