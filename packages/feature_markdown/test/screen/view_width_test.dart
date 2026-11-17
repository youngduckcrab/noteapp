// The rendered 보기 keeps the full reading column after editing (owner report: the text
// showed one character per line after 편집 → 보기). The cause was the source editor kept
// mounted Offstage in a loosely sized Stack (0af6469); since v2.18-md the source editor
// is not mounted in 보기 at all, and a new document is typed in the live block field.
import 'package:feature_markdown/feature_markdown.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump.dart';

const _text =
    '# 회의 메모\n\n오늘은 마크다운 문서를 처음 만들어 보았습니다. Hello markdown world, '
    'this paragraph is long enough to wrap only a few times.\n\n- 첫째 항목\n- second item\n';

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(MarkdownKeys.editor), text);
  await tester.pump();
}

Future<void> _typeLive(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(MarkdownKeys.liveField), text);
  await tester.pump();
}

/// Every paragraph of the rendered view is (nearly) as wide as the view's column.
void _expectSaneWidth(WidgetTester tester, {Key key = MarkdownKeys.view}) {
  final view = tester.renderObject<RenderBox>(find.byKey(key));
  expect(
    view.size.width,
    greaterThan(300),
    reason: 'the 보기 list collapsed to ${view.size}',
  );
  final paragraphs = find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate((w) => w is RichText),
  );
  expect(paragraphs, findsWidgets);
  final column = (view.size.width - 32).clamp(0.0, 720.0);
  var checked = 0;
  for (final e in paragraphs.evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final text = p.text.toPlainText();
    if (text.characters.length < 12) continue;
    checked++;
    expect(
      p.size.width,
      greaterThanOrEqualTo(column * 0.5),
      reason: '"$text" laid out ${p.size.width} wide (column $column)',
    );
  }
  expect(checked, greaterThan(0));
}

void main() {
  const sizes = <String, Size>{
    'landscape tablet 1280x800': Size(1280, 800),
    'portrait tablet 800x1280': Size(800, 1280),
    'phone 390x844': Size(390, 844),
  };
  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('새 MD 문서 → type in place → [완료]: full-width text ($name)', (
      tester,
    ) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '');
      await h.pump(tester, id, size: size, initialEdit: true);
      await _typeLive(tester, _text);
      await tester.tap(find.byKey(MarkdownKeys.liveToolbarButton('done')));
      await settleMd(tester);
      expect(
        find.byKey(MarkdownKeys.editor, skipOffstage: false),
        findsNothing,
      );
      _expectSaneWidth(tester);
    });

    testWidgets('원문 → type → [보기]: full-width text ($name)', (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '');
      await h.pump(tester, id, size: size, source: true);
      await _type(tester, _text);
      await tester.tap(find.byKey(MarkdownKeys.mode));
      await settleMd(tester);
      expect(
        find.byKey(MarkdownKeys.editor, skipOffstage: false),
        findsNothing,
      );
      _expectSaneWidth(tester);
    });
  }

  testWidgets('system back 원문 → 보기 at 2560x1600 physical (dpr 2)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '');
    await h.pump(tester, id, size: const Size(1280, 800), source: true);
    tester.view
      ..physicalSize = const Size(2560, 1600)
      ..devicePixelRatio = 2;
    await settleMd(tester);
    await _type(tester, _text);
    await tester.binding.handlePopRoute();
    await settleMd(tester);
    _expectSaneWidth(tester);
  });

  testWidgets('보기 → 원문 → 보기 on an existing document', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, _text);
    await h.pump(tester, id, size: const Size(800, 1280));
    _expectSaneWidth(tester);
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    await _type(tester, '$_text\n추가 문단은 여기에 적습니다. One more paragraph.\n');
    await tester.tap(find.byKey(MarkdownKeys.mode));
    await settleMd(tester);
    _expectSaneWidth(tester);
    // Rotating while 보기 shows keeps it full width too.
    tester.view.physicalSize = const Size(1280, 800);
    await settleMd(tester);
    _expectSaneWidth(tester);
  });
}
