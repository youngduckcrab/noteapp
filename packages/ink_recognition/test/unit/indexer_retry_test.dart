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
    show IndexerTuning, indexDirtyPagesNow;
import 'package:ink_recognition/testing.dart';

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
}
