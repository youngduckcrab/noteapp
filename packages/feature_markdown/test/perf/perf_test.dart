// B-13 / MD-T20 (08-markdown 8.11, 16): a 100 KB document paints its first screen in under
// 300 ms on the VM, a 2,000-item list too, and typing in 편집 never parses. Run with
// `flutter test --run-skipped -t perf`.
@Tags(['perf'])
@TestOn('vm')
library;

import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/src/parse/md_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump.dart';
import '../support/sample_doc.dart';

String _sized(int bytes) {
  final b = StringBuffer();
  var i = 0;
  while (b.length < bytes) {
    b
      ..write(kSampleMarkdown.replaceAll('[^1]', '[^n$i]'))
      ..write('\n[^n$i]: 각주 $i\n\n');
    i++;
  }
  return b.toString();
}

Future<int> _firstPaintMs(WidgetTester tester, MdHarness h, String text) async {
  final id = await h.doc(tester, text);
  final sw = Stopwatch()..start();
  await h.pump(tester, id, settle: false);
  // The store event, the parse (another isolate above 50 KB) and the first frame.
  for (
    var i = 0;
    i < 200 && find.byKey(MarkdownKeys.block(0)).evaluate().isEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump();
  }
  sw.stop();
  expect(find.byKey(MarkdownKeys.block(0)), findsOneWidget);
  return sw.elapsedMilliseconds;
}

void main() {
  testWidgets('100 KB: first paint under 300 ms', (tester) async {
    final h = await MdHarness.create(tester);
    final text = _sized(100 * 1024);
    // warm up (code paths, fonts)
    await _firstPaintMs(tester, h, _sized(60 * 1024));
    // Best of three: the VM shares the machine with other jobs.
    var ms = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final t = await _firstPaintMs(tester, h, '$text\n\n끝 $i');
      if (t < ms) ms = t;
    }
    // ignore: avoid_print
    print('first paint 100 KB: $ms ms');
    expect(ms, lessThan(300));
  });

  testWidgets('2,000-item list: first paint under 300 ms', (tester) async {
    final h = await MdHarness.create(tester);
    final text = List.generate(2000, (i) => '- 항목 $i 와 **굵게**').join('\n');
    await _firstPaintMs(tester, h, '- 예열');
    var ms = 1 << 30;
    for (var i = 0; i < 3; i++) {
      final t = await _firstPaintMs(tester, h, '$text\n- 끝 $i');
      if (t < ms) ms = t;
    }
    // ignore: avoid_print
    print('first paint 2,000 items: $ms ms');
    expect(ms, lessThan(300));
  });

  testWidgets('typing in 편집 never parses', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, _sized(100 * 1024));
    await h.pump(tester, id, initialEdit: true);
    final before = debugParseCount;
    final field = find.byKey(MarkdownKeys.editor);
    final text = (tester.widget(field) as TextField).controller!.text;
    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await tester.enterText(field, '$text${'가' * i}');
      await tester.pump(const Duration(milliseconds: 16));
    }
    sw.stop();
    // ignore: avoid_print
    print('20 keystrokes on 100 KB: ${sw.elapsedMilliseconds} ms');
    expect(debugParseCount, before);
  });
}
