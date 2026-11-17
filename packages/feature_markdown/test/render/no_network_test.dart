// B-5 / MD-T13 (08-markdown 8.3, 8.6): remote images are never fetched and links never
// open by themselves — rendering, scrolling and tapping make zero network calls.
@TestOn('vm')
library;

import 'dart:io';

import 'package:feature_markdown/feature_markdown.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump.dart';
import '../support/sample_doc.dart';

final class _CountingOverrides extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('network access from the MD screen');
  }
}

void main() {
  late HttpOverrides? previous;
  late _CountingOverrides counting;

  setUp(() {
    previous = HttpOverrides.current;
    counting = _CountingOverrides();
    HttpOverrides.global = counting;
  });
  tearDown(() => HttpOverrides.global = previous);

  testWidgets('remote images and links: zero HTTP clients', (tester) async {
    final h = await MdHarness.create(tester);
    final text = [
      kSampleMarkdown,
      for (var i = 0; i < 20; i++)
        '![사진 $i](https://cdn$i.example.com/p.png "t") <img src="http://tracker.example.net/pixel.gif?id=$i" alt="픽셀">',
      '[링크](https://example.com) <https://auto.example.com>',
    ].join('\n\n');
    final id = await h.doc(tester, text);
    await h.pump(tester, id);
    await tester.drag(find.byKey(MarkdownKeys.view), const Offset(0, -20000));
    await settleMd(tester, 12);
    await tester.tapOnText(find.textRange.ofSubstring('링크'));
    await settleMd(tester);
    expect(find.byKey(MarkdownKeys.linkSheet), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('md.image.'),
      ),
      findsWidgets,
    );
    expect(counting.clients, 0);
  });
}
