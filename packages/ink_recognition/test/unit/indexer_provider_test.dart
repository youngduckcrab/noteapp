// handwritingIndexerProvider and recognitionDevOverlayLinesProvider
// (m5-7/05-library 8.2 L2-11, 4.4.7, 4.4.9, 6.10; contract 7.2.11): null
// without an engine (and on the web — web/recognition_browser_test.dart), an
// instance that is never started by the provider, `enabled` follows
// recog.autoIndex, disposed with the container (a second dispose by INFRA is
// safe), the four developer lines and the fixed line without an indexer.
// Widget tests where start() runs: the provider's indexer uses the default
// foreground (AppLifecycleListener).
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/l10n/recognition_strings.dart';
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

/// Available, model not downloaded, a download that waits for Wi-Fi forever.
final class _WaitingForWifi implements HandwritingRecognizer {
  final Completer<void> download = Completer<void>();

  @override
  String get engineId => 'waiting';
  @override
  bool get isAvailable => true;
  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      RecognitionModelState.notDownloaded;
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) =>
      download.future;
  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async => const [];
  @override
  Future<void> dispose() async {}
}

ProviderContainer containerFor(
  core.NoteStore store,
  HandwritingRecognizer recognizer, {
  RecognitionConfig config = const RecognitionConfig(),
}) => ProviderContainer(
  overrides: [
    core.noteStoreProvider.overrideWithValue(store),
    ...recognitionOverrides(config: config)
        .where((o) => o.origin != handwritingRecognizerProvider),
    handwritingRecognizerProvider.overrideWithValue(recognizer),
  ],
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

void main() {
  test('no available engine → null; the fixed developer line', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = containerFor(
      store,
      FakeHandwritingRecognizer(isAvailable: false),
    );
    addTearDown(container.dispose);
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(container.read(recognitionDevOverlayLinesProvider).value, [
      RecognitionStrings.noIndexerLine,
    ]);
  });

  test(
    'an available engine → an instance the provider does not start',
    () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final recognizer = FakeHandwritingRecognizer();
      final container = containerFor(store, recognizer);
      addTearDown(container.dispose);
      final indexer = container.read(handwritingIndexerProvider)!;
      await pumpEventQueue();
      expect(indexer.status.value.phase, HandwritingIndexerPhase.off);
      expect(container.read(handwritingIndexerProvider), same(indexer));
      expect(recognizer.calls, isEmpty);
    },
  );

  testWidgets('recog.autoIndex drives enabled', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = containerFor(store, FakeHandwritingRecognizer());
    addTearDown(container.dispose);
    final indexer = container.read(handwritingIndexerProvider)!;
    indexer.start(); // INFRA's idle task
    await settle(tester);
    expect(indexer.status.value.phase, HandwritingIndexerPhase.disabled);

    await store.settings.set(RecognitionSettingsKeys.autoIndex, true);
    await settle(tester);
    expect(indexer.status.value.phase, HandwritingIndexerPhase.idle);

    await store.settings.set(RecognitionSettingsKeys.autoIndex, false);
    await settle(tester);
    expect(indexer.status.value.phase, HandwritingIndexerPhase.disabled);
  });

  testWidgets('the container disposes the indexer; INFRA disposing it too is '
      'safe', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    await store.settings.set(RecognitionSettingsKeys.autoIndex, true);
    final recognizer = FakeHandwritingRecognizer();
    final container = containerFor(store, recognizer);
    final indexer = container.read(handwritingIndexerProvider)!;
    indexer.start();
    await settle(tester);
    expect(indexer.status.value.phase, HandwritingIndexerPhase.idle);

    container.dispose();
    await settle(tester);
    expect(indexer.status.value.phase, HandwritingIndexerPhase.off);
    await indexer.dispose(); // INFRA's idle-task shutdown
    indexer.start();
    expect(indexer.status.value.phase, HandwritingIndexerPhase.off);
    expect(recognizer.disposed, isFalse); // overrideWithValue: not owned
  });

  testWidgets('developer lines: status, job, model, math — and the job line '
      'after a page job', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    await store.settings.set(RecognitionSettingsKeys.autoIndex, true);
    final container = containerFor(store, FakeHandwritingRecognizer());
    addTearDown(container.dispose);
    final lines = container.read(recognitionDevOverlayLinesProvider);
    final indexer = container.read(handwritingIndexerProvider)!;
    await settle(tester);
    expect(lines.value, ['off', 'job —', 'model ko: ready', 'math: manual']);

    indexer.start();
    await settle(tester);
    expect(lines.value, [
      'idle · ko · queue 0 · done 0 · failed 0',
      'job —',
      'model ko: ready',
      'math: manual',
    ]);

    final note = await store.library.createNote(title: 'n');
    final pageId = (await store.content.pagesOf(note.id)).single.id;
    final session = await store.openSession(note.id);
    await session.openPage(pageId);
    await session
        .execute(
          core.AddStrokes(
            pageId: pageId,
            strokes: SyntheticHandwriting.lines(pageId: pageId, lineCount: 3),
          ),
        )
        .persisted;
    await session.close();
    await settle(tester);
    expect(
      lines.value.first,
      'waitingInput · ko · queue 1 · done 0 · failed 0',
    );
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(lines.value.first, 'idle · ko · queue 0 · done 1 · failed 0');
    expect(
      lines.value[1],
      matches(RegExp('^job \\d+\\.\\d ms · lines 3 · page $pageId\$')),
    );

    await store.settings.set(RecognitionSettingsKeys.language, 'en');
    await settle(tester);
    expect(lines.value[2], 'model en: ready');
  });

  testWidgets('model line while a Wi-Fi-only download waits', (tester) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    await store.settings.set(RecognitionSettingsKeys.autoIndex, true);
    final container = containerFor(store, _WaitingForWifi());
    addTearDown(container.dispose);
    final lines = container.read(recognitionDevOverlayLinesProvider);
    container.read(handwritingIndexerProvider)!.start();
    await settle(tester);
    expect(lines.value[0], 'waitingModel · ko · model ko: waiting for Wi-Fi');
    expect(lines.value[2], 'model ko: notDownloaded · waiting for Wi-Fi');
  });

  test('math line: callable with consent off / on; another engine', () async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = containerFor(
      store,
      FakeHandwritingRecognizer(),
      config: RecognitionConfig(
        mathEndpoint: Uri.parse('http://127.0.0.1:5001/demo/us-central1/m'),
      ),
    );
    addTearDown(container.dispose);
    final lines = container.read(recognitionDevOverlayLinesProvider);
    await pumpEventQueue();
    expect(lines.value[3], 'math: callable(consent off)');
    await store.settings.set(RecognitionSettingsKeys.mathConsent, true);
    await pumpEventQueue();
    expect(lines.value[3], 'math: callable(consent on)');

    final other = ProviderContainer(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        handwritingRecognizerProvider.overrideWithValue(
          FakeHandwritingRecognizer(),
        ),
        mathRecognizerProvider.overrideWithValue(FakeMathRecognizer()),
      ],
    );
    addTearDown(other.dispose);
    expect(
      other.read(recognitionDevOverlayLinesProvider).value[3],
      'math: fake',
    );
    final ValueListenable<List<String>> again = other.read(
      recognitionDevOverlayLinesProvider,
    );
    expect(again.value, hasLength(4));
  });
}
