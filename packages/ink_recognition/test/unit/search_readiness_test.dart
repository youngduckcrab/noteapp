// handwritingSearchReadinessProvider (handwriting search — m5-7/05-library
// 6.19a): the phase the library's search hint shows (autoIndexOff, the model
// states, indexing with the pages left, ready), [켜기] = recog.autoIndex on
// and the model asked for, [지금 받기] (Wi-Fi only / cellular), and the search
// opening → dirty pages recognized now.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/indexer/handwriting_indexer.dart'
    show kModelRetryGap;
import 'package:ink_recognition/src/ports/model_admin.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/src/ui/model_downloads.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

/// Android-like: model missing; a Wi-Fi-only download waits until [wifi]
/// completes, a cellular one ends at once.
final class _Engine implements HandwritingRecognizer, RecognizerModelAdmin {
  final Completer<void> wifi = Completer<void>();
  final List<bool> ensured = [];

  /// ensureModel fails while set (a download that did not work).
  bool failing = false;
  final StreamController<String> _changes = StreamController.broadcast();
  bool ready = false;

  @override
  bool get enforcesWifiOnly => true;
  @override
  Stream<String> get modelChanges => _changes.stream;
  @override
  Future<void> deleteModel(String languageTag) async {}

  @override
  String get engineId => 'android-like';
  @override
  bool get isAvailable => true;
  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      ready ? RecognitionModelState.ready : RecognitionModelState.notDownloaded;
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async {
    ensured.add(wifiOnly);
    if (failing) throw StateError('download failed');
    if (wifiOnly) await wifi.future;
    ready = true;
    _changes.add(languageTag);
  }

  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async => [TextCandidate('글', languageTag: languageTag)];
  @override
  Future<void> dispose() async => _changes.close();
}

ProviderContainer _container(
  core.NoteStore store,
  HandwritingRecognizer recognizer,
) => ProviderContainer(
  overrides: [
    core.noteStoreProvider.overrideWithValue(store),
    ...recognitionOverrides().where(
      (o) => o.origin != handwritingRecognizerProvider,
    ),
    handwritingRecognizerProvider.overrideWithValue(recognizer),
  ],
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

/// The indexer started (INFRA's idle task) and the readiness read.
Future<HandwritingSearchReadiness> _open(
  WidgetTester tester,
  ProviderContainer container,
) async {
  container.read(handwritingIndexerProvider)!.start();
  final r = container.read(handwritingSearchReadinessProvider)!;
  await _settle(tester);
  return r;
}

HandwritingSearchPhase _phase(HandwritingSearchReadiness r) =>
    r.status.value.phase;

void main() {
  test('no available engine → null', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = _container(
      store,
      FakeHandwritingRecognizer(isAvailable: false),
    );
    addTearDown(container.dispose);
    expect(container.read(handwritingSearchReadinessProvider), isNull);
  });

  testWidgets('autoIndex off → autoIndexOff; [켜기] → on and ready', (
    tester,
  ) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    await store.settings.set(RecognitionSettingsKeys.autoIndex, false);
    final container = _container(store, FakeHandwritingRecognizer());
    final r = await _open(tester, container);
    expect(_phase(r), HandwritingSearchPhase.autoIndexOff);

    await r.turnOnAutoIndex();
    await _settle(tester);
    expect(await store.settings.get(RecognitionSettingsKeys.autoIndex), isTrue);
    expect(_phase(r), HandwritingSearchPhase.ready);
    container.dispose();
    await _settle(tester);
  });

  testWidgets('model missing on Android: downloading → waiting for Wi-Fi '
      'after 5 s → [지금 받기] over cellular → ready', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final engine = _Engine();
    final container = _container(store, engine);
    final r = await _open(tester, container);
    // On by default: the start asked for the model (Wi-Fi only).
    expect(engine.ensured, contains(true));
    expect(_phase(r), HandwritingSearchPhase.modelDownloading);
    expect(r.status.value.confirmCellularFirst, isFalse);

    await tester.pump(kWifiWaitBeforeCellular);
    await _settle(tester);
    expect(_phase(r), HandwritingSearchPhase.waitingForWifi);

    await r.downloadModel(cellular: true);
    await _settle(tester);
    expect(engine.ensured, contains(false));
    expect(
      container.read(modelDownloadsProvider).stateOf('ko'),
      ModelDownloadState.none,
    );
    // modelChanges → the indexer sees the model and resumes.
    expect(_phase(r), HandwritingSearchPhase.ready);
    container.dispose();
    await _settle(tester);
  });

  testWidgets('iPad: model missing → modelMissing, confirm cellular first '
      'with Wi-Fi only; [지금 받기] → ready', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final engine = FakeHandwritingRecognizer()
      ..enforcesWifiOnly = false
      ..modelStates['ko'] = RecognitionModelState.notDownloaded;
    final container = _container(store, engine);
    final r = await _open(tester, container);
    expect(_phase(r), HandwritingSearchPhase.modelMissing);
    expect(r.status.value.confirmCellularFirst, isTrue);
    expect(engine.ensureModelCalls, 0);

    await r.downloadModel();
    await _settle(tester);
    expect(engine.ensureModelCalls, 1);
    expect(_phase(r), HandwritingSearchPhase.ready);
    container.dispose();
    await _settle(tester);
  });

  testWidgets('pages waiting → indexing (n pages left); the search opening '
      'recognizes them now → ready', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final engine = FakeHandwritingRecognizer();
    final container = _container(store, engine);
    final r = await _open(tester, container);
    expect(_phase(r), HandwritingSearchPhase.ready);

    final note = await store.library.createNote(
      title: 'n',
      pages: [core.PageDraft.blankA4, core.PageDraft.blankA4],
    );
    final pages = [for (final p in await store.content.pagesOf(note.id)) p.id];
    final session = await store.openSession(note.id);
    for (final page in pages) {
      await session.openPage(page);
      await session
          .execute(
            core.AddStrokes(
              pageId: page,
              strokes: SyntheticHandwriting.lines(pageId: page, lineCount: 2),
            ),
          )
          .persisted;
    }
    await session.close();
    await _settle(tester);
    expect(_phase(r), HandwritingSearchPhase.indexing);
    expect(r.status.value.remainingPages, 2);
    expect(engine.calls, isEmpty);

    r.searchOpened();
    await _settle(tester);
    expect(engine.calls, isNotEmpty);
    for (var i = 0; i < 50 && _phase(r) != HandwritingSearchPhase.ready; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(_phase(r), HandwritingSearchPhase.ready);
    expect(await store.handwriting.forPage(pages.last), isNotNull);
    container.dispose();
    await _settle(tester);
  });

  testWidgets('the engine or the model unsupported → unsupported', (
    tester,
  ) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final engine = FakeHandwritingRecognizer()
      ..modelStates['ko'] = RecognitionModelState.unsupported;
    final container = _container(store, engine);
    final r = await _open(tester, container);
    expect(_phase(r), HandwritingSearchPhase.unsupported);
    container.dispose();
    await _settle(tester);
  });

  testWidgets('a failed download asked again by the search shows the retry, '
      'not the old failure; asked at most once per kModelRetryGap', (
    tester,
  ) async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final engine = _Engine()..failing = true;
    final container = _container(store, engine);
    final r = await _open(tester, container);
    expect(
      container.read(modelDownloadsProvider).stateOf('ko'),
      ModelDownloadState.failed,
    );
    expect(_phase(r), HandwritingSearchPhase.modelFailed);
    final asked = engine.ensured.length;

    engine.failing = false;
    r.searchOpened();
    await _settle(tester);
    expect(engine.ensured.length, asked + 1);
    // ModelDownloads still says failed; the indexer's retry wins.
    expect(_phase(r), HandwritingSearchPhase.waitingForWifi);

    // Typing more does not ask again while the retry gap runs.
    engine.failing = true;
    engine.wifi.completeError(StateError('no Wi-Fi'));
    await _settle(tester);
    expect(_phase(r), HandwritingSearchPhase.modelFailed);
    r
      ..searchOpened()
      ..searchOpened();
    await _settle(tester);
    expect(engine.ensured.length, asked + 1);
    await tester.pump(kModelRetryGap);
    r.searchOpened();
    await _settle(tester);
    expect(engine.ensured.length, asked + 2);
    container.dispose();
    await _settle(tester);
    FlutterError.onError = previous;
    expect(reports, isNotEmpty);
  });

  testWidgets('(in-note search) statusOfNote counts that note\'s pages; '
      'searchOpenedInNote recognizes them first and fires changes', (
    tester,
  ) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final engine = FakeHandwritingRecognizer(
      latency: const Duration(milliseconds: 100),
    );
    final container = _container(store, engine);
    final r = await _open(tester, container);
    Future<(core.NoteId, core.PageId)> noteWithInk(String title) async {
      final note = await store.library.createNote(
        title: title,
        pages: const [core.PageDraft.blankA4],
      );
      final pageId = (await store.content.pagesOf(note.id)).single.id;
      final session = await store.openSession(note.id);
      await session.openPage(pageId);
      await session
          .execute(
            core.AddStrokes(
              pageId: pageId,
              strokes: SyntheticHandwriting.lines(pageId: pageId),
            ),
          )
          .persisted;
      await session.close();
      return (note.id, pageId);
    }

    final (other, _) = await noteWithInk('other');
    final (mine, minePage) = await noteWithInk('mine');
    await _settle(tester);
    expect(_phase(r), HandwritingSearchPhase.indexing);
    expect(r.statusOfNote(mine).phase, HandwritingSearchPhase.indexing);
    expect(r.statusOfNote(mine).remainingPages, 1);
    expect(r.statusOfNote(other).remainingPages, 1);
    expect(r.statusOfNote('no-such-note').phase, HandwritingSearchPhase.ready);

    var changes = 0;
    r.changes.addListener(() => changes++);
    r.searchOpenedInNote(mine);
    await _settle(tester);
    expect(changes, greaterThan(0));
    // This note's page first (although written last): 5 lines × 100 ms.
    final indexer = container.read(handwritingIndexerProvider)!;
    expect(indexer.status.value.currentPageId, minePage);
    await tester.pump(const Duration(milliseconds: 550));
    await _settle(tester);
    expect(r.statusOfNote(mine).phase, HandwritingSearchPhase.ready);
    expect(r.statusOfNote(other).phase, HandwritingSearchPhase.indexing);
    expect(_phase(r), HandwritingSearchPhase.indexing);
    // A new query asks again: while that lookup runs the answer stays ready
    // (the hint does not flash 'indexing' on every query).
    r.searchOpenedInNote(mine);
    expect(r.statusOfNote(mine).phase, HandwritingSearchPhase.ready);
    await _settle(tester);
    expect(r.statusOfNote(mine).phase, HandwritingSearchPhase.ready);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(r.statusOfNote(other).phase, HandwritingSearchPhase.ready);
    container.dispose();
    await _settle(tester);
  });
}
