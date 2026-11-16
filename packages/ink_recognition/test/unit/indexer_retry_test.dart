// (handwriting search — m5-7/05-library 6.9.6, 6.19a) the indexer's retries:
// a page whose ink failed in the engine is tried again on the next launch
// and when the model turns ready; indexDirtyPagesNow (the library search
// opened) recognizes the pages waiting for their quiet time at once.
@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/indexer/handwriting_indexer.dart'
    show
        IndexerTuning,
        catchUpRunningOf,
        indexDirtyPagesNow,
        indexNoteNow,
        pendingPagesOfNote;
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/indexer_harness.dart';

void indexerTest(String name, void Function(FakeAsync async) body) =>
    test(name, () => fakeAsync(body));

List<FlutterErrorDetails> captureReports() {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  addTearDown(() => FlutterError.onError = previous);
  return reports;
}

void main() {
  indexerTest('a failed page is tried again on the next launch', (async) {
    captureReports();
    final h = IndexerHarness(async);
    h.addStrokes(h.lines());
    h.recognizer.failNext = RecognizerEngineError('timeout', 'slow');
    h.elapse(IndexerTuning.localQuiet);
    expect(h.status.failedPages, 1);
    expect(h.stored(), isNull);
    final first = h.recognizer.calls.length;
    h.wait(h.indexer.dispose());

    // The next launch: a new indexer over the same store.
    final enabled = ValueNotifier<bool>(true);
    final foreground = ValueNotifier<bool>(true);
    final next = HandwritingIndexer(
      store: h.store,
      recognizer: h.recognizer,
      enabled: enabled,
      foreground: foreground,
    )..start();
    h.settle();
    expect(h.recognizer.calls.length, greaterThan(first));
    expect(h.stored()?.lines, hasLength(3));
    expect(next.status.value.failedPages, 0);
    h.wait(next.dispose());
    enabled.dispose();
    foreground.dispose();
    h.dispose();
  });

  indexerTest('a failed page is tried again when the model turns ready', (
    async,
  ) {
    captureReports();
    final recognizer = FakeHandwritingRecognizer()..enforcesWifiOnly = false;
    final h = IndexerHarness(async, recognizer: recognizer, pages: 2);
    h.addStrokes(h.lines());
    recognizer.failNext = RecognizerEngineError('timeout', 'slow');
    h.elapse(IndexerTuning.localQuiet);
    expect(h.status.failedPages, 1);

    // Another page meets a model that went away → waitingModel.
    final other = h.pageIds[1];
    h.addStrokes(h.lines(pageId: other), pageId: other);
    recognizer.failNext = ModelNotReady('ko');
    h.elapse(IndexerTuning.localQuiet);
    expect(h.phase, HandwritingIndexerPhase.waitingModel);

    // The user downloads it (iPad): both pages are indexed.
    h.wait(recognizer.ensureModel('ko'));
    h.settle();
    expect(h.stored()?.lines, hasLength(3));
    expect(h.stored(pageId: other)?.lines, hasLength(3));
    expect(h.status.failedPages, 0);
    expect(h.phase, HandwritingIndexerPhase.idle);
    h.dispose();
  });

  indexerTest('indexDirtyPagesNow: pages waiting for their quiet time are '
      'recognized at once', (async) {
    final h = IndexerHarness(async);
    h.addStrokes(h.lines());
    expect(h.phase, HandwritingIndexerPhase.waitingInput);
    expect(h.recognizer.calls, isEmpty);
    indexDirtyPagesNow(h.indexer);
    h.settle();
    expect(h.recognizer.calls, hasLength(3));
    expect(h.stored()?.lines, hasLength(3));
    expect(h.phase, HandwritingIndexerPhase.idle);
    // Nothing more when the old quiet time would have ended.
    h.elapse(IndexerTuning.localQuiet);
    expect(h.recognizer.calls, hasLength(3));
    h.dispose();
  });

  indexerTest('indexDirtyPagesNow while disabled does nothing', (async) {
    final h = IndexerHarness(async, enabled: false);
    h.addStrokes(h.lines());
    indexDirtyPagesNow(h.indexer);
    h.elapse(IndexerTuning.localQuiet);
    expect(h.recognizer.calls, isEmpty);
    expect(h.phase, HandwritingIndexerPhase.disabled);
    h.dispose();
  });

  indexerTest('catchUpRunningOf is true while the start-up catch-up looks '
      'for stale pages', (async) {
    final h = IndexerHarness(async);
    h.wait(h.indexer.dispose());
    final enabled = ValueNotifier<bool>(true);
    final foreground = ValueNotifier<bool>(true);
    final next = HandwritingIndexer(
      store: h.store,
      recognizer: h.recognizer,
      enabled: enabled,
      foreground: foreground,
    );
    expect(catchUpRunningOf(next).value, isFalse);
    next.start();
    expect(catchUpRunningOf(next).value, isTrue);
    h.settle();
    expect(catchUpRunningOf(next).value, isFalse);
    h.wait(next.dispose());
    enabled.dispose();
    foreground.dispose();
    h.dispose();
  });

  indexerTest('(in-note search) indexNoteNow: that note\'s pages are '
      'recognized before the other notes\' pages', (async) {
    final h = IndexerHarness(
      async,
      recognizer: FakeHandwritingRecognizer(
        latency: const Duration(milliseconds: 100),
      ),
    );
    final (other, otherPages) = h.newNote('other', pages: 2);
    // The other note's pages were written first, then this note's page.
    for (final p in otherPages) {
      h.addStrokes(
        h.lines(pageId: p),
        pageId: p,
        noteId: other.id,
      );
    }
    h.addStrokes(h.lines());
    expect(pendingPagesOfNote(h.indexer, h.note.id), 1);
    expect(pendingPagesOfNote(h.indexer, other.id), 2);
    h.wait(indexNoteNow(h.indexer, h.note.id));
    // The first job is this note's page, although it was written last.
    expect(h.status.currentPageId, h.pageId);
    expect(pendingPagesOfNote(h.indexer, h.note.id), 1);
    // 3 lines × 100 ms: this page is done, the other note's are not.
    h.elapse(const Duration(milliseconds: 350));
    expect(h.stored()?.lines, hasLength(3));
    expect(pendingPagesOfNote(h.indexer, h.note.id), 0);
    expect(pendingPagesOfNote(h.indexer, other.id), greaterThan(0));
    h.elapse(const Duration(seconds: 3));
    expect(pendingPagesOfNote(h.indexer, other.id), 0);
    h.dispose();
  });

  indexerTest('(in-note search) a page parked after 5 drops in a row still '
      'counts as pending for its note', (async) {
    final h = IndexerHarness(
      async,
      recognizer: FakeHandwritingRecognizer(
        latency: const Duration(milliseconds: 100),
      ),
    );
    h.addStrokes(h.lines());
    h.elapse(IndexerTuning.localQuiet);
    for (var i = 0; i < IndexerTuning.maxDropsInRow; i++) {
      h.elapseMs(50); // a line in flight
      h.put(
        core.HandwritingText(
          noteId: h.note.id,
          pageId: h.pageId,
          engineId: 'sheet:ko',
          sourceRev: 'drop$i',
          lines: const [],
          createdAt: 1,
        ),
      );
      h.elapseMs(50); // dropped
    }
    // Parked for dropDeferral: not in the queue, not quiet, no job.
    expect(h.status.queuedPages, 1);
    expect(pendingPagesOfNote(h.indexer, h.note.id), 1);
    h.elapse(IndexerTuning.dropDeferral + const Duration(seconds: 1));
    expect(pendingPagesOfNote(h.indexer, h.note.id), 0);
    h.dispose();
  });

  indexerTest('(in-note search) indexNoteNow queues a stale page of the note '
      'that nothing else would queue', (async) {
    final h = IndexerHarness(
      async,
      recognizer: FakeHandwritingRecognizer(
        latency: const Duration(milliseconds: 100),
      ),
    );
    h.addStrokes(h.lines());
    h.elapse(IndexerTuning.localQuiet + const Duration(seconds: 1));
    final done = h.stored()!;
    expect(done.sourceRev, h.revOf());
    // Another device wrote an old result: the page is stale, but no stroke
    // changed, so the indexer does not queue it.
    h.put(
      core.HandwritingText(
        noteId: h.note.id,
        pageId: h.pageId,
        engineId: done.engineId,
        sourceRev: 'old',
        lines: done.lines,
        createdAt: done.createdAt,
        updatedAt: done.updatedAt + 1,
      ),
    );
    h.elapse(IndexerTuning.localQuiet);
    expect(h.stored()?.sourceRev, 'old');
    expect(pendingPagesOfNote(h.indexer, h.note.id), 0);
    final indexed = h.status.indexedPages;
    h.wait(indexNoteNow(h.indexer, h.note.id));
    // (the stored lines are reused: no engine call, no latency)
    h.elapse(const Duration(seconds: 1));
    expect(h.status.indexedPages, indexed + 1);
    expect(pendingPagesOfNote(h.indexer, h.note.id), 0);
    expect(h.stored()?.sourceRev, h.revOf());
    h.dispose();
  });
}
