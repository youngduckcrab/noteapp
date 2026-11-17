// B-13 / MD-T20 (08-markdown 8.11, 16): a 100 KB document paints its first screen in under
// 300 ms on the VM, a 2,000-item list too, and typing in 편집 never parses; the time of
// one keystroke at 100 KB and at the edit limit (kMaxEditUnits), and a 400 KB document
// (the store's limit) opening view-only. Run with `flutter test --run-skipped -t perf`.
// VM debug numbers: the owner's tablet (release) is checked by hand (08-markdown 8.7).
@Tags(['perf'])
@TestOn('vm')
library;

import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/src/parse/md_document.dart';
import 'package:feature_markdown/src/screen/markdown_controller.dart'
    show kMaxEditUnits;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show MarkdownLimits;

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

  testWidgets('one keystroke at 100 KB and at the edit limit (MD-T20)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    for (final units in [100 * 1024, kMaxEditUnits - 100]) {
      final text = _sized(units).substring(0, units);
      final id = await h.doc(tester, text);
      await h.pump(tester, id, initialEdit: true);
      await tester.showKeyboard(find.byKey(MarkdownKeys.editor));
      final field = find.byKey(MarkdownKeys.editor);
      var current = (tester.widget(field) as TextField).controller!.value;
      // warm up
      for (var i = 0; i < 3; i++) {
        current = current.copyWith(
          text: '${current.text}a',
          selection: TextSelection.collapsed(offset: current.text.length + 1),
        );
        tester.testTextInput.updateEditingValue(current);
        await tester.pump();
      }
      final times = <int>[];
      for (var i = 0; i < 10; i++) {
        current = current.copyWith(
          text: '${current.text}가',
          selection: TextSelection.collapsed(offset: current.text.length + 1),
        );
        final sw = Stopwatch()..start();
        tester.testTextInput.updateEditingValue(current);
        await tester.pump();
        sw.stop();
        times.add(sw.elapsedMilliseconds);
      }
      times.sort();
      // ignore: avoid_print
      print(
        'keystroke at $units units: median ${times[5]} ms, '
        'max ${times.last} ms (VM debug)',
      );
      expect(times[5], lessThan(3000));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
  });

  testWidgets('400 KB (the store limit): view-only, first paint measured', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    // Korean is 3 bytes in UTF-8: cut to just under the store's 400,000 bytes.
    var text = _sized(200 * 1024);
    while (MarkdownLimits.utf8BytesOf(text) > 395000) {
      text = text.substring(0, text.lastIndexOf('\n\n', text.length - 1000));
    }
    await _firstPaintMs(tester, h, _sized(60 * 1024));
    final ms = await _firstPaintMs(tester, h, text);
    // ignore: avoid_print
    print('first paint ${text.length} units: $ms ms');
    expect(find.byKey(MarkdownKeys.bannerTooLargeToEdit), findsOneWidget);
    expect(ms, lessThan(1500));
  });
}
