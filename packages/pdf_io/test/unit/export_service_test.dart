// DefaultPdfExportService.exportNote (06-pdf 4.9, 6.11.2, 6.11.9, 6.11.10; 8 T15) on
// FakePdfNoteGateway + BoxInkVectorizer + RecordingComposeBackend: the three ranges and
// selection order, sources once each, missing originals (blankPage + warning / fail),
// chunks (8 pages here, 16 on the web — web/pure_logic_browser_test, 8 MB), progress,
// cancel at every wait (abort), file names, unknown notes, busy, backend errors, the
// pending pre-export flush on CORE's fake store (PDF-3-1) and pdfExportJobProvider.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart';

void main() {
  late ExportWorld w;

  setUp(() => w = ExportWorld());

  test(
    'all pages: note order, sources once in first-seen order, ink ops',
    () async {
      final a = await w.addPdf('a');
      final b = await w.addPdf('b');
      final note = await w.note('미적분 3강', [
        w.pdfPage(a, 0),
        blankDraft,
        w.pdfPage(b, 1, size: core.PageSize.letterPortrait),
        w.pdfPage(a, 2),
        blankDraft,
      ]);
      final pages = await w.gateway.pagesOf(note.id);
      w.addStroke(pages[1].id);
      w.addStroke(pages[4].id);
      w.addStroke(pages[4].id, x: 200);
      w.gateway.calls.clear();

      final result = await w.service.exportNote(
        note.id,
        const PdfExportOptions(),
      );

      expect(w.gateway.calls.first, 'flush');
      expect(w.gateway.calls.where((c) => c == 'readAssetBytes'), hasLength(2));
      final plan = w.backend.plans.single;
      expect([for (final s in plan.sources) s.assetId], [a, b]);
      expect(plan.sources[0].bytes, w.bytesOf('a'));
      expect(describePlan(plan), [
        'source 0:0',
        'blank',
        'source 1:1',
        'source 0:2',
        'blank',
      ]);
      expect(plan.pages[2].noteSize, const ui.Size(612, 792));
      expect(plan.pages[0].noteSize, const ui.Size(595.2756, 841.8898));
      expect(w.backend.events, ['begin#1', 'addPages#1', 'finish#1']);
      final ops = w.backend.pagesOfJob(1);
      expect([for (final o in ops) o.outputIndex], [1, 4]);
      // Two strokes → two path objects on page 5.
      expect(
        ops[1].verbs.where((v) => v == PdfComposeOpcodes.endObject),
        hasLength(2),
      );
      expect(String.fromCharCodes(result.bytes), '%PDF-fake');
      expect(result.fileName, '미적분 3강.pdf');
      expect(result.mimeType, 'application/pdf');
      expect(result.pageCount, 5);
      expect(result.warnings, isEmpty);
      expect(w.backend.openJobCount, 0);
    },
  );

  test('current page: that page only, file name with (p{n})', () async {
    final a = await w.addPdf('a');
    final note = await w.note('강의', [
      w.pdfPage(a, 0),
      w.pdfPage(a, 1),
      w.pdfPage(a, 2),
    ]);
    final pages = await w.gateway.pagesOf(note.id);
    w.addStroke(pages[1].id);

    final result = await w.service.exportNote(
      note.id,
      PdfExportOptions(range: PdfExportCurrentPage(pages[1].id)),
    );

    expect(describePlan(w.backend.plans.single), ['source 0:1']);
    expect([for (final o in w.backend.pagesOfJob(1)) o.outputIndex], [0]);
    expect(result.fileName, '강의 (p2).pdf');
    expect(result.pageCount, 1);
  });

  test(
    'selected pages: note order (not list order), unknown ids ignored, (선택 k쪽)',
    () async {
      final a = await w.addPdf('a');
      final note = await w.note('n', [
        for (var i = 0; i < 5; i++) w.pdfPage(a, i),
      ]);
      final pages = await w.gateway.pagesOf(note.id);

      final result = await w.service.exportNote(
        note.id,
        PdfExportOptions(
          range: PdfExportSelectedPages([
            pages[4].id,
            'no-such-page',
            pages[0].id,
            pages[2].id,
          ]),
        ),
      );

      expect(describePlan(w.backend.plans.single), [
        'source 0:0',
        'source 0:2',
        'source 0:4',
      ]);
      expect(result.fileName, 'n (선택 3쪽).pdf');
      expect(result.pageCount, 3);
    },
  );

  test('range errors are ArgumentErrors; nothing is composed', () async {
    final note = await w.note('n', [blankDraft]);
    await expectLater(
      w.service.exportNote(
        note.id,
        const PdfExportOptions(range: PdfExportCurrentPage('other')),
      ),
      throwsArgumentError,
    );
    await expectLater(
      w.service.exportNote(
        note.id,
        const PdfExportOptions(range: PdfExportSelectedPages(['x', 'y'])),
      ),
      throwsArgumentError,
    );
    expect(w.backend.plans, isEmpty);
    // The service is free again.
    await w.service.exportNote(note.id, const PdfExportOptions());
  });

  test('missing original, default blankPage: blank pages + warning, ink kept, '
      'no download asked', () async {
    final present = await w.addPdf('here');
    const remote = 'f00dfeed';
    w.gateway.addRemoteAsset(remote, fileName: 'remote.pdf');
    final note = await w.note('n', [
      w.pdfPage(remote, 0),
      w.pdfPage(present, 0),
      w.pdfPage(remote, 3),
      w.pdfPage(present, 1),
    ]);
    final pages = await w.gateway.pagesOf(note.id);
    w.addStroke(pages[2].id);
    w.gateway.calls.clear();

    final result = await w.service.exportNote(
      note.id,
      const PdfExportOptions(),
    );

    // One read per asset, even for the missing one.
    expect(w.gateway.calls.where((c) => c == 'readAssetBytes'), hasLength(2));
    final plan = w.backend.plans.single;
    expect([for (final s in plan.sources) s.assetId], [present]);
    expect(describePlan(plan), ['blank', 'source 0:0', 'blank', 'source 0:1']);
    expect(plan.pages[0].noteSize, const ui.Size(595.2756, 841.8898));
    expect([for (final o in w.backend.pagesOfJob(1)) o.outputIndex], [2]);
    final warning = result.warnings.single as PdfExportBlankedMissingAsset;
    expect(warning.notePageNumbers, [1, 3]);
    expect(result.pageCount, 4);
  });

  test(
    'missing original, fail: assetMissing with the page list, nothing begun',
    () async {
      const remote = 'f00dfeed';
      w.gateway.addRemoteAsset(remote);
      final note = await w.note('n', [
        w.pdfPage(remote, 0),
        blankDraft,
        w.pdfPage(remote, 1),
        w.pdfPage(remote, 2),
      ]);
      final error = await w.service
          .exportNote(
            note.id,
            const PdfExportOptions(
              missingAssetPolicy: PdfMissingAssetPolicy.fail,
            ),
          )
          .then<PdfIoException?>(
            (_) => null,
            onError: (Object e) => e as PdfIoException,
          );
      expect(error?.code, PdfErrorCode.assetMissing);
      expect(error?.detail, '1, 3–4');
      expect(error?.userMessage, '이 기기에 PDF 원본이 없어요. (1, 3–4쪽)');
      expect(w.backend.plans, isEmpty);
    },
  );

  test('chunks: ${kIsWeb ? 16 : 8} pages per addPages here '
      '(16 on the web, 8 on the shared native worker)', () async {
    final note = await w.note('n', [for (var i = 0; i < 20; i++) blankDraft]);
    for (final page in await w.gateway.pagesOf(note.id)) {
      w.addStroke(page.id);
    }
    await w.service.exportNote(note.id, const PdfExportOptions());
    expect([
      for (final c in w.backend.chunks) c.length,
    ], kIsWeb ? [16, 4] : [8, 8, 4]);
    expect(
      [
        for (final c in w.backend.chunks)
          for (final o in c) o.outputIndex,
      ],
      [for (var i = 0; i < 20; i++) i],
    );
  });

  test('chunks: at most 8 MB of ops, a larger page goes alone', () async {
    final note = await w.note('n', [for (var i = 0; i < 8; i++) blankDraft]);
    final pages = await w.gateway.pagesOf(note.id);
    // ~3.6 MB pages, except page 6 (~9 MB).
    final vectorizer = LongPathVectorizer({
      for (var i = 0; i < pages.length; i++)
        pages[i].id: i == 5 ? 1000000 : 400000,
    });
    final service = DefaultPdfExportService(
      gateway: w.gateway,
      vectorizer: vectorizer,
      backend: w.backend,
    );
    await service.exportNote(
      note.id,
      const PdfExportOptions(includeInk: false),
    );
    final chunks = w.backend.chunks;
    expect(
      [
        for (final c in chunks) [for (final o in c) o.outputIndex],
      ],
      [
        [0, 1],
        [2, 3],
        [4],
        [5],
        [6, 7],
      ],
    );
    for (final c in chunks) {
      if (c.length > 1) {
        final bytes = c.fold<int>(0, (n, o) => n + o.byteLength);
        expect(bytes, lessThanOrEqualTo(PdfTuning.exportChunkMaxBytes));
      }
    }
  });

  test(
    'progress: preparing → composing 0..n → finishing n/n, never back',
    () async {
      final note = await w.note('n', [for (var i = 0; i < 3; i++) blankDraft]);
      final seen = <PdfProgress>[];
      await w.service.exportNote(
        note.id,
        const PdfExportOptions(),
        onProgress: seen.add,
      );
      expect(seen, const [
        PdfProgress(PdfJobPhase.preparingExport),
        PdfProgress(PdfJobPhase.composing, total: 3),
        PdfProgress(PdfJobPhase.composing, done: 1, total: 3),
        PdfProgress(PdfJobPhase.composing, done: 2, total: 3),
        PdfProgress(PdfJobPhase.composing, done: 3, total: 3),
        PdfProgress(PdfJobPhase.finishingExport, done: 3, total: 3),
      ]);
      expect(seen.last.label, 'PDF 마무리 중 (3/3)');
    },
  );

  group('cancel', () {
    late core.Note note;

    setUp(() async {
      note = await w.note('n', [for (var i = 0; i < 20; i++) blankDraft]);
      for (final page in await w.gateway.pagesOf(note.id)) {
        w.addStroke(page.id);
      }
    });

    test('while composing → cancelled at once, the job is aborted', () async {
      final hold = Completer<void>();
      w.backend.beforeAddPages = () => hold.future;
      final cancel = PdfCancelSignal();
      final export = w.service.exportNote(
        note.id,
        const PdfExportOptions(),
        cancel: cancel,
      );
      final outcome = expectLater(
        export,
        throwsA(hasCode(PdfErrorCode.cancelled)),
      );
      await pumpEventQueue();
      expect(w.backend.events, ['begin#1', 'addPages#1']);
      cancel.cancel();
      await outcome;
      await pumpEventQueue();
      expect(w.backend.events, ['begin#1', 'addPages#1', 'abort#1']);
      expect(w.backend.openJobCount, 0);
      hold.complete();
      await pumpEventQueue();
      expect(w.backend.events.last, 'abort#1');
    });

    test(
      'while the backend begins → cancelled at once, the late job is aborted',
      () async {
        final hold = Completer<void>();
        w.backend.beforeBegin = () => hold.future;
        final cancel = PdfCancelSignal();
        final export = w.service.exportNote(
          note.id,
          const PdfExportOptions(),
          cancel: cancel,
        );
        final outcome = expectLater(
          export,
          throwsA(hasCode(PdfErrorCode.cancelled)),
        );
        await pumpEventQueue();
        cancel.cancel();
        await outcome;
        expect(w.backend.events, ['begin#1']);
        hold.complete();
        await pumpEventQueue();
        expect(w.backend.events, ['begin#1', 'abort#1']);
        expect(w.backend.openJobCount, 0);
      },
    );

    test(
      'while finishing → cancelled at once; finish cleans up (no abort)',
      () async {
        final hold = Completer<void>();
        w.backend.beforeFinish = () => hold.future;
        final cancel = PdfCancelSignal();
        final export = w.service.exportNote(
          note.id,
          const PdfExportOptions(),
          cancel: cancel,
        );
        final outcome = expectLater(
          export,
          throwsA(hasCode(PdfErrorCode.cancelled)),
        );
        await pumpEventQueue();
        expect(w.backend.events.last, 'finish#1');
        cancel.cancel();
        await outcome;
        hold.complete();
        await pumpEventQueue();
        expect(w.backend.events.last, 'finish#1');
        expect(w.backend.openJobCount, 0);
      },
    );

    test('already cancelled → cancelled, nothing read or composed', () async {
      w.gateway.calls.clear();
      final cancel = PdfCancelSignal()..cancel();
      await expectLater(
        w.service.exportNote(note.id, const PdfExportOptions(), cancel: cancel),
        throwsA(hasCode(PdfErrorCode.cancelled)),
      );
      expect(w.gateway.calls, ['flush']);
      expect(w.backend.plans, isEmpty);
    });
  });

  test(
    'file names: sanitized title; options.fileName wins, ".pdf" added',
    () async {
      final note = await w.note(' a/b: "c" ', [blankDraft]);
      final r1 = await w.service.exportNote(note.id, const PdfExportOptions());
      expect(r1.fileName, 'a_b_ _c_.pdf');
      final r2 = await w.service.exportNote(
        note.id,
        const PdfExportOptions(fileName: '보고서'),
      );
      expect(r2.fileName, '보고서.pdf');
      final r3 = await w.service.exportNote(
        note.id,
        const PdfExportOptions(fileName: 'Final.PDF'),
      );
      expect(r3.fileName, 'Final.pdf');
      final empty = await w.note('   ', [blankDraft]);
      final r4 = await w.service.exportNote(empty.id, const PdfExportOptions());
      expect(r4.fileName, '노트.pdf');
    },
  );

  test('an unknown note → noteNotFound, nothing composed', () async {
    await expectLater(
      w.service.exportNote('note-404', const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.noteNotFound)),
    );
    expect(w.backend.plans, isEmpty);
  });

  test('busy: one export (single or batch) at a time per service', () async {
    final note = await w.note('n', [blankDraft]);
    w.addStroke((await w.gateway.pagesOf(note.id)).single.id);
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;
    final first = w.service.exportNote(note.id, const PdfExportOptions());
    await pumpEventQueue();
    await expectLater(
      w.service.exportNote(note.id, const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.busy)),
    );
    await expectLater(
      w.service.exportNotes([note.id], const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.busy)),
    );
    hold.complete();
    await first;
    w.backend.beforeAddPages = null;
    await w.service.exportNote(note.id, const PdfExportOptions());
  });

  test('a backend that is not supported → unsupportedPlatform', () async {
    final note = await w.note('n', [blankDraft]);
    w.backend.supported = false;
    await expectLater(
      w.service.exportNote(note.id, const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.unsupportedPlatform)),
    );
    await expectLater(
      w.service.exportNotes([note.id], const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.unsupportedPlatform)),
    );
  });

  group('backend errors (reported once, job aborted)', () {
    late core.Note note;
    late List<FlutterErrorDetails> reports;

    setUp(() async {
      reports = captureFlutterErrors();
      note = await w.note('n', [blankDraft, blankDraft]);
      for (final page in await w.gateway.pagesOf(note.id)) {
        w.addStroke(page.id);
      }
    });

    test(
      'begin: exportFailed rethrown; engineUnavailable not reported',
      () async {
        w.backend.beginError = const PdfIoException(
          PdfErrorCode.exportFailed,
          detail: 'source did not load',
        );
        await expectLater(
          w.service.exportNote(note.id, const PdfExportOptions()),
          throwsA(hasCode(PdfErrorCode.exportFailed)),
        );
        expect(reports, hasLength(1));
        expect(reports.single.library, 'pdf_io');
        w.backend.beginError = const PdfIoException(
          PdfErrorCode.engineUnavailable,
        );
        await expectLater(
          w.service.exportNote(note.id, const PdfExportOptions()),
          throwsA(hasCode(PdfErrorCode.engineUnavailable)),
        );
        expect(reports, hasLength(1));
      },
    );

    test(
      'addPages: an unexpected error → abort + exportFailed with the cause',
      () async {
        final boom = StateError('worker went away');
        w.backend.addPagesError = boom;
        await expectLater(
          w.service.exportNote(note.id, const PdfExportOptions()),
          throwsA(
            hasCode(PdfErrorCode.exportFailed)
                .having((e) => e.cause, 'cause', same(boom)),
          ),
        );
        await pumpEventQueue();
        expect(w.backend.events, ['begin#1', 'addPages#1', 'abort#1']);
        expect(reports, hasLength(1));
        expect(reports.single.exception, same(boom));
      },
    );

    test(
      'finish: exportFailed rethrown, no abort (finish cleaned up)',
      () async {
        w.backend.finishError = const PdfIoException(PdfErrorCode.exportFailed);
        await expectLater(
          w.service.exportNote(note.id, const PdfExportOptions()),
          throwsA(hasCode(PdfErrorCode.exportFailed)),
        );
        await pumpEventQueue();
        expect(w.backend.events, ['begin#1', 'addPages#1', 'finish#1']);
        expect(w.backend.openJobCount, 0);
        expect(reports, hasLength(1));
      },
    );
  });

  test(
    'includeInk false: no page loads, PDF pages untouched, paper fills kept',
    () async {
      final a = await w.addPdf('a');
      final note = await w.note('n', [
        w.pdfPage(a, 0),
        const core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.BlankBackground(
            paperColorArgb: core.PaperColors.ivory,
          ),
        ),
        blankDraft,
      ]);
      for (final page in await w.gateway.pagesOf(note.id)) {
        w.addStroke(page.id);
      }
      w.gateway.calls.clear();
      await w.service.exportNote(
        note.id,
        const PdfExportOptions(includeInk: false),
      );
      expect(w.gateway.calls, isNot(contains('loadPage')));
      final ops = w.backend.pagesOfJob(1);
      expect([for (final o in ops) o.outputIndex], [1]); // the ivory paper only
      expect(ops.single.paints[1], closeTo(0xFB, 0.5)); // r of ivory

      // includeTemplates false as well: original pages + plain white pages, no ops.
      await w.service.exportNote(
        note.id,
        const PdfExportOptions(includeInk: false, includeTemplates: false),
      );
      expect(w.backend.pagesOfJob(2), isEmpty);
      expect(w.backend.events.where((e) => e.endsWith('#2')), [
        'begin#2',
        'finish#2',
      ]);
    },
  );

  group(
    'PDF-3-1: cancel while the pre-export flush waits (CORE fake store)',
    () {
      for (final batch in [false, true]) {
        test(batch ? 'exportNotes' : 'exportNote', () {
          final reports = captureFlutterErrors();
          fakeAsync((async) {
            final faults = core_testing.FakeNoteStoreFaults();
            final store = core_testing.createFakeNoteStore(faults: faults);
            final gateway = CorePdfNoteGateway(store);
            final backend = RecordingComposeBackend();
            final service = DefaultPdfExportService(
              gateway: gateway,
              vectorizer: const BoxInkVectorizer(),
              backend: backend,
            );
            core.Note? note;
            gateway
                .createNote(title: 'n', pages: const [blankDraft])
                .then((n) => note = n);
            async.elapse(Duration.zero);
            expect(note, isNotNull);
            core.NoteSession? session;
            store.openSession(note!.id).then((s) => session = s);
            async.elapse(Duration.zero);
            final pageId = session!.pages.single.id;

            // Every commit fails for a while: the stroke edit's commit is retried.
            faults.failNextCommits(100);
            unawaited(
              session!
                  .executeAsync(
                    core.AddStrokes(
                      pageId: pageId,
                      strokes: [testStroke(store.ids.newId(), pageId)],
                    ),
                  )
                  .then((_) {}),
            );
            async.elapse(Duration.zero);

            final cancel = PdfCancelSignal();
            Object? error;
            PdfBatchExportResult? batchResult;
            var done = false;
            if (batch) {
              service
                  .exportNotes(
                    [note!.id],
                    const PdfExportOptions(),
                    cancel: cancel,
                  )
                  .then(
                    (r) {
                      batchResult = r;
                      done = true;
                    },
                    onError: (Object e) {
                      error = e;
                    },
                  );
            } else {
              service
                  .exportNote(
                    note!.id,
                    const PdfExportOptions(),
                    cancel: cancel,
                  )
                  .then(
                    (_) {
                      done = true;
                    },
                    onError: (Object e) {
                      error = e;
                    },
                  );
            }
            async.elapse(const Duration(seconds: 10));
            expect(done, isFalse, reason: 'step 1 waits for the flush');
            expect(error, isNull);
            expect(
              core.storageWarningOf(store.storageInfo, store.persistenceStatus),
              core.StorageWarning.writeFailing,
            );

            cancel.cancel();
            async.flushMicrotasks();
            if (batch) {
              expect(error, isNull);
              expect(batchResult!.cancelled, isTrue);
              expect(batchResult!.files, isEmpty);
              expect(batchResult!.notReachedCount, 1);
            } else {
              expect(error, hasCode(PdfErrorCode.cancelled));
            }
            expect(backend.plans, isEmpty, reason: 'begin was never called');

            // CORE's retried commit succeeds later: nothing else happens.
            async.elapse(const Duration(minutes: 10));
            expect(
              core.storageWarningOf(store.storageInfo, store.persistenceStatus),
              isNull,
            );
            expect(backend.plans, isEmpty);
            unawaited(session!.close());
            unawaited(store.close());
            async.elapse(Duration.zero);
          });
          expect(reports, isEmpty);
        });
      }
    },
  );

  group('pdfExportJobProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [pdfExportServiceProvider.overrideWithValue(w.service)],
      );
      addTearDown(container.dispose);
    });

    test('Running → Succeeded with the result; reset → idle', () async {
      final note = await w.note('n', [blankDraft]);
      final job = container.read(pdfExportJobProvider.notifier);
      expect(
        container.read(pdfExportJobProvider),
        const PdfJobIdle<PdfExportResult>(),
      );
      expect(job.isBusy, isFalse);
      final running = job.run(note.id, const PdfExportOptions());
      expect(
        container.read(pdfExportJobProvider),
        isA<PdfJobRunning<PdfExportResult>>(),
      );
      expect(job.isBusy, isTrue);
      final result = await running;
      expect(result, isNotNull);
      final state = container.read(pdfExportJobProvider);
      expect(state, isA<PdfJobSucceeded<PdfExportResult>>());
      expect((state as PdfJobSucceeded<PdfExportResult>).result, same(result));
      expect(job.isBusy, isFalse);
      job.reset();
      expect(
        container.read(pdfExportJobProvider),
        const PdfJobIdle<PdfExportResult>(),
      );
    });

    test(
      'a second run while one runs → null, the Running state kept',
      () async {
        final note = await w.note('n', [blankDraft]);
        w.addStroke((await w.gateway.pagesOf(note.id)).single.id);
        final hold = Completer<void>();
        w.backend.beforeAddPages = () => hold.future;
        final job = container.read(pdfExportJobProvider.notifier);
        final first = job.run(note.id, const PdfExportOptions());
        await pumpEventQueue();
        expect(await job.run(note.id, const PdfExportOptions()), isNull);
        expect(
          container.read(pdfExportJobProvider),
          isA<PdfJobRunning<PdfExportResult>>(),
        );
        job.reset(); // ignored while running
        expect(
          container.read(pdfExportJobProvider),
          isA<PdfJobRunning<PdfExportResult>>(),
        );
        hold.complete();
        expect(await first, isNotNull);
      },
    );

    test('cancel → Failed(cancelled) at once; the service busy elsewhere → Failed(busy)', () async {
      final note = await w.note('n', [blankDraft]);
      w.addStroke((await w.gateway.pagesOf(note.id)).single.id);
      final hold = Completer<void>();
      w.backend.beforeAddPages = () => hold.future;
      final job = container.read(pdfExportJobProvider.notifier);
      final running = job.run(note.id, const PdfExportOptions());
      await pumpEventQueue();
      job.cancel();
      expect(await running, isNull);
      expect(
        container.read(pdfExportJobProvider),
        const PdfJobFailed<PdfExportResult>(
          PdfIoException(PdfErrorCode.cancelled),
        ),
      );
      hold.complete();
      await pumpEventQueue();

      // The same service is busy with a direct call (another container, a batch …).
      final hold2 = Completer<void>();
      w.backend.beforeAddPages = () => hold2.future;
      final direct = w.service.exportNote(note.id, const PdfExportOptions());
      await pumpEventQueue();
      expect(await job.run(note.id, const PdfExportOptions()), isNull);
      expect(
        container.read(pdfExportJobProvider),
        const PdfJobFailed<PdfExportResult>(PdfIoException(PdfErrorCode.busy)),
      );
      hold2.complete();
      await direct;
    });

    test('progress reaches the state at most every 100 ms', () {
      fakeAsync((async) {
        late core.Note note;
        w
            .note('n', [for (var i = 0; i < 40; i++) blankDraft])
            .then((n) => note = n);
        async.flushMicrotasks();
        for (final page in w.gateway.pagesOf(note.id).let(async)) {
          w.addStroke(page.id);
        }
        // 5 chunks of 8 pages, 50 ms each: ~42 progress values over 250 ms.
        w.backend.beforeAddPages = () =>
            Future<void>.delayed(const Duration(milliseconds: 50));
        final states = <PdfJobState<PdfExportResult>>[];
        container.listen(pdfExportJobProvider, (_, next) => states.add(next));
        final job = container.read(pdfExportJobProvider.notifier);
        PdfExportResult? result;
        job.run(note.id, const PdfExportOptions()).then((r) => result = r);
        async.elapse(const Duration(seconds: 1));
        expect(result, isNotNull);
        final running = states.whereType<PdfJobRunning<PdfExportResult>>();
        // Running(preparing) from run, then at most one update per 100 ms.
        expect(running.length, inInclusiveRange(2, 4));
        expect(running.skip(1).first.progress.phase, PdfJobPhase.composing);
        expect(states.last, isA<PdfJobSucceeded<PdfExportResult>>());
      });
    });
  });
}

extension<T> on Future<T> {
  /// The value of a future that completes within the fake zone's microtasks.
  T let(FakeAsync async) {
    late T value;
    then((v) => value = v);
    async.flushMicrotasks();
    return value;
  }
}
