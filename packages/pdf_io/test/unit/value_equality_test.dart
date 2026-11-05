// Value equality of pdf_io state classes (contract 00-overview 7.4.4, 06-pdf 4 intro,
// PDF-3-2). Real from B4 (06-pdf 8 T0: value types' ==/hashCode are pure calculation):
// separately built equal values are == with equal hashCode; payloads holding bytes keep
// identity equality.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';

void _same(Object a, Object b) {
  expect(identical(a, b), isFalse, reason: 'build the two values separately');
  expect(a, b);
  expect(a.hashCode, b.hashCode);
}

void _different(Object a, Object b) {
  expect(a == b, isFalse, reason: '$a == $b');
}

PdfRenderStats _stats({int queued = 0, double p95 = 0}) => PdfRenderStats(
  previewBytes: 0,
  tileBytes: 0,
  thumbnailBytes: 0,
  liveImages: 0,
  queued: queued,
  inflight: 0,
  rendered: 0,
  cancelled: 0,
  lastRenderMs: 0,
  p95RenderMs: p95,
  openDocuments: 0,
  overBudgetBytes: 0,
);

PdfImportResult _importResult({List<String>? pages, bool created = true}) =>
    PdfImportResult(
      noteId: 'n1',
      insertedPageIds: pages ?? ['p1', 'p2'],
      assetId: 'a1',
      sourcePageCount: 2,
      storedDecryptedCopy: false,
      createdNewNote: created,
    );

PdfSearchHit _hit({double left = 10, String page = 'p1'}) => PdfSearchHit(
  pageId: page,
  notePageNumber: 1,
  assetId: 'a1',
  pdfPageIndex: 0,
  rects: [ui.Rect.fromLTWH(left, 20, 30, 12)],
  snippet: '강의 자료',
  matchStart: 0,
  matchLength: 2,
);

PdfExportResult _export() => PdfExportResult(
  bytes: Uint8List.fromList([37, 80, 68, 70]),
  fileName: 'a.pdf',
  pageCount: 1,
  elapsed: Duration.zero,
);

void main() {
  test('config: PdfImportLimits, PdfRenderBudget, PdfIoConfig', () {
    _same(
      PdfImportLimits(maxPages: int.parse('10')),
      const PdfImportLimits(maxPages: 10),
    );
    _different(const PdfImportLimits(), const PdfImportLimits(maxPages: 10));
    _same(
      PdfRenderBudget(
        previewBytes: int.parse('1'),
        tileBytes: 2,
        thumbnailBytes: 3,
      ),
      const PdfRenderBudget(previewBytes: 1, tileBytes: 2, thumbnailBytes: 3),
    );
    _different(const PdfRenderBudget.web(), const PdfRenderBudget.native());
    _same(
      PdfIoConfig(pdfiumWasmModulesUrl: 'pdfium/'.toString()),
      const PdfIoConfig(pdfiumWasmModulesUrl: 'pdfium/'),
    );
    _different(const PdfIoConfig(), const PdfIoConfig(warmUpOnStart: false));
    _different(
      const PdfIoConfig(),
      const PdfIoConfig(limits: PdfImportLimits(maxBytes: 1)),
    );
    _different(
      const PdfIoConfig(),
      const PdfIoConfig(renderBudget: PdfRenderBudget.web()),
    );
    _different(
      const PdfIoConfig(),
      const PdfIoConfig(userPasswordPolicy: PdfUserPasswordPolicy.refuse),
    );
  });

  test('PdfIoException: code and detail, cause ignored', () {
    _same(
      PdfIoException(PdfErrorCode.corrupt, detail: 'x', cause: Object()),
      PdfIoException(PdfErrorCode.corrupt, detail: 'x', cause: Object()),
    );
    _different(
      const PdfIoException(PdfErrorCode.corrupt, detail: 'x'),
      const PdfIoException(PdfErrorCode.corrupt, detail: 'y'),
    );
    _different(
      const PdfIoException(PdfErrorCode.corrupt),
      const PdfIoException(PdfErrorCode.notPdf),
    );
  });

  test('PdfProgress and PdfBatchProgress', () {
    _same(
      PdfProgress(PdfJobPhase.composing, done: int.parse('3'), total: 8),
      const PdfProgress(PdfJobPhase.composing, done: 3, total: 8),
    );
    _different(
      const PdfProgress(PdfJobPhase.composing, done: 3, total: 8),
      const PdfProgress(PdfJobPhase.composing, done: 4, total: 8),
    );
    _different(
      const PdfProgress(PdfJobPhase.openingPdf),
      const PdfProgress(PdfJobPhase.readingFile),
    );
    _same(
      PdfBatchProgress(
        noteIndex: int.parse('1'),
        noteCount: 3,
        current: const PdfProgress(PdfJobPhase.composing, done: 1, total: 2),
      ),
      const PdfBatchProgress(
        noteIndex: 1,
        noteCount: 3,
        current: PdfProgress(PdfJobPhase.composing, done: 1, total: 2),
      ),
    );
    _different(
      const PdfBatchProgress(
        noteIndex: 1,
        noteCount: 3,
        current: PdfProgress(PdfJobPhase.composing),
      ),
      const PdfBatchProgress(
        noteIndex: 2,
        noteCount: 3,
        current: PdfProgress(PdfJobPhase.composing),
      ),
    );
  });

  test('PdfImportResult: every field, page ids with ListEquality', () {
    _same(_importResult(), _importResult());
    _different(_importResult(), _importResult(pages: ['p1']));
    _different(_importResult(), _importResult(created: false));
  });

  test('PdfJobState: same subtype and type argument, fields with ==', () {
    _same(PdfJobIdle<PdfImportResult>(), PdfJobIdle<PdfImportResult>());
    _different(
      const PdfJobIdle<PdfImportResult>(),
      const PdfJobIdle<PdfExportResult>(),
    );
    _same(
      PdfJobRunning<PdfImportResult>(
        PdfProgress(PdfJobPhase.storingPdf, done: int.parse('1')),
      ),
      const PdfJobRunning<PdfImportResult>(
        PdfProgress(PdfJobPhase.storingPdf, done: 1),
      ),
    );
    _different(
      const PdfJobRunning<PdfImportResult>(PdfProgress(PdfJobPhase.storingPdf)),
      const PdfJobRunning<PdfExportResult>(PdfProgress(PdfJobPhase.storingPdf)),
    );
    // insertedPageIds are different list objects with the same ids.
    _same(
      PdfJobSucceeded<PdfImportResult>(_importResult()),
      PdfJobSucceeded<PdfImportResult>(_importResult()),
    );
    // Export results hold bytes: identity only.
    final export = _export();
    _different(
      PdfJobSucceeded<PdfExportResult>(export),
      PdfJobSucceeded<PdfExportResult>(_export()),
    );
    _same(
      PdfJobSucceeded<PdfExportResult>(export),
      PdfJobSucceeded<PdfExportResult>(export),
    );
    _same(
      PdfJobFailed<PdfExportResult>(
        PdfIoException(PdfErrorCode.cancelled, cause: Object()),
      ),
      const PdfJobFailed<PdfExportResult>(
        PdfIoException(PdfErrorCode.cancelled),
      ),
    );
    _different(
      const PdfJobFailed<PdfExportResult>(PdfIoException(PdfErrorCode.busy)),
      const PdfJobFailed<PdfExportResult>(
        PdfIoException(PdfErrorCode.cancelled),
      ),
    );
    _different(
      const PdfJobIdle<PdfImportResult>(),
      const PdfJobFailed<PdfImportResult>(PdfIoException(PdfErrorCode.busy)),
    );
  });

  test('PdfBatchJobState', () {
    _same(PdfBatchJobIdle(), PdfBatchJobIdle());
    const progress = PdfBatchProgress(
      noteIndex: 0,
      noteCount: 2,
      current: PdfProgress(PdfJobPhase.composing),
    );
    _same(
      PdfBatchJobRunning(
        PdfBatchProgress(
          noteIndex: int.parse('0'),
          noteCount: 2,
          current: const PdfProgress(PdfJobPhase.composing),
        ),
      ),
      const PdfBatchJobRunning(progress),
    );
    final result = PdfBatchExportResult(requestedCount: 1, items: const []);
    _same(PdfBatchJobFinished(result), PdfBatchJobFinished(result));
    _different(
      PdfBatchJobFinished(result),
      PdfBatchJobFinished(
        PdfBatchExportResult(requestedCount: 1, items: const []),
      ),
    );
    _same(
      PdfBatchJobFailed(PdfIoException(PdfErrorCode.busy, cause: Object())),
      const PdfBatchJobFailed(PdfIoException(PdfErrorCode.busy)),
    );
    _different(
      const PdfBatchJobFailed(PdfIoException(PdfErrorCode.busy)),
      const PdfBatchJobFailed(PdfIoException(PdfErrorCode.engineUnavailable)),
    );
    _different(const PdfBatchJobIdle(), const PdfBatchJobRunning(progress));
  });

  test(
    'PdfRenderStats: all twelve fields; ValueNotifier skips equal values',
    () {
      _same(_stats(), _stats());
      expect(_stats(), PdfRenderStats.zero);
      _different(_stats(), _stats(queued: 1));
      _different(_stats(), _stats(p95: 0.5));

      final notifier = ValueNotifier(PdfRenderStats.zero);
      addTearDown(notifier.dispose);
      var calls = 0;
      notifier.addListener(() => calls++);
      notifier.value = _stats();
      expect(calls, 0);
      notifier.value = _stats(queued: 2);
      expect(calls, 1);
    },
  );

  test('PdfSearchHit and PdfSearchState: deep list equality', () {
    _same(_hit(), _hit());
    _different(_hit(), _hit(left: 11));
    _different(_hit(), _hit(page: 'p2'));
    _same(
      PdfSearchState(
        noteId: 'n1',
        query: '강의',
        status: PdfSearchStatus.done,
        scannedPages: 3,
        totalPages: 3,
        hits: [
          _hit(),
          _hit(page: 'p2'),
        ],
        currentIndex: 1,
        error: PdfIoException(PdfErrorCode.assetMissing, cause: Object()),
      ),
      PdfSearchState(
        noteId: 'n1',
        query: '강의',
        status: PdfSearchStatus.done,
        scannedPages: 3,
        totalPages: 3,
        hits: [
          _hit(),
          _hit(page: 'p2'),
        ],
        currentIndex: 1,
        error: const PdfIoException(PdfErrorCode.assetMissing),
      ),
    );
    _different(
      PdfSearchState(hits: [_hit()]),
      PdfSearchState(hits: [_hit(left: 11)]),
    );
    _different(PdfSearchState.idle, const PdfSearchState(query: 'a'));
    expect(PdfSearchState(hits: [_hit()], currentIndex: 0).current, _hit());
  });
}
