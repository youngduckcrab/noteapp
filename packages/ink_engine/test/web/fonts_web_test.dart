@TestOn('browser')
library;

// T26a (m5-7/03-ink 8.1): fonts in Chrome — useInkTestFonts loads at once and
// measure answers within a second; without it ensureLoaded does not hang: it ends
// with TimeoutException after InkTuning.fontLoadTimeoutMs (rootBundle does not
// answer under `flutter test --platform chrome`). Sizes are not asserted (the test
// font has other metrics — 03-ink 4.12).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('useInkTestFonts → measure within 1 s; text rasters', () async {
    await useInkTestFonts().timeout(const Duration(seconds: 2));
    final size = await InkTextLayout.measure(
      '안녕 hello',
      const core.TextBoxStyle(),
      widthPt: 300,
    ).timeout(const Duration(seconds: 1));
    expect(size.height, greaterThan(0));
    expect(
      InkTextLayout.measureSync('줄 1', const core.TextBoxStyle(), widthPt: 100),
      isNotNull,
    );
    final image = await InkTextLayout.rasterize(
      core.TextBoxObject(
        id: 't',
        pageId: 'p1',
        frame: const core.ElementFrame(core.PageRect(0, 0, 200, 40)),
        text: '한글 텍스트 상자',
        style: const core.TextBoxStyle(),
        createdAt: 1,
      ),
      pixelsPerPt: 2,
    ).timeout(const Duration(seconds: 2));
    expect(image, isNotNull);
    expect([image!.width, image.height], [400, 80]);
    image.dispose();
  });

  test(
    'without the test font ensureLoaded ends in TimeoutException after 5 s',
    () async {
      debugSetInkFontSource(null);
      final watch = Stopwatch()..start();
      await expectLater(
        InkFonts.ensureLoaded(),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        watch.elapsedMilliseconds,
        lessThan(InkTuning.fontLoadTimeoutMs + 2000),
      );
      // measure falls back without waiting another 5 s (30 s retry pause)
      final quick = Stopwatch()..start();
      await InkTextLayout.measure('x', const core.TextBoxStyle(), widthPt: 50);
      expect(quick.elapsedMilliseconds, lessThan(1000));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
