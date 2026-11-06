// ink_recognition on dart2js (m5-7/05-library 8.1 B6-b, 9.3 G-1). R2-B6
// part: the web-safe entry point imports and runs in Chrome, the web gets the
// unsupported handwriting engine (the stub) and never an indexer — even when
// a test overrides an available engine — and the HandwritingTrace body shared
// with the VM keeps 13-digit epoch ms exact. (L2-05) The line grouping body
// shared with the VM (shared/line_cases.dart — V9 on the same synthetic
// pages, lineAccuracy) gives the same numbers on dart2js. L2-20 adds the
// conversion sheet and web wording cases (with useInkTestFonts in setUpAll).
@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart' show Rect;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../shared/line_cases.dart';
import '../shared/trace_cases.dart';

void main() {
  test('runs on the web', () {
    expect(kIsWeb, isTrue);
  });

  test('recognitionOverrides(): unsupported handwriting, manual math, '
      'NoShapeFitter, no indexer (G-1)', () async {
    final container = ProviderContainer.test(overrides: recognitionOverrides());
    final hw = container.read(handwritingRecognizerProvider);
    expect(hw, isA<UnsupportedHandwritingRecognizer>());
    expect(hw.isAvailable, isFalse);
    expect(await hw.modelState('ko'), RecognitionModelState.unsupported);
    expect(
      container.read(mathRecognizerProvider),
      isA<ManualOnlyMathRecognizer>(),
    );
    expect(
      container.read(ink.inkShapeFitterProvider),
      isA<ink.NoShapeFitter>(),
    );
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(container.read(recognitionDevOverlayLinesProvider).value, [
      '손글씨 색인 없음 (이 기기에서 인식 불가)',
    ]);
  });

  test('no indexer on the web even with an available engine', () {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final recognizer = FakeHandwritingRecognizer();
    final container = ProviderContainer.test(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        handwritingRecognizerProvider.overrideWithValue(recognizer),
      ],
    );
    expect(container.read(handwritingIndexerProvider), isNull);
    expect(recognizer.calls, isEmpty);
  });

  test('testing.dart works on dart2js', () async {
    final fake = FakeHandwritingRecognizer();
    final out = await fake.recognizeLine(
      const HandwritingLineInput([]),
      languageTag: 'ko',
    );
    expect(out.first.text, '줄 1');
    final strokes = SyntheticHandwriting.lines(pageId: 'p1', lineCount: 3);
    expect(strokes.first.id, 'syn_1_l00_0000');
    final path = SyntheticShapes.rectanglePath(
      const Rect.fromLTWH(0, 0, 96, 48),
    );
    expect(path, hasLength(97));
    expect(path.last, path.first);
    final lines = groupIntoLines([
      for (final s in strokes) HandwritingTrace.fromStroke(s),
    ]);
    expect(lines, hasLength(3)); // 6.5: the three written lines
  });

  defineHandwritingTraceTests();
  defineLineCaseTests();
}
