// Bulk export (06-pdf 4.9, 6.11.11; 8 T15b, PDF-S3) — DefaultPdfExportService.exportNotes
// on FakePdfNoteGateway + BoxInkVectorizer + RecordingComposeBackend: notes in order (one
// file each, one compose job each), same titles → ' (2)', missing notes and per-note
// failures recorded while the batch goes on, cancel keeps the files made so far, the 150 MB
// limit, the overall progress never goes back, the busy flag shared with single exports,
// and pdfBatchExportJobProvider (states, busy across PDF jobs, cancel, empty list).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart';

void main() {
  late ExportWorld w;

  setUp(() => w = ExportWorld());

  Future<List<core.NoteId>> notes(List<String> titles) async => [
    for (final title in titles)
      (await w.note(title, [blankDraft, blankDraft])).id,
  ];

  test('notes in order: one file and one compose job each', () async {
    final a = await w.addPdf('a');
    final ids = [
      (await w.note('수학', [w.pdfPage(a, 0), blankDraft])).id,
      (await w.note('영어', [blankDraft])).id,
      (await w.note('과학', [w.pdfPage(a, 1)])).id,
    ];
    final result = await w.service.exportNotes(ids, const PdfExportOptions());
    expect(result.requestedCount, 3);
    expect(result.cancelled, isFalse);
    expect(result.stoppedAtSizeLimit, isFalse);
    expect(result.notReachedCount, 0);
    expect([for (final i in result.items) i.noteId], ids);
    expect([for (final i in result.items) i.title], ['수학', '영어', '과학']);
    expect([for (final i in result.items) i.succeeded], [true, true, true]);
    expect(
      [for (final f in result.files) f.fileName],
      ['수학.pdf', '영어.pdf', '과학.pdf'],
    );
    expect([for (final f in result.files) f.pageCount], [2, 1, 1]);
    expect(
      [for (final p in w.backend.plans) describePlan(p)],
      [
        ['source 0:0', 'blank'],
        ['blank'],
        ['source 0:1'],
      ],
    );
    expect(w.backend.events, [
      'begin#1',
      'finish#1',
      'begin#2',
      'finish#2',
      'begin#3',
      'finish#3',
    ]);
  });

  test('a range in the options is ignored: whole notes', () async {
    final ids = await notes(['a', 'b']);
    final first = (await w.gateway.pagesOf(ids.first)).first;
    final result = await w.service.exportNotes(
      ids,
      PdfExportOptions(range: PdfExportCurrentPage(first.id)),
    );
    expect([for (final f in result.files) f.pageCount], [2, 2]);
    expect([for (final f in result.files) f.fileName], ['a.pdf', 'b.pdf']);
  });

  test("same titles → ' (2)', ' (3)' (case-insensitive), same bytes", () async {
    final ids = await notes(['Notes', 'notes', 'Other', 'NOTES']);
    final result = await w.service.exportNotes(ids, const PdfExportOptions());
    expect(
      [for (final f in result.files) f.fileName],
      ['Notes.pdf', 'notes (2).pdf', 'Other.pdf', 'NOTES (3).pdf'],
    );
    expect(String.fromCharCodes(result.files[1].bytes), '%PDF-fake');
    expect(result.items[1].title, 'notes');
  });

  test(
    'a missing note is recorded (noteNotFound, no title) and the batch goes on',
    () async {
      final ids = await notes(['a', 'b']);
      final result = await w.service.exportNotes([
        ids[0],
        'note-404',
        ids[1],
      ], const PdfExportOptions());
      expect(result.items, hasLength(3));
      final missing = result.items[1];
      expect(missing.noteId, 'note-404');
      expect(missing.title, '');
      expect(missing.succeeded, isFalse);
      expect(missing.error, hasCode(PdfErrorCode.noteNotFound));
      expect(result.files, hasLength(2));
      expect(w.backend.plans, hasLength(2));
    },
  );

  test(
    'per-note exportFailed / assetMissing are recorded and the batch goes on',
    () async {
      final reports = captureFlutterErrors();
      const remote = 'abcdef';
      w.gateway.addRemoteAsset(remote);
      final ids = await notes(['a', 'b']);
      final missingOriginal = await w.note('원본 없음', [w.pdfPage(remote, 0)]);
      // The second compose job fails to begin.
      w.backend.beforeBegin = () async {
        w.backend.beginError = w.backend.plans.length == 2
            ? const PdfIoException(PdfErrorCode.exportFailed, detail: 'boom')
            : null;
      };
      final result = await w.service.exportNotes(
        [ids[0], ids[1], missingOriginal.id],
        const PdfExportOptions(missingAssetPolicy: PdfMissingAssetPolicy.fail),
      );
      expect([for (final i in result.items) i.succeeded], [true, false, false]);
      expect(result.items[1].title, 'b');
      expect(result.items[1].error, hasCode(PdfErrorCode.exportFailed));
      expect(result.items[2].title, '원본 없음');
      expect(result.items[2].error, hasCode(PdfErrorCode.assetMissing));
      expect(result.items[2].error!.detail, '1');
      expect(result.files.single.fileName, 'a.pdf');
      expect(reports, hasLength(1), reason: 'exportFailed reported once');
    },
  );

  test('engineUnavailable ends the whole batch with that error', () async {
    final ids = await notes(['a', 'b']);
    w.backend.beginError = const PdfIoException(PdfErrorCode.engineUnavailable);
    await expectLater(
      w.service.exportNotes(ids, const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.engineUnavailable)),
    );
    expect(w.backend.plans, hasLength(1));
  });

  test(
    'cancel: the note in progress is aborted, the files made are kept',
    () async {
      final ids = await notes(['a', 'b', 'c']);
      for (final id in ids) {
        for (final page in await w.gateway.pagesOf(id)) {
          w.addStroke(page.id);
        }
      }
      final hold = Completer<void>();
      w.backend.beforeAddPages = () =>
          w.backend.plans.length == 2 ? hold.future : Future<void>.value();
      final cancel = PdfCancelSignal();
      final running = w.service.exportNotes(
        ids,
        const PdfExportOptions(),
        cancel: cancel,
      );
      await pumpEventQueue();
      expect(w.backend.events.last, 'addPages#2');
      cancel.cancel();
      final result = await running;
      expect(result.cancelled, isTrue);
      expect(result.items, hasLength(1));
      expect(result.files.single.fileName, 'a.pdf');
      expect(result.notReachedCount, 2);
      await pumpEventQueue();
      expect(w.backend.events.last, 'abort#2');
      expect(w.backend.openJobCount, 0);
      hold.complete();
    },
  );

  test('cancel before the start → cancelled, no file, nothing read', () async {
    final ids = await notes(['a']);
    w.gateway.calls.clear();
    final result = await w.service.exportNotes(
      ids,
      const PdfExportOptions(),
      cancel: PdfCancelSignal()..cancel(),
    );
    expect(result.cancelled, isTrue);
    expect(result.items, isEmpty);
    expect(result.notReachedCount, 1);
    expect(w.gateway.calls, isEmpty);
  });

  test('size limit: no note starts once the files reach 150 MB', () async {
    // One shared 80 MB buffer per file: two files = 160 MB.
    final big = Uint8List(80 * 1024 * 1024);
    final w = ExportWorld(backend: RecordingComposeBackend(result: (_) => big));
    final ids = [
      for (final t in ['a', 'b', 'c', 'd']) (await w.note(t, [blankDraft])).id,
    ];
    final result = await w.service.exportNotes(ids, const PdfExportOptions());
    expect(result.stoppedAtSizeLimit, isTrue);
    expect(result.cancelled, isFalse);
    expect(result.items, hasLength(2));
    expect(result.notReachedCount, 2);
    expect(w.backend.plans, hasLength(2));

    // Reaching the limit with the last note is not a stop.
    final w2 = ExportWorld(
      backend: RecordingComposeBackend(result: (_) => big),
    );
    final two = [
      for (final t in ['a', 'b']) (await w2.note(t, [blankDraft])).id,
    ];
    final r2 = await w2.service.exportNotes(two, const PdfExportOptions());
    expect(r2.stoppedAtSizeLimit, isFalse);
    expect(r2.files, hasLength(2));
  });

  test(
    'overall progress: note index, label, fraction never goes back',
    () async {
      final ids = await notes(['a', 'b', 'c']);
      final seen = <PdfBatchProgress>[];
      await w.service.exportNotes(
        ids,
        const PdfExportOptions(),
        onProgress: seen.add,
      );
      expect(seen.first.noteIndex, 0);
      expect(seen.first.noteCount, 3);
      expect(seen.last.noteIndex, 2);
      expect(seen.last.fraction, 1.0);
      for (var i = 1; i < seen.length; i++) {
        expect(
          seen[i].fraction,
          greaterThanOrEqualTo(seen[i - 1].fraction),
          reason: '${seen[i - 1]} → ${seen[i]}',
        );
      }
      expect(
        seen.firstWhere((p) => p.noteIndex == 1).label,
        '노트 2/3 · 내보낼 준비 중',
      );
      expect(
        seen
            .firstWhere(
              (p) =>
                  p.noteIndex == 1 && p.current.phase == PdfJobPhase.composing,
            )
            .label,
        '노트 2/3 · 페이지 합성 중 (0/2)',
      );
    },
  );

  test('busy is shared: a single export while a batch runs and the other way round', () async {
    final ids = await notes(['a', 'b']);
    for (final page in await w.gateway.pagesOf(ids.first)) {
      w.addStroke(page.id);
    }
    final hold = Completer<void>();
    w.backend.beforeAddPages = () => hold.future;
    final batch = w.service.exportNotes(ids, const PdfExportOptions());
    await pumpEventQueue();
    await expectLater(
      w.service.exportNote(ids.last, const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.busy)),
    );
    await expectLater(
      w.service.exportNotes(ids, const PdfExportOptions()),
      throwsA(hasCode(PdfErrorCode.busy)),
    );
    hold.complete();
    expect((await batch).files, hasLength(2));
  });

  group('pdfBatchExportJobProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [pdfExportServiceProvider.overrideWithValue(w.service)],
      );
      addTearDown(container.dispose);
    });

    test('Running → Finished (the same result object); reset → idle', () async {
      final ids = await notes(['a', 'b']);
      final job = container.read(pdfBatchExportJobProvider.notifier);
      expect(
        container.read(pdfBatchExportJobProvider),
        const PdfBatchJobIdle(),
      );
      final running = job.run(ids, const PdfExportOptions());
      expect(
        container.read(pdfBatchExportJobProvider),
        const PdfBatchJobRunning(
          PdfBatchProgress(
            noteIndex: 0,
            noteCount: 2,
            current: PdfProgress(PdfJobPhase.preparingExport),
          ),
        ),
      );
      expect(job.isBusy, isTrue);
      final result = await running;
      expect(result!.files, hasLength(2));
      expect(
        container.read(pdfBatchExportJobProvider),
        PdfBatchJobFinished(result),
      );
      job.reset();
      expect(
        container.read(pdfBatchExportJobProvider),
        const PdfBatchJobIdle(),
      );
    });

    test('an empty list finishes at once with no items', () async {
      final job = container.read(pdfBatchExportJobProvider.notifier);
      final result = await job.run(const [], const PdfExportOptions());
      expect(result!.requestedCount, 0);
      expect(result.items, isEmpty);
      expect(w.backend.plans, isEmpty);
    });

    test('cancel → Finished with cancelled and the files made', () async {
      final ids = await notes(['a', 'b']);
      for (final page in await w.gateway.pagesOf(ids.last)) {
        w.addStroke(page.id);
      }
      final hold = Completer<void>();
      w.backend.beforeAddPages = () => hold.future;
      final job = container.read(pdfBatchExportJobProvider.notifier);
      final running = job.run(ids, const PdfExportOptions());
      await pumpEventQueue();
      job.cancel();
      final result = await running;
      expect(result!.cancelled, isTrue);
      expect(result.files.single.fileName, 'a.pdf');
      expect(
        container.read(pdfBatchExportJobProvider),
        PdfBatchJobFinished(result),
      );
      hold.complete();
    });

    test('one PDF job at a time across the export and batch jobs', () async {
      final ids = await notes(['a']);
      for (final page in await w.gateway.pagesOf(ids.single)) {
        w.addStroke(page.id);
      }
      final hold = Completer<void>();
      w.backend.beforeAddPages = () => hold.future;
      final single = container.read(pdfExportJobProvider.notifier);
      final batch = container.read(pdfBatchExportJobProvider.notifier);
      final running = single.run(ids.single, const PdfExportOptions());
      await pumpEventQueue();
      expect(batch.isBusy, isTrue);
      expect(await batch.run(ids, const PdfExportOptions()), isNull);
      expect(
        container.read(pdfBatchExportJobProvider),
        const PdfBatchJobFailed(PdfIoException(PdfErrorCode.busy)),
      );
      hold.complete();
      await running;
      expect(batch.isBusy, isFalse);

      // And the other way round.
      final hold2 = Completer<void>();
      w.backend.beforeAddPages = () => hold2.future;
      final runningBatch = batch.run(ids, const PdfExportOptions());
      await pumpEventQueue();
      expect(single.isBusy, isTrue);
      expect(await single.run(ids.single, const PdfExportOptions()), isNull);
      expect(
        container.read(pdfExportJobProvider),
        const PdfJobFailed<PdfExportResult>(PdfIoException(PdfErrorCode.busy)),
      );
      expect(await batch.run(ids, const PdfExportOptions()), isNull);
      expect(
        container.read(pdfBatchExportJobProvider),
        isA<PdfBatchJobRunning>(),
      );
      hold2.complete();
      await runningBatch;
    });

    test('engineUnavailable → Failed', () async {
      final ids = await notes(['a']);
      w.backend.beginError = const PdfIoException(
        PdfErrorCode.engineUnavailable,
      );
      final job = container.read(pdfBatchExportJobProvider.notifier);
      expect(await job.run(ids, const PdfExportOptions()), isNull);
      expect(
        container.read(pdfBatchExportJobProvider),
        const PdfBatchJobFailed(PdfIoException(PdfErrorCode.engineUnavailable)),
      );
    });
  });
}
