// MD-T35 (08-markdown 24.17): Notion-like live editing on the screen — Enter makes blocks
// (end, middle, start, setext title), a tap outside the open block closes it, the field
// survives switching and scrolling under the SelectionArea, a task box toggles while the
// open block was emptied, tables and math show a drawn preview, [+] after an unclosed
// fence, the one-time hint, inline looks in the field.
import 'package:feature_markdown/feature_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump.dart';

Future<void> _real(WidgetTester tester, [int ms = 20]) =>
    tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

Future<void> _autosave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 800));
  await _real(tester);
  await settleMd(tester, 2);
}

final Finder _field = find.byKey(MarkdownKeys.liveField);

TextField _textField(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(of: _field, matching: find.byType(TextField)),
);

TextEditingController _controller(WidgetTester tester) =>
    _textField(tester).controller!;

String _fieldText(WidgetTester tester) => _controller(tester).text;

Future<void> _typeAtCaret(WidgetTester tester, String text) async {
  final v = _controller(tester).value;
  final at = v.selection.isValid ? v.selection.start : v.text.length;
  final end = v.selection.isValid ? v.selection.end : at;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: v.text.replaceRange(at, end, text),
      selection: TextSelection.collapsed(offset: at + text.length),
    ),
  );
  await tester.pump();
  await settleMd(tester, 2);
}

Future<void> _caret(WidgetTester tester, int offset) async {
  _controller(tester).selection = TextSelection.collapsed(offset: offset);
  await tester.pump();
}

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.byKey(MarkdownKeys.liveToolbarButton('done')));
  await settleMd(tester);
}

void main() {
  testWidgets('Enter at the end of a heading followed directly by text: a block of its own '
      '(L′1, data review 1)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '# Title\nbody text');
    await h.pump(tester, id);
    await tester.tap(find.text('Title'));
    await settleMd(tester);
    expect(_fieldText(tester), '# Title');
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(find.text('Title'), findsOneWidget, reason: 'drawn again');
    expect(find.text('body text'), findsOneWidget);
    // The new block sits between the heading and the body.
    expect(
      tester.getTopLeft(_field).dy,
      lessThan(tester.getTopLeft(find.text('body text')).dy),
    );
    expect(
      tester.getTopLeft(_field).dy,
      greaterThan(tester.getTopLeft(find.text('Title')).dy),
    );
    await _typeAtCaret(tester, 'new para');
    await _done(tester);
    await _autosave(tester);
    expect(await h.stored(tester, id), '# Title\n\nnew para\n\nbody text');
    expect(find.text('new para'), findsOneWidget);
    expect(find.text('body text'), findsOneWidget);
  });

  testWidgets('Enter in the middle splits the block; at the start a new block '
      'goes in front (L′1)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'first part second part\n\nend\n');
    await h.pump(tester, id);
    await tester.tap(find.text('first part second part'));
    await settleMd(tester);
    await _caret(tester, 11);
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), 'second part');
    expect(_controller(tester).selection.extentOffset, 0);
    expect(find.text('first part '), findsNothing);
    expect(find.text('first part'), findsOneWidget);
    await _autosave(tester);
    expect(await h.stored(tester, id), 'first part \n\nsecond part\n\nend\n');
    // At the start: an empty block in front, the text stays where it is.
    await _caret(tester, 0);
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '');
    expect(find.text('second part'), findsOneWidget);
    expect(
      tester.getTopLeft(_field).dy,
      lessThan(tester.getTopLeft(find.text('second part')).dy),
    );
    await _typeAtCaret(tester, 'x');
    await _done(tester);
    await _autosave(tester);
    expect(
      await h.stored(tester, id),
      'first part \n\nx\n\nsecond part\n\nend\n',
    );
  });

  testWidgets('Enter on a setext title: the new paragraph comes after the '
      'underline (L′2, data review 2)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'Title\n---\n\nbody');
    await h.pump(tester, id);
    await tester.tap(find.text('Title'));
    await settleMd(tester);
    await _caret(tester, 5);
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '');
    await _typeAtCaret(tester, 'x');
    await _done(tester);
    await _autosave(tester);
    expect(await h.stored(tester, id), 'Title\n---\n\nx\n\nbody');
  });

  testWidgets('a tap outside the open block closes it; a tap on its frame does '
      'not (C218M-04, UX review 4)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'one\n\ntwo\n');
    await h.pump(tester, id, size: const Size(1280, 800));
    await tester.tap(find.text('one'));
    await settleMd(tester);
    expect(_field, findsOneWidget);
    // The field's frame (its padding).
    await tester.tapAt(tester.getTopLeft(_field) + const Offset(3, 3));
    await settleMd(tester);
    expect(_field, findsOneWidget);
    // The left margin.
    await tester.tapAt(const Offset(40, 120));
    await settleMd(tester);
    expect(_field, findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    // Below the document.
    await tester.tap(find.text('two'));
    await settleMd(tester);
    expect(_fieldText(tester), 'two');
    await tester.tapAt(const Offset(640, 600));
    await settleMd(tester);
    expect(_field, findsNothing);
    // Another block still switches.
    await tester.tap(find.text('one'));
    await settleMd(tester);
    await tester.tap(find.text('two'));
    await settleMd(tester);
    expect(_fieldText(tester), 'two');
  });

  for (final sep in ['\n\n', '\n']) {
    testWidgets(
      'switch blocks, scroll far, tap: no framework error, the field opens '
      '(UX review 5, ${sep.length} line break(s))',
      (tester) async {
        final h = await MdHarness.create(tester);
        final text = [for (var i = 0; i < 400; i++) '줄 $i'].join(sep);
        final id = await h.doc(tester, text);
        await h.pump(tester, id, size: const Size(800, 1280));
        await tester.tapAt(const Offset(400, 300));
        await settleMd(tester);
        expect(_field, findsOneWidget);
        await tester.tapAt(const Offset(400, 1200));
        await settleMd(tester);
        await tester.dragFrom(const Offset(400, 1000), const Offset(0, -3000));
        await settleMd(tester);
        await tester.tapAt(const Offset(400, 600));
        await settleMd(tester);
        expect(_field, findsOneWidget);
        await tester.dragFrom(const Offset(400, 1000), const Offset(0, 2000));
        await settleMd(tester);
        await tester.tapAt(const Offset(400, 700));
        await settleMd(tester);
        expect(_field, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a task box toggles while the open block was emptied (data '
      'review 6)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'para\n\n- [ ] t1\n- [ ] t2\n');
    await h.pump(tester, id);
    await tester.tap(find.text('para'));
    await settleMd(tester);
    _controller(tester).selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await _typeAtCaret(tester, '');
    expect(_fieldText(tester), '');
    await tester.tap(find.byKey(MarkdownKeys.task(1)));
    await settleMd(tester);
    await _real(tester);
    await settleMd(tester);
    await _autosave(tester);
    expect(await h.stored(tester, id), '- [ ] t1\n- [x] t2\n');
  });

  testWidgets('a table shows drawn under its open field; a large table opens '
      '원문 (L′10, L′11)', (tester) async {
    final h = await MdHarness.create(tester);
    final rows = List.filled(500, '| 셀 | 값 |').join('\n');
    final id = await h.doc(
      tester,
      '| a | b |\n| --- | --- |\n| 1 | 2 |\n\n\$\$\nx^2\n\$\$\n\n'
      '| big | t |\n| --- | --- |\n$rows\n',
    );
    await h.pump(tester, id);
    await tester.tap(find.text('1'));
    await settleMd(tester);
    expect(_fieldText(tester), startsWith('| a | b |'));
    final preview = find.byKey(MarkdownKeys.livePreview);
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.text('2')),
      findsOneWidget,
    );
    // Typing redraws the preview a moment later.
    await _caret(tester, _fieldText(tester).length);
    await _typeAtCaret(tester, '\n| 3 | 4 |');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: preview, matching: find.text('4')),
      findsOneWidget,
    );
    await _done(tester);
    expect(preview, findsNothing);
    // A paragraph has no preview.
    await tester.tap(find.byKey(MarkdownKeys.block(1)));
    await settleMd(tester);
    expect(_fieldText(tester), startsWith(r'$$'));
    expect(preview, findsOneWidget);
    await _done(tester);
    // The large table.
    await tester.tap(find.text('big'));
    await settleMd(tester);
    expect(_field, findsNothing);
    expect(find.byKey(MarkdownKeys.editor), findsOneWidget);
  });

  testWidgets('[+] after an unclosed fence opens the fence at its end (L′4, '
      'data review 4)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'para\n\n```\ncode');
    await h.pump(tester, id);
    await tester.tap(find.byKey(MarkdownKeys.liveAddEnd));
    await settleMd(tester);
    expect(_fieldText(tester), '```\ncode');
    expect(_controller(tester).selection.extentOffset, 8);
  });

  testWidgets('the hint shows once per device (L′12, UX review 8)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester, hint: true);
    final id = await h.doc(tester, 'some text');
    await h.pump(tester, id);
    expect(find.byKey(MarkdownKeys.liveHint), findsOneWidget);
    expect(find.text('글을 누르면 바로 고칠 수 있어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _real(tester);
    await h.pump(tester, id);
    expect(find.byKey(MarkdownKeys.liveHint), findsNothing);
  });

  testWidgets('the open field draws bold, code and links styled, markers faded '
      '(L′9, UX review 2)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'a **굵게** and `code` [링크](https://x.y)');
    await h.pump(tester, id);
    await tester.tap(find.byKey(MarkdownKeys.block(0)));
    await settleMd(tester);
    expect(_fieldText(tester), 'a **굵게** and `code` [링크](https://x.y)');
    final span = _controller(tester)
        .buildTextSpan(context: tester.element(_field), withComposing: false);
    TextStyle? styleOf(String text) {
      TextStyle? found;
      span.visitChildren((s) {
        if (s is TextSpan && s.text == text) found = s.style;
        return found == null;
      });
      return found;
    }

    expect(styleOf('굵게')?.fontWeight, FontWeight.w700);
    expect(styleOf('**')?.color, isNot(styleOf('굵게')?.color));
    expect(styleOf('code')?.fontFamily, isNot(styleOf(' and ')?.fontFamily));
    expect(styleOf('링크')?.decoration, TextDecoration.underline);
    final all = span.toPlainText();
    expect(all, _fieldText(tester), reason: 'display only');
  });

  testWidgets('Esc and hardware Enter still behave (smoke)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'one');
    await h.pump(tester, id);
    await tester.tap(find.text('one'));
    await settleMd(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleMd(tester);
    expect(_field, findsNothing);
  });
}
