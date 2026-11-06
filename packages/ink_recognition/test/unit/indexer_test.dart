// HandwritingIndexer ① — schedule, page jobs, errors, status
// (m5-7/05-library 8.2 L2-10a, 4.4.1, 4.4.7, 6.9.1–6.9.3, 6.9.6, 6.9.7;
// ② L2-10b — line reuse, confirmed lines, other writers during a job, 6.9.4;
// contract 7.2.11). fakeAsync + createFakeNoteStore() (through
// RecordingNoteStore — call counts, remote origin) + FakeHandwritingRecognizer
// + foreground: ValueNotifier. Only Timer time is asserted (fake_async); the
// 1,000-stroke job record is real CPU time, printed, with a 3× fail limit.
@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/indexer/handwriting_indexer.dart'
    show IndexerTuning, groupTraceIndicesInBackground, metricsOf;
import 'package:ink_recognition/src/indexer/line_reuse.dart'
    show mergeConfirmed;
import 'package:ink_recognition/src/lines/glyph_boxes.dart'
    show estimateGlyphHeight;
import 'package:ink_recognition/src/lines/group_into_lines.dart'
    show groupTraceIndices;
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/indexer_harness.dart';

void indexerTest(String name, void Function(FakeAsync async) body) =>
    test(name, () => fakeAsync(body));

/// Lines groupIntoLines makes of [strokes] (what the indexer sends).
int linesOf(List<core.Stroke> strokes) =>
    groupIntoLines([for (final s in strokes) HandwritingTrace.fromStroke(s)])
        .length;

/// The synthetic line of a stroke id `'syn_<seed>_l<line>_<n>'`.
int trueLineOf(String id) => int.parse(id.split('_')[2].substring(1));

List<FlutterErrorDetails> captureReports() {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  addTearDown(() => FlutterError.onError = previous);
  return reports;
}

/// Every handwriting EntityChange the store emits, counted.
int Function() countHandwritingChanges(IndexerHarness h) {
  var n = 0;
  final sub = h.store.changes.listen((b) {
    n += b.changes.where((c) => c.kind == core.EntityKind.handwriting).length;
  });
  addTearDown(sub.cancel);
  return () => n;
}

/// The conversion sheet's copy (6.13.5): line [index] of the stored value
/// (or of the synthetic truth when nothing is stored) confirmed as [text].
void confirmLine(
  IndexerHarness h,
  List<core.Stroke> strokes,
  int index,
  String text, {
  bool all = false,
}) {
  final ids = [
    for (final s in strokes)
      if (trueLineOf(s.id) == index) s.id,
  ];
  final rect = strokes
      .where((s) => trueLineOf(s.id) == index)
      .map((s) => s.points.pointBounds)
      .reduce((a, b) => a.expandToInclude(b));
  h.wait(
    h.store.inner.handwriting.update(
      h.pageId,
      (current) => mergeConfirmed(
        current,
        [
          core.HandwritingLine(
            text: text,
            rect: rect,
            strokeIds: ids,
            userConfirmed: true,
          ),
        ],
        noteId: h.note.id,
        pageId: h.pageId,
        rev: h.revOf(),
        all: all,
        engineId: 'fake:ko',
        nowMs: 1,
      ),
    ),
  );
  h.settle();
}

/// A stroke from [points] (page pt), drawn after the synthetic lines.
core.Stroke strokeAt(
  core.Stroke like,
  String id,
  List<(double, double)> points,
) => core.Stroke(
  id: id,
  pageId: like.pageId,
  style: like.style,
  points: core.StrokePoints.fromList([
    for (final (i, (x, y)) in points.indexed)
      core.StrokePoint(x, y, t: 8.0 * i),
  ]),
  createdAt: 1730800000000,
);

void main() {
  group('schedule (6.9.2)', () {
    indexerTest('a local stroke change: nothing at 2,999 ms; at 3,000 ms one '
        'engine call per line and one write', (async) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      final lineCount = linesOf(strokes);
      expect(lineCount, 3);
      h.addStrokes(strokes);
      expect(h.phase, HandwritingIndexerPhase.waitingInput);
      expect(h.status.queuedPages, 1);

      h.elapseMs(2999);
      expect(h.recognizer.calls, isEmpty);
      expect(h.store.count('loadPage:'), 0);
      expect(h.store.count('stalePages:'), 0);

      h.elapseMs(1);
      expect(h.recognizer.calls, hasLength(lineCount));
      expect(h.store.count('update:'), 1);
      expect(h.store.handwritingWrites, 1);
      expect(h.store.count('loadPage:'), 1);
      expect(h.status.phase, HandwritingIndexerPhase.idle);
      expect(h.status.indexedPages, 1);
      expect(h.status.queuedPages, 0);

      // Our own write comes back as a local handwriting change: no new job.
      h.elapse(const Duration(minutes: 2));
      expect(h.recognizer.calls, hasLength(lineCount));
      expect(h.store.handwritingWrites, 1);
      h.dispose();
    });

    indexerTest('the stored result: lines in reading order, engine text and '
        'alternatives, strokes, rect, language, engine id, sourceRev', (async) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      final highlighter = core_testing.StrokeFixtures.synthetic(
        pageId: h.pageId,
        ids: h.store.ids,
        seed: 9,
        tool: core.PenTool.highlighter,
        createdAt: 1730790100000,
      );
      h.addStrokes([...strokes, highlighter]);
      h.elapse(IndexerTuning.localQuiet);

      final stored = h.stored()!;
      expect(stored.noteId, h.note.id);
      expect(stored.pageId, h.pageId);
      expect(stored.engineId, 'fake:ko');
      expect(stored.sourceRev, h.revOf());
      expect(stored.createdAt, kHarnessStart.millisecondsSinceEpoch + 3000);
      expect(stored.lines.map((l) => l.text), ['줄 1', '줄 2', '줄 3']);
      for (final (i, line) in stored.lines.indexed) {
        expect(line.alternatives, ['줄 ${i + 1}?', '줄 ${i + 1}!']);
        expect(line.languageTag, 'ko');
        expect(line.userConfirmed, isFalse);
        // Every stroke of synthetic line i, no highlighter.
        expect(line.strokeIds.map(trueLineOf).toSet(), {i});
        expect(line.strokeIds.toSet(), {
          for (final s in strokes)
            if (trueLineOf(s.id) == i) s.id,
        });
        final byId = {for (final s in strokes) s.id: s};
        final union = line.strokeIds
            .map((id) => byId[id]!.points.pointBounds)
            .reduce((a, b) => a.expandToInclude(b));
        expect(line.rect, union);
      }

      // The engine input: traces of the line, the previous line's text as
      // preContext, the page width and max(line height × 1.5, 24).
      final (first, firstLang) = h.recognizer.calls[0];
      final (second, _) = h.recognizer.calls[1];
      expect(firstLang, 'ko');
      expect(first.preContext, '');
      expect(second.preContext, '줄 1');
      expect(
        first.traces.map((t) => t.strokeId).toSet(),
        stored.lines[0].strokeIds.toSet(),
      );
      expect(first.writingAreaPt!.width, core.PageSize.a4Portrait.width);
      expect(
        first.writingAreaPt!.height,
        moreOrLessEquals(
          [
            stored.lines[0].rect.height * 1.5,
            24.0,
          ].reduce((a, b) => a > b ? a : b),
        ),
      );
      h.dispose();
    });

    indexerTest('a remote change waits 30 s', (async) {
      final h = IndexerHarness(async);
      h.store.originOverride = core.ChangeOrigin.remote;
      h.addStrokes(h.lines());
      h.store.originOverride = null;
      h.elapseMs(29999);
      expect(h.recognizer.calls, isEmpty);
      expect(h.phase, HandwritingIndexerPhase.waitingInput);
      h.elapseMs(1);
      expect(h.recognizer.calls, hasLength(3));
      expect(h.store.count('update:'), 1);
      h.dispose();
    });

    indexerTest('writing on the same page keeps postponing it; another page '
        'keeps its own timer', (async) {
      final h = IndexerHarness(async, pages: 2);
      final [p1, p2] = h.pageIds;
      final strokes = h.lines(pageId: p1, lineCount: 4);
      h.addStrokes(strokes.sublist(0, 30), pageId: p1);
      h.elapseMs(1000);
      h.addStrokes(h.lines(pageId: p2, seed: 2), pageId: p2);
      h.elapseMs(1000);
      h.addStrokes(strokes.sublist(30, 60), pageId: p1);
      h.elapseMs(2000);
      h.addStrokes(strokes.sublist(60), pageId: p1);
      // p2: last change at 1,000 ms → recognized at 4,000 ms; p1 still
      // waits (last change at 4,000 ms).
      expect(h.store.calls.where((c) => c.startsWith('loadPage:')), [
        'loadPage:$p2',
      ]);
      h.elapseMs(2999);
      expect(h.store.count('loadPage:$p1'), 0);
      h.elapseMs(1);
      expect(h.store.count('loadPage:$p1'), 1);
      expect(h.stored(pageId: p1)!.lines, hasLength(linesOf(strokes)));
      expect(h.stored(pageId: p2), isNotNull);
      expect(h.status.indexedPages, 2);
      h.dispose();
    });

    indexerTest('a stroke change between two lines drops the job (no write); '
        'the page waits its quiet time again', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      final strokes = h.lines(lineCount: 3);
      h.addStrokes(strokes.sublist(0, strokes.length - 1));
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(50); // line 1 in flight
      expect(h.recognizer.calls, hasLength(1));
      expect(h.phase, HandwritingIndexerPhase.recognizing);
      h.addStrokes([strokes.last]);
      h.elapseMs(100); // line 1 answers: the job is dropped
      expect(h.recognizer.calls, hasLength(1));
      expect(h.store.handwritingWrites, 0);
      expect(h.phase, HandwritingIndexerPhase.waitingInput);

      h.elapse(IndexerTuning.localQuiet);
      h.elapse(const Duration(seconds: 1));
      expect(h.recognizer.calls, hasLength(1 + linesOf(strokes)));
      expect(h.store.count('update:'), 1);
      expect(h.stored()!.sourceRev, h.revOf());
      h.dispose();
    });

    indexerTest('a deleted page leaves the queue', (async) {
      final h = IndexerHarness(async, pages: 2);
      final [p1, p2] = h.pageIds;
      h.addStrokes(h.lines(pageId: p2), pageId: p2);
      h.execute(core.DeletePages(pageIds: [p2]), pageId: p1);
      expect(h.status.queuedPages, 0);
      h.elapse(const Duration(seconds: 10));
      expect(h.recognizer.calls, isEmpty);
      expect(h.store.count('loadPage:'), 0);
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.dispose();
    });
  });

  group('page jobs (6.9.3)', () {
    indexerTest('a fresh page: stalePages + forPage only — loadPage 0, '
        'engine 0, writes 0', (async) {
      final h = IndexerHarness(async);
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      expect(h.store.count('loadPage:'), 1);
      h.store.calls.clear();
      final engineCalls = h.recognizer.calls.length;

      h.touchPage(); // page change, same strokes
      h.elapse(IndexerTuning.localQuiet);
      expect(h.store.calls, [
        'flush',
        'stalePages:${h.note.id}',
        'forPage:${h.pageId}',
      ]);
      expect(h.recognizer.calls, hasLength(engineCalls));
      h.dispose();
    });

    indexerTest('only the language differs → recognized again in the new '
        'language', (async) {
      final h = IndexerHarness(async);
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      expect(h.stored()!.engineId, 'fake:ko');

      h.setLanguage('en');
      expect(h.status.languageTag, 'en');
      h.touchPage();
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(6));
      expect(h.recognizer.calls.skip(3).map((c) => c.$2).toSet(), {'en'});
      final stored = h.stored()!;
      expect(stored.engineId, 'fake:en');
      expect(stored.lines.map((l) => l.languageTag).toSet(), {'en'});
      expect(h.store.count('update:'), 2);
      h.dispose();
    });

    indexerTest('a result of another engine id / version / device with the '
        'same sourceRev and language is fresh — engine 0, writes 0', (async) {
      final h = IndexerHarness(async);
      h.addStrokes(h.lines());
      final other = core.HandwritingText(
        noteId: h.note.id,
        pageId: h.pageId,
        engineId: 'mlkit-digital-ink-ios/9.0.0:ko',
        sourceRev: h.revOf(),
        lines: const [
          core.HandwritingLine(
            text: '다른 기기',
            rect: core.PageRect(0, 0, 10, 10),
            strokeIds: ['x'],
          ),
        ],
        createdAt: 1,
      );
      h.put(other); // during the quiet time: no job in flight → ignored
      h.store.calls.clear();
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, isEmpty);
      expect(h.store.count('loadPage:'), 0);
      expect(h.store.handwritingWrites, 0);
      expect(h.stored()!.engineId, 'mlkit-digital-ink-ios/9.0.0:ko');
      expect(h.stored()!.lines.single.text, '다른 기기');
      h.dispose();
    });

    indexerTest('no input strokes left → removeForPage', (async) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      h.addStrokes(strokes);
      h.elapse(IndexerTuning.localQuiet);
      expect(h.stored(), isNotNull);

      h.removeStrokes([for (final s in strokes) s.id]);
      h.elapse(IndexerTuning.localQuiet);
      expect(h.store.count('removeForPage:${h.pageId}'), 1);
      expect(h.stored(), isNull);
      expect(h.recognizer.calls, hasLength(3));
      expect(h.status.indexedPages, 2);
      h.dispose();
    });

    indexerTest('highlighter strokes only → nothing is written', (async) {
      final h = IndexerHarness(async);
      h.addStrokes([
        for (var i = 0; i < 3; i++)
          core_testing.StrokeFixtures.synthetic(
            pageId: h.pageId,
            ids: h.store.ids,
            seed: i,
            tool: core.PenTool.highlighter,
          ),
      ]);
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, isEmpty);
      expect(h.store.handwritingWrites, 0);
      expect(h.store.count('loadPage:'), 0);
      expect(h.stored(), isNull);
      h.dispose();
    });
  });

  group('handwriting changes during a job (6.9.2, review M-1)', () {
    indexerTest('before the write: the job is dropped and the page runs again '
        'at once (no new quiet time)', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(150); // line 2 in flight
      h.put(
        core.HandwritingText(
          noteId: h.note.id,
          pageId: h.pageId,
          engineId: 'sheet:ko',
          sourceRev: '0000000000000000',
          lines: const [],
          createdAt: 1,
        ),
      );
      h.elapseMs(50); // line 2 answers → dropped, requeued first
      // The page runs again at once: its first line is already asked.
      expect(h.recognizer.calls, hasLength(3));
      expect(h.store.count('update:'), 0);
      expect(h.status.queuedPages, 0); // already running again
      expect(h.phase, HandwritingIndexerPhase.recognizing);
      h.elapseMs(300); // 3 lines × 100 ms — not 3 s later
      expect(h.recognizer.calls, hasLength(5));
      expect(h.store.count('update:'), 1);
      expect(h.stored()!.engineId, 'fake:ko');
      h.dispose();
    });

    indexerTest('5 drops in a row → the page waits 30 s', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      for (var i = 0; i < 5; i++) {
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
      expect(h.recognizer.calls, hasLength(5));
      expect(h.phase, HandwritingIndexerPhase.waitingInput);
      expect(h.status.queuedPages, 1);
      // The 5th drop was 50 ms ago: 30 s after it the page runs again.
      h.elapseMs(29949);
      expect(h.recognizer.calls, hasLength(5));
      h.elapseMs(1);
      expect(h.recognizer.calls, hasLength(6));
      h.elapseMs(300);
      expect(h.recognizer.calls, hasLength(8));
      expect(h.store.count('update:'), 1);
      h.dispose();
    });
  });

  group('line reuse and confirmed lines (6.9.4 — L2-10b)', () {
    indexerTest('a confirmed line arriving during the job (conversion sheet) '
        '→ job dropped, run again, the confirmed line kept; one indexer '
        'write', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      final changes = countHandwritingChanges(h);
      final strokes = h.lines();
      h.addStrokes(strokes);
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(150); // line 2 in flight
      confirmLine(h, strokes, 0, '고친 첫 줄'); // stored: that line only
      h.elapseMs(50); // line 2 answers: dropped, the page runs again
      h.elapseMs(500);
      final stored = h.stored()!;
      expect(stored.lines, hasLength(3));
      expect(stored.lines[0].text, '고친 첫 줄');
      expect(stored.lines[0].userConfirmed, isTrue);
      expect(stored.lines.skip(1).every((l) => !l.userConfirmed), isTrue);
      expect(stored.sourceRev, h.revOf());
      // 2 calls of the dropped job + lines 2 and 3 (line 1 reused).
      expect(h.recognizer.calls, hasLength(4));
      expect(h.store.count('update:'), 1);
      expect(changes(), 2); // the copy + the indexer
      h.dispose();
    });

    indexerTest('another device\'s result during the job (same sourceRev and '
        'language, another engine id) → dropped, run again, fresh: no engine '
        'call, no write, its value stays', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(150);
      final remote = core.HandwritingText(
        noteId: h.note.id,
        pageId: h.pageId,
        engineId: 'mlkit-digital-ink/19.0.0:ko',
        sourceRev: h.revOf(),
        lines: const [
          core.HandwritingLine(
            text: '안드로이드',
            rect: core.PageRect(0, 0, 10, 10),
            strokeIds: ['x'],
          ),
        ],
        createdAt: 1,
      );
      h.put(remote); // stands in for applyRemote (L2-I1 with the real CORE)
      h.elapse(const Duration(seconds: 5));
      expect(h.recognizer.calls, hasLength(2));
      expect(h.store.count('update:'), 0);
      expect(h.stored()!.engineId, 'mlkit-digital-ink/19.0.0:ko');
      expect(h.stored()!.lines.single.text, '안드로이드');
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.dispose();
    });

    indexerTest('its own write is ignored — no second job', (async) {
      final h = IndexerHarness(async);
      final changes = countHandwritingChanges(h);
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      h.elapse(const Duration(minutes: 5));
      expect(h.store.count('stalePages:'), 1);
      expect(h.store.count('update:'), 1);
      expect(changes(), 1);
      h.dispose();
    });

    indexerTest('moving strokes → no engine call, only the rects change', (
      async,
    ) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      h.addStrokes(strokes);
      h.elapse(IndexerTuning.localQuiet);
      final before = h.stored()!;
      h.execute(
        core.TransformElements(
          pageId: h.pageId,
          elementIds: [
            for (final s in strokes)
              if (trueLineOf(s.id) == 0) s.id,
          ],
          transform: core.Affine2.translation(12, -4),
        ),
      );
      h.elapse(IndexerTuning.localQuiet);
      final after = h.stored()!;
      expect(h.recognizer.calls, hasLength(3));
      expect(h.store.count('update:'), 2);
      expect(after.sourceRev, h.revOf());
      expect(after.sourceRev, isNot(before.sourceRev));
      expect(after.lines.map((l) => l.text), before.lines.map((l) => l.text));
      final r0 = before.lines[0].rect, m0 = after.lines[0].rect;
      expect(m0.left, moreOrLessEquals(r0.left + 12, epsilon: 1e-3));
      expect(m0.top, moreOrLessEquals(r0.top - 4, epsilon: 1e-3));
      expect(after.lines[1].rect, before.lines[1].rect);
      h.dispose();
    });

    indexerTest('a partial eraser → only that line is recognized again', (
      async,
    ) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      h.addStrokes(strokes);
      h.elapse(IndexerTuning.localQuiet);
      final victim = strokes.firstWhere((s) => trueLineOf(s.id) == 1);
      final n = victim.points.length;
      core.StrokePoints part(int from, int to) => core.StrokePoints.fromList([
        for (var i = from; i < to; i++)
          core.StrokePoint(
            victim.points.x(i),
            victim.points.y(i),
            t: victim.points.t(i).toDouble(),
          ),
      ]);
      h.execute(
        core.SplitStrokes(
          pageId: h.pageId,
          removedIds: [victim.id],
          added: [
            victim.fragment(id: 'frag-a', points: part(0, n ~/ 2)),
            victim.fragment(id: 'frag-b', points: part(n ~/ 2 + 1, n)),
          ],
        ),
      );
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(4));
      final stored = h.stored()!;
      expect(stored.lines.map((l) => l.text), ['줄 1', '줄 4', '줄 3']);
      expect(stored.lines[1].strokeIds, containsAll(['frag-a', 'frag-b']));
      expect(stored.lines[1].strokeIds, isNot(contains(victim.id)));
      h.dispose();
    });

    indexerTest('a dot added to a confirmed line → the confirmed text stays', (
      async,
    ) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      h.addStrokes(strokes);
      h.elapse(IndexerTuning.localQuiet);
      confirmLine(h, strokes, 0, '고친 첫 줄', all: true);
      final line0 = h.stored()!.lines[0].rect;
      h.addStrokes([
        strokeAt(strokes.first, 'dot', [
          (line0.right - 3, line0.bottom - 3),
          (line0.right - 2, line0.bottom - 2),
        ]),
      ]);
      h.elapse(IndexerTuning.localQuiet);
      final stored = h.stored()!;
      expect(stored.lines[0].strokeIds, contains('dot'));
      expect(stored.lines[0].text, '고친 첫 줄');
      expect(stored.lines[0].userConfirmed, isTrue);
      // Line 1 changed its stroke set → asked; lines 2 and 3 reused.
      expect(h.recognizer.calls, hasLength(4));
      h.dispose();
    });

    indexerTest('a new syllable added to a confirmed line → the engine text, '
        'the old confirmed text first among the alternatives', (async) {
      final h = IndexerHarness(async);
      final strokes = h.lines();
      h.addStrokes(strokes);
      h.elapse(IndexerTuning.localQuiet);
      confirmLine(h, strokes, 0, '고친 첫 줄', all: true);
      final first = h.stored()!.lines[0];
      final glyph = estimateGlyphHeight([
        for (final s in strokes)
          if (trueLineOf(s.id) == 0) HandwritingTrace.fromStroke(s),
      ]);
      final x0 = first.rect.right + 0.3 * glyph;
      final cy = (first.rect.top + first.rect.bottom) / 2;
      // One zigzag 1.4·H wide and 0.9·H high, centred on the line.
      h.addStrokes([
        strokeAt(strokes.first, 'syllable', [
          for (var i = 0; i <= 14; i++)
            (x0 + 0.1 * glyph * i, cy + (i.isEven ? -0.45 : 0.45) * glyph),
        ]),
      ]);
      h.elapse(IndexerTuning.localQuiet);
      final line = h.stored()!.lines[0];
      expect(line.strokeIds, contains('syllable'));
      expect(line.userConfirmed, isFalse);
      expect(line.text, '줄 4');
      expect(line.alternatives.first, '고친 첫 줄');
      h.dispose();
    });
  });

  group('model (6.7.4, 6.9.6)', () {
    indexerTest('Android: not downloaded → waitingModel (waiting for Wi-Fi) '
        '→ ensureModel once → idle', (async) {
      final recognizer = FakeHandwritingRecognizer()
        ..modelStates['ko'] = RecognitionModelState.notDownloaded;
      final h = IndexerHarness(async, recognizer: recognizer);
      expect(recognizer.ensureModelCalls, 1);
      expect(
        h.statuses.where(
          (s) => s.phase == HandwritingIndexerPhase.waitingModel,
        ),
        isNotEmpty,
      );
      final waiting = h.statuses.firstWhere(
        (s) => s.phase == HandwritingIndexerPhase.waitingModel,
      );
      expect(waiting.lastError, 'model ko: waiting for Wi-Fi');
      expect(
        waiting.toString(),
        'waitingModel · ko · model ko: waiting for Wi-Fi',
      );
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(3));
      h.dispose();
    });

    indexerTest('Android with recog.modelWifiOnly off → "downloading"', (
      async,
    ) {
      final recognizer = FakeHandwritingRecognizer()
        ..modelStates['ko'] = RecognitionModelState.notDownloaded;
      final h = IndexerHarness(async, recognizer: recognizer, start: false);
      h.wait(
        h.store.settings.set(RecognitionSettingsKeys.modelWifiOnly, false),
      );
      h.indexer.start();
      h.settle();
      expect(
        h.statuses.map((s) => s.lastError),
        contains('model ko: downloading'),
      );
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.dispose();
    });

    indexerTest('iOS: not downloaded → waitingModel (not downloaded), no '
        'download of its own; a download by the user → resumes', (async) {
      final recognizer = FakeHandwritingRecognizer()
        ..modelStates['ko'] = RecognitionModelState.notDownloaded
        ..enforcesWifiOnly = false;
      final h = IndexerHarness(async, recognizer: recognizer);
      expect(h.phase, HandwritingIndexerPhase.waitingModel);
      expect(h.status.lastError, 'model ko: not downloaded');
      expect(recognizer.ensureModelCalls, 0);

      h.addStrokes(h.lines());
      h.elapse(const Duration(seconds: 10));
      expect(h.recognizer.calls, isEmpty);
      expect(h.phase, HandwritingIndexerPhase.waitingModel);
      expect(h.status.queuedPages, 1);

      h.wait(recognizer.ensureModel('ko')); // the settings section's [받기]
      h.settle();
      expect(h.recognizer.calls, hasLength(3));
      expect(h.store.count('update:'), 1);
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.dispose();
    });

    indexerTest('ModelNotReady from a line → waitingModel, the page back '
        'first, resumed after the model change', (async) {
      final recognizer = FakeHandwritingRecognizer()..enforcesWifiOnly = false;
      final h = IndexerHarness(async, recognizer: recognizer);
      h.addStrokes(h.lines());
      recognizer.failNext = ModelNotReady('ko');
      h.elapse(IndexerTuning.localQuiet);
      expect(recognizer.calls, hasLength(1));
      expect(h.phase, HandwritingIndexerPhase.waitingModel);
      expect(h.status.lastError, 'model ko: not downloaded');
      expect(h.status.queuedPages, 1);
      expect(h.status.failedPages, 0);
      expect(h.store.handwritingWrites, 0);

      h.wait(recognizer.ensureModel('ko'));
      h.settle();
      expect(recognizer.calls, hasLength(4));
      expect(h.store.count('update:'), 1);
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.dispose();
    });

    indexerTest('ModelNotReady on Android → ensureModel, then the page', (
      async,
    ) {
      final h = IndexerHarness(async);
      h.addStrokes(h.lines());
      h.recognizer.failNext = ModelNotReady('ko');
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.ensureModelCalls, 1);
      expect(h.recognizer.calls, hasLength(4));
      expect(h.store.count('update:'), 1);
      expect(
        h.statuses.map((s) => s.phase),
        contains(HandwritingIndexerPhase.waitingModel),
      );
      h.dispose();
    });
  });

  group('errors (6.9.6)', () {
    indexerTest('an engine error → failed 1, one report, the same ink is '
        'not tried again; new ink is', (async) {
      final reports = captureReports();
      final h = IndexerHarness(async);
      final strokes = h.lines();
      h.addStrokes(strokes.sublist(0, strokes.length - 1));
      h.recognizer.failNext = RecognizerEngineError('timeout', 'slow');
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(1));
      expect(h.status.failedPages, 1);
      expect(h.status.indexedPages, 0);
      expect(h.store.handwritingWrites, 0);
      expect(reports, hasLength(1));
      expect(reports.single.library, 'ink_recognition');
      expect(reports.single.exception, isA<RecognizerEngineError>());
      expect(h.phase, HandwritingIndexerPhase.idle);

      h.touchPage(); // same ink
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(1));
      expect(reports, hasLength(1));

      h.addStrokes([strokes.last]); // new ink
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(1 + linesOf(strokes)));
      expect(h.store.count('update:'), 1);
      expect(h.status.failedPages, 0);
      expect(reports, hasLength(1));
      h.dispose();
    });

    indexerTest('a CORE write failure → one report, failed', (async) {
      final reports = captureReports();
      final h = IndexerHarness(async);
      h.addStrokes(h.lines());
      h.store.failNextUpdate = StateError('disk full');
      h.elapse(IndexerTuning.localQuiet);
      expect(h.store.count('update:'), 1);
      expect(h.stored(), isNull);
      expect(h.status.failedPages, 1);
      expect(reports, hasLength(1));
      expect(reports.single.exception, isA<StateError>());
      h.touchPage();
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(3));
      expect(reports, hasLength(1));
      h.dispose();
    });

    indexerTest('RecognizerUnsupported from a line → off for good', (async) {
      final h = IndexerHarness(async);
      h.addStrokes(h.lines());
      h.recognizer.failNext = RecognizerUnsupported();
      h.elapse(IndexerTuning.localQuiet);
      expect(h.phase, HandwritingIndexerPhase.off);
      expect(h.status, const HandwritingIndexerStatus());
      h.store.calls.clear();
      h.addStrokes(h.lines(seed: 2));
      h.elapse(const Duration(minutes: 1));
      expect(h.recognizer.calls, hasLength(1));
      expect(h.store.calls, isEmpty);
      expect(h.phase, HandwritingIndexerPhase.off);
      h.dispose();
    });
  });

  group('foreground (6.9.2 — CP-L10)', () {
    indexerTest('foreground false → no next line (the line in flight '
        'finishes); true → it goes on', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(50); // line 1 in flight
      h.foreground.value = false;
      expect(h.phase, HandwritingIndexerPhase.paused);
      h.elapse(const Duration(minutes: 1));
      expect(h.recognizer.calls, hasLength(1));
      expect(h.store.handwritingWrites, 0);
      expect(h.status.toString(), startsWith('paused · ko · page ${h.pageId}'));

      h.foreground.value = true;
      expect(h.phase, HandwritingIndexerPhase.recognizing);
      h.elapseMs(200);
      expect(h.recognizer.calls, hasLength(3));
      expect(h.store.count('update:'), 1);
      h.dispose();
    });

    indexerTest('in the background no job starts', (async) {
      final h = IndexerHarness(async, foreground: false);
      expect(h.phase, HandwritingIndexerPhase.paused);
      h.addStrokes(h.lines());
      h.elapse(const Duration(minutes: 1));
      expect(h.store.count('flush'), 0);
      expect(h.recognizer.calls, isEmpty);
      h.foreground.value = true;
      h.settle();
      expect(h.recognizer.calls, hasLength(3));
      h.dispose();
    });

    testWidgets('the default foreground follows AppLifecycleListener', (
      tester,
    ) async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final recognizer = FakeHandwritingRecognizer();
      final enabled = ValueNotifier<bool>(true);
      addTearDown(enabled.dispose);
      final indexer = HandwritingIndexer(
        store: store,
        recognizer: recognizer,
        enabled: enabled,
      );
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      indexer.start();
      await tester.pump();
      expect(indexer.status.value.phase, HandwritingIndexerPhase.idle);

      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      expect(indexer.status.value.phase, HandwritingIndexerPhase.paused);
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(s);
      }
      expect(indexer.status.value.phase, HandwritingIndexerPhase.idle);

      await indexer.dispose(); // closes its own listener
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(indexer.status.value.phase, HandwritingIndexerPhase.off);
    });
  });

  group('enabled, dispose, availability (4.4.7)', () {
    indexerTest('enabled false → disabled, no store or engine call', (async) {
      final h = IndexerHarness(async, enabled: false);
      expect(h.phase, HandwritingIndexerPhase.disabled);
      expect(h.status.toString(), 'disabled · ko');
      h.addStrokes(h.lines());
      h.elapse(const Duration(minutes: 1));
      expect(h.recognizer.calls, isEmpty);
      expect(h.store.calls, isEmpty);
      h.dispose();
    });

    indexerTest('disabled during a job → dropped, no write; enabled again → '
        'idle', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(50);
      h.enabled.value = false;
      expect(h.phase, HandwritingIndexerPhase.disabled);
      expect(h.status.queuedPages, 0);
      h.elapse(const Duration(seconds: 10));
      expect(h.recognizer.calls, hasLength(1));
      expect(h.store.handwritingWrites, 0);
      // Enabled again: the catch-up finds the stale page (L2-10b).
      h.enabled.value = true;
      h.settle();
      expect(h.phase, HandwritingIndexerPhase.recognizing);
      h.elapseMs(300);
      expect(h.store.count('update:'), 1);
      expect(h.phase, HandwritingIndexerPhase.idle);
      h.dispose();
    });

    indexerTest('dispose twice; an engine answer after dispose writes '
        'nothing; the engine stays open', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      h.elapseMs(50);
      final first = h.indexer.dispose();
      final second = h.indexer.dispose();
      h.wait(first);
      h.wait(second);
      expect(h.phase, HandwritingIndexerPhase.off);
      h.elapse(const Duration(minutes: 1));
      expect(h.recognizer.calls, hasLength(1));
      expect(h.store.handwritingWrites, 0);
      h.addStrokes(h.lines(seed: 3));
      h.elapse(const Duration(minutes: 1));
      expect(h.recognizer.calls, hasLength(1));
      expect(h.recognizer.disposed, isFalse);
      h.indexer.start(); // after dispose: nothing
      expect(h.phase, HandwritingIndexerPhase.off);
      h.dispose();
    });

    indexerTest('isAvailable false → off, nothing subscribed', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(isAvailable: false),
      );
      expect(h.phase, HandwritingIndexerPhase.off);
      h.addStrokes(h.lines());
      h.elapse(const Duration(minutes: 1));
      expect(h.store.calls, isEmpty);
      expect(h.recognizer.calls, isEmpty);
      expect(h.statuses, isEmpty); // never left the initial off
      h.dispose();
    });

    indexerTest('start() is idempotent', (async) {
      final h = IndexerHarness(async);
      h.indexer
        ..start()
        ..start();
      h.addStrokes(h.lines());
      h.elapse(IndexerTuning.localQuiet);
      expect(h.recognizer.calls, hasLength(3));
      expect(h.store.count('update:'), 1);
      h.dispose();
    });
  });

  group('status (4.4.1, 6.19)', () {
    indexerTest('phases and the one-line form through a job', (async) {
      final h = IndexerHarness(
        async,
        recognizer: FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 100),
        ),
      );
      expect(h.status.toString(), 'idle · ko · queue 0 · done 0 · failed 0');
      h.addStrokes(h.lines());
      expect(
        h.status.toString(),
        'waitingInput · ko · queue 1 · done 0 · failed 0',
      );
      h.elapse(IndexerTuning.localQuiet);
      expect(h.status.currentPageId, h.pageId);
      expect(
        h.status.toString(),
        'recognizing · ko · page ${h.pageId} · queue 0 · done 0 · failed 0',
      );
      h.elapseMs(300);
      expect(h.status.toString(), 'idle · ko · queue 0 · done 1 · failed 0');
      expect(h.statuses.map((s) => s.phase).toSet(), {
        HandwritingIndexerPhase.idle,
        HandwritingIndexerPhase.waitingInput,
        HandwritingIndexerPhase.recognizing,
      });
      h.dispose();
    });
  });

  group('performance (6.9.7)', () {
    indexerTest('a 1,000-stroke page: yields every 200 strokes and after '
        'every line; the longest piece of our part is recorded', (async) {
      final h = IndexerHarness(async, pages: 2);
      final [page, warmUpPage] = h.pageIds;
      List<core.Stroke> thousand(core.PageId pageId, int seed) => h
          .lines(pageId: pageId, lineCount: 40, seed: seed)
          .take(1000)
          .toList();
      h.addStrokes(thousand(warmUpPage, 6), pageId: warmUpPage);
      h.elapse(IndexerTuning.localQuiet); // warm-up job (JIT)
      final strokes = thousand(page, 5);
      expect(strokes, hasLength(1000));
      h.addStrokes(strokes, pageId: page);
      h.elapse(IndexerTuning.localQuiet);
      final job = metricsOf(h.indexer).lastJob.value!;
      final lines = linesOf(strokes);
      expect(job.lines, lines);
      expect(job.recognizedLines, lines);
      // 4 conversion yields + one per line + the awaits of the job.
      expect(job.slices, greaterThanOrEqualTo(lines + 4));
      // ignore: avoid_print — the 6.9.7 record (target ≤ 8 ms; VM JIT)
      print('indexer 1,000 strokes: $job');
      expect(job.longestSliceMs, lessThan(3 * 8));
      expect(h.stored()!.lines, hasLength(lines));
      h.dispose();
    });

    test(
      'above 1,500 strokes the grouping runs in compute — same lines',
      () async {
        final strokes = [
          for (final seed in [1, 2, 3, 4, 5, 6])
            ...SyntheticHandwriting.lines(
              pageId: 'p',
              lineCount: 12,
              seed: seed,
            ),
        ];
        final traces = [
          for (final s in strokes) HandwritingTrace.fromStroke(s),
        ];
        expect(traces.length, greaterThan(IndexerTuning.computeAboveStrokes));
        final background = await groupTraceIndicesInBackground(traces);
        expect(background, groupTraceIndices(traces));
      },
    );
  });
}
