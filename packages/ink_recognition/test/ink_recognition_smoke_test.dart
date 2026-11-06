// 2차 foundation step R2-B6 smoke test (contract m5-7/00-overview 7.6.2 R2-B6,
// m5-7/05-library 8.1 B6-b): what the app shell's RecognitionModule does with
// this package at the foundation stage works — recognitionOverrides() in a
// root scope with CORE's fake store, every provider reads without an
// exception, the settings section builds, and an available engine gives an
// indexer that the container disposes. (L2-07) recognitionOverrides() gives
// GeometricShapeFitter to INK. (L2-10a) start() runs the indexer; the
// provider's `enabled` stays false until L2-11 (recog.autoIndex) → disabled.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

void main() {
  test('recognitionOverrides() + fake store: every provider reads', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = ProviderContainer.test(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        ...recognitionOverrides(),
      ],
    );
    expect(
      container.read(handwritingRecognizerProvider),
      isA<UnsupportedHandwritingRecognizer>(),
    );
    expect(
      container.read(mathRecognizerProvider),
      isA<ManualOnlyMathRecognizer>(),
    );
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(container.read(recognitionDevOverlayLinesProvider).value, [
      '손글씨 색인 없음 (이 기기에서 인식 불가)',
    ]);
    expect(
      container.read(ink.inkShapeFitterProvider),
      isA<GeometricShapeFitter>(), // L2-07 (4.4.8)
    );
  });

  test('the providers read without a NoteStore override (no engine)', () {
    final container = ProviderContainer.test(overrides: recognitionOverrides());
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(
      container.read(recognitionDevOverlayLinesProvider).value,
      hasLength(1),
    );
  });

  testWidgets(
    'an available engine → an indexer (VM), disposed with the container',
    (tester) async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final recognizer = FakeHandwritingRecognizer();
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          // (L2-07) recognitionOverrides() overrides the engine itself: a
          // test engine replaces that one override (a provider may be
          // overridden once per container).
          ...recognitionOverrides().where(
            (o) => o.origin != handwritingRecognizerProvider,
          ),
          handwritingRecognizerProvider.overrideWithValue(recognizer),
        ],
      );
      final indexer = container.read(handwritingIndexerProvider);
      expect(indexer, isA<HandwritingIndexer>());
      // The default foreground (AppLifecycleListener) needs the widgets
      // binding — testWidgets has it.
      indexer!.start();
      await tester.pump();
      expect(indexer.status.value.phase, HandwritingIndexerPhase.disabled);
      expect(recognizer.calls, isEmpty);

      container.dispose(); // onDispose → indexer.dispose(); idempotent
      await tester.pump();
      await indexer.dispose();
      expect(indexer.status.value.phase, HandwritingIndexerPhase.off);
      expect(
        recognizer.disposed,
        isFalse,
      ); // the indexer never closes the engine
    },
  );

  test('an unavailable engine → no indexer', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final container = ProviderContainer.test(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        handwritingRecognizerProvider.overrideWithValue(
          FakeHandwritingRecognizer(isAvailable: false),
        ),
      ],
    );
    expect(container.read(handwritingIndexerProvider), isNull);
  });

  testWidgets('RecognitionSettingsSection builds in the app scope', (
    tester,
  ) async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...recognitionOverrides(),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RecognitionSettingsSection()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(RecognitionSettingsSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
