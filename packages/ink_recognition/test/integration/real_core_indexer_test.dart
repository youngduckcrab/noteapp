// L2-I1 (m5-7/05-library 8.3, 9.3 G-4; contract 7.7 step 5; 02-core 6.9.4
// race case 3 — the LIBRARY side): the indexer on real CORE
// (openTestNoteStore — DB v2, FTS5). Written ahead in the concurrent stage
// and run in the integration stage (ws test --run-skipped -t integration).
// In the concurrent-stage tree CORE's DriftNoteStore still has the
// foundation-stage handwriting / search repositories (reads answer as for an
// empty store, writes throw UnimplementedError — CORE T32 / T33a), so here
// the tag skips it and it only has to compile. The same flows run on the
// fake store in unit/indexer_test.dart and unit/catch_up_test.dart (there
// HandwritingRepository.put stands in for sync.applyRemote).
//  ① a SyntheticHandwriting page → CORE's notesWithStalePages / stalePages
//    name it → the indexer (fake engine, answer = a word chosen from the
//    stroke ids) asks the same, recognizes and writes with update →
//    searchPages(word) finds the page with source ink and the line's rect;
//    nothing is stale afterwards.
//  ② another device's result (same sourceRev and language, another engine
//    id) arrives through sync.applyRemote while a line is in flight → the
//    job is dropped and runs again, the page is fresh: no engine call, no
//    write — the remote value and its search units stay (G-4).
// No wall-clock waits: the page comes from the start-up catch-up (no quiet
// time), the engine is held by a Completer, and every wait is a bounded
// number of event-loop turns.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:note_core/testing_vm.dart' as core_vm;

import '../support/recording_store.dart';

/// Event-loop turns a wait may take before the test fails (no wall clock —
/// 9.1).
const int _maxTurns = 20000;

/// Turns after a wait in which nothing else may happen.
const int _quietTurns = 200;

/// The HLC node of the other device.
const String _otherDevice = '00000000000000b2';

/// The fake engine's answer for synthetic line i: one word a line, no
/// bigram shared with another line or with [_remoteWords].
const List<String> _words = ['사과나무', '바다거북', '하늘구름'];

/// The other device's text for synthetic line i.
const List<String> _remoteWords = ['안드로이드', '태블릿펜', '동기화끝'];

/// The synthetic line of a stroke id `syn_<seed>_l<line>_<n>` (CP-L4).
int _lineOf(String id) => int.parse(id.split('_')[2].substring(1));

/// The word for the line the engine is asked about (its first stroke id).
String _answer(HandwritingLineInput line) =>
    _words[_lineOf(line.traces.first.strokeId!)];

Future<void> _until(bool Function() done, String what) async {
  for (var i = 0; i < _maxTurns; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('still waiting for $what');
}

Future<void> _quiet() async {
  for (var i = 0; i < _quietTurns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Every FlutterError report (reportRecognitionError) during the test.
List<FlutterErrorDetails> _captureReports() {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  addTearDown(() => FlutterError.onError = previous);
  return reports;
}

/// The one hit of [hits]: [w]'s page, source ink.
core.PageSearchHit _inkHit(
  List<core.PageSearchHit> hits,
  _World w,
  String query,
) {
  expect(hits, hasLength(1), reason: 'searchPages("$query")');
  final hit = hits.single;
  expect(hit.noteId, w.note.id);
  expect(hit.pageId, w.pageId);
  expect(hit.source, core.SearchSource.ink);
  return hit;
}

/// A FakeHandwritingRecognizer whose first recognizeLine answers only after
/// [release] (a line in flight for as long as the test wants).
final class _HeldRecognizer implements HandwritingRecognizer {
  _HeldRecognizer(this.inner);

  final FakeHandwritingRecognizer inner;

  /// Completed when the first line is asked.
  final Completer<void> asked = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  String get engineId => inner.engineId;

  @override
  bool get isAvailable => inner.isAvailable;

  @override
  Future<RecognitionModelState> modelState(String languageTag) =>
      inner.modelState(languageTag);

  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) =>
      inner.ensureModel(languageTag, wifiOnly: wifiOnly);

  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async {
    final answer = await inner.recognizeLine(line, languageTag: languageTag);
    if (!asked.isCompleted) {
      asked.complete();
      await release.future;
    }
    return answer;
  }

  @override
  Future<void> dispose() => inner.dispose();
}

/// Real CORE (in memory) behind the call recorder, one note with one page
/// holding three synthetic lines (seed 1) committed through a session.
final class _World {
  _World._(this.store, this.note, this.pageId, this.strokes);

  static Future<_World> open() async {
    final store = RecordingNoteStore(
      await core_vm.openTestNoteStore(seedDefaultPenPresets: false),
    );
    addTearDown(store.close);
    final note = await store.library.createNote(
      title: 'L2-I1',
      pages: [core.PageDraft.blankA4],
    );
    final pageId = (await store.content.pagesOf(note.id)).single.id;
    final strokes = SyntheticHandwriting.lines(
      pageId: pageId,
      lineCount: 3,
      seed: 1,
    );
    final session = await store.openSession(note.id);
    await session.openPage(pageId);
    await session
        .execute(core.AddStrokes(pageId: pageId, strokes: strokes))
        .persisted;
    await session.close();
    await store.flush();
    store.calls.clear();
    return _World._(store, note, pageId, strokes);
  }

  final RecordingNoteStore store;
  final core.Note note;
  final core.PageId pageId;
  final List<core.Stroke> strokes;

  core.HandwritingRepository get handwriting => store.inner.handwriting;

  /// The stroke ids of synthetic line [i].
  Set<core.ElementId> lineIds(int i) => {
    for (final s in strokes)
      if (_lineOf(s.id) == i) s.id,
  };

  /// The union of the pointBounds of synthetic line [i].
  core.PageRect lineRect(int i) => strokes
      .where((s) => _lineOf(s.id) == i)
      .map((s) => s.points.pointBounds)
      .reduce((a, b) => a.expandToInclude(b));

  /// sourceRevOf the committed input strokes of the page.
  Future<String> rev() async {
    final content = await store.inner.content.loadPage(pageId);
    return core.HandwritingText.sourceRevOf(
      content.strokes.where(core.HandwritingText.isRecognitionInput),
    );
  }

  /// An enabled indexer in the foreground (no WidgetsBinding), disposed
  /// before the store closes.
  HandwritingIndexer indexer(HandwritingRecognizer recognizer) {
    final enabled = ValueNotifier<bool>(true);
    final foreground = ValueNotifier<bool>(true);
    final indexer = HandwritingIndexer(
      store: store,
      recognizer: recognizer,
      enabled: enabled,
      foreground: foreground,
    );
    addTearDown(() async {
      await indexer.dispose();
      enabled.dispose();
      foreground.dispose();
    });
    return indexer;
  }
}

void main() {
  test('a synthetic page: notesWithStalePages → stalePages → the indexer '
      '(fake engine) → update → searchPages finds the page as ink with the '
      'line rect; nothing stale afterwards', () async {
    final w = await _World.open();
    final reports = _captureReports();
    final rev = await w.rev();
    expect(await w.handwriting.notesWithStalePages(), [w.note.id]);
    expect(await w.handwriting.stalePages(w.note.id), [w.pageId]);
    w.store.calls.clear();

    final recognizer = FakeHandwritingRecognizer(answer: _answer);
    final indexer = w.indexer(recognizer)..start();
    await _until(
      () =>
          indexer.status.value.indexedPages == 1 &&
          indexer.status.value.phase == HandwritingIndexerPhase.idle,
      'the page indexed (status ${indexer.status.value})',
    );
    await _quiet();

    // The indexer asked CORE what is stale (catch-up, then the job) and
    // wrote once with update; one engine call per line, nothing else.
    expect(
      w.store.calls,
      containsAllInOrder([
        'notesWithStalePages',
        'stalePages:${w.note.id}',
        'loadPage:${w.pageId}',
        'update:${w.pageId}',
      ]),
    );
    expect(w.store.handwritingWrites, 1);
    expect(recognizer.calls, hasLength(3));
    expect(indexer.status.value.failedPages, 0);
    expect(indexer.status.value.queuedPages, 0);

    final stored = (await w.handwriting.forPage(w.pageId))!;
    expect(stored.noteId, w.note.id);
    expect(stored.engineId, 'fake:ko');
    expect(stored.sourceRev, rev);
    expect(stored.lines.map((l) => l.text), _words);
    for (final (i, line) in stored.lines.indexed) {
      expect(line.strokeIds.toSet(), w.lineIds(i));
      expect(line.rect, w.lineRect(i));
      expect(line.languageTag, 'ko');
      expect(line.userConfirmed, isFalse);
    }
    expect(await w.handwriting.stalePages(w.note.id), isEmpty);
    expect(await w.handwriting.notesWithStalePages(), isEmpty);

    // Search: the word of each line → this page, source ink, that line's
    // rect (one unit a line — 02-core 6.10.3).
    for (final (i, word) in _words.indexed) {
      final hit = _inkHit(await w.store.search.searchPages(word), w, word);
      expect(hit.rects, [stored.lines[i].rect]);
      expect(hit.snippet.substring(hit.matchRange.$1, hit.matchRange.$2), word);
    }
    expect(reports, isEmpty);
  });

  test('another device\'s result through sync.applyRemote while a line is '
      'in flight (same sourceRev and language) → the job is dropped and runs '
      'again, the page is fresh: no engine call, no write — the remote value '
      'and its search units stay', () async {
    final w = await _World.open();
    final reports = _captureReports();
    final rev = await w.rev();
    final recognizer = _HeldRecognizer(
      FakeHandwritingRecognizer(answer: _answer),
    );
    final indexer = w.indexer(recognizer)..start();
    await _until(() => recognizer.asked.isCompleted, 'the first line asked');
    expect(indexer.status.value.phase, HandwritingIndexerPhase.recognizing);
    expect(w.store.count('update:'), 0);

    // The other device's result, as SYNC hands it over (taken: no local
    // handwriting row yet).
    final nowMs = w.store.inner.clock.now().millisecondsSinceEpoch;
    final version = core.Hlc(nowMs + 1, 0, _otherDevice);
    final remote = core.HandwritingText(
      noteId: w.note.id,
      pageId: w.pageId,
      engineId: 'mlkit-digital-ink/19.0.0:ko',
      sourceRev: rev,
      lines: [
        for (final (i, text) in _remoteWords.indexed)
          core.HandwritingLine(
            text: text,
            rect: w.lineRect(i),
            strokeIds: w.lineIds(i).toList()..sort(),
          ),
      ],
      createdAt: nowMs,
      version: version,
    );
    var remoteSeen = false;
    final sub = w.store.changes.listen((batch) {
      if (batch.origin == core.ChangeOrigin.remote &&
          batch.changes.any(
            (c) =>
                c.kind == core.EntityKind.handwriting && c.pageId == w.pageId,
          )) {
        remoteSeen = true;
      }
    });
    addTearDown(sub.cancel);
    final report = await w.store.sync.applyRemote([
      core.RemoteUpsert(remote, core.EntityFieldVersions(version)),
    ], policy: core_testing.newerVersionWinsPolicy);
    expect(report.taken, 1);
    // The indexer listened first, so it has seen the change as well.
    await _until(() => remoteSeen, 'the remote handwriting change');

    w.store.calls.clear();
    recognizer.release.complete();
    await _until(
      () =>
          w.store.calls.contains('stalePages:${w.note.id}') &&
          indexer.status.value.queuedPages == 0 &&
          indexer.status.value.phase == HandwritingIndexerPhase.idle,
      'the page run again (status ${indexer.status.value})',
    );
    await _quiet();

    // Run again: fresh by the DB columns (stalePages) and the language of
    // the stored engine id — no loadPage, no engine call, no write.
    expect(w.store.calls, [
      'flush',
      'stalePages:${w.note.id}',
      'forPage:${w.pageId}',
    ]);
    expect(recognizer.inner.calls, hasLength(1)); // the held line only
    expect(indexer.status.value.failedPages, 0);

    final stored = (await w.handwriting.forPage(w.pageId))!;
    expect(stored.engineId, 'mlkit-digital-ink/19.0.0:ko');
    expect(stored.sourceRev, rev);
    expect(stored.version, version);
    expect(stored.lines.map((l) => l.text), _remoteWords);
    expect(await w.handwriting.stalePages(w.note.id), isEmpty);

    // The remote result is what search finds (the putRemote index hook);
    // the engine's words never got written.
    final hit = _inkHit(
      await w.store.search.searchPages(_remoteWords[1]),
      w,
      _remoteWords[1],
    );
    expect(hit.rects, [w.lineRect(1)]);
    for (final word in _words) {
      expect(await w.store.search.searchPages(word), isEmpty);
    }
    expect(reports, isEmpty);
  });
}
