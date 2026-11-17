// MD-T22 … MD-T30 (08-markdown 24, 24.15): live block editing on the screen — new
// documents type in place, taps open blocks with the caret near the tap, Enter / Backspace
// / arrows, list and task continuation, the toolbar, undo / redo, autosave and IME
// composing, back order, app pause, other devices' text, 원문 and 나란히, task boxes,
// search landing, empty and read-only documents, scrolling away, line endings.
import 'dart:async';

import 'package:feature_markdown/feature_markdown.dart';
import 'package:feature_markdown/src/parse/md_document.dart'
    show debugParseCount;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

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

String _fieldText(WidgetTester tester) => _textField(tester).controller!.text;

/// Types [value] into the field the way an IME does (a whole new value).
Future<void> _ime(WidgetTester tester, TextEditingValue value) async {
  tester.testTextInput.updateEditingValue(value);
  await tester.pump();
}

/// Types [text] at the caret.
Future<void> _typeAtCaret(WidgetTester tester, String text) async {
  final c = _textField(tester).controller!;
  final v = c.value;
  final at = v.selection.isValid ? v.selection.start : v.text.length;
  final end = v.selection.isValid ? v.selection.end : at;
  await _ime(
    tester,
    TextEditingValue(
      text: v.text.replaceRange(at, end, text),
      selection: TextSelection.collapsed(offset: at + text.length),
    ),
  );
}

Future<void> _done(WidgetTester tester) async {
  await tester.tap(find.byKey(MarkdownKeys.liveToolbarButton('done')));
  await settleMd(tester);
}

Future<void> _tool(WidgetTester tester, String name) async {
  final b = find.byKey(MarkdownKeys.liveToolbarButton(name));
  final row = find
      .descendant(
        of: find.byKey(MarkdownKeys.liveToolbar),
        matching: find.byType(Scrollable),
      )
      .first;
  // The row scrolls on a phone (lazy): back to its start, then along.
  if (b.evaluate().isEmpty) {
    for (var i = 0; i < 10; i++) {
      await tester.drag(row, const Offset(400, 0));
      await tester.pump();
    }
    for (var i = 0; i < 20 && b.evaluate().isEmpty; i++) {
      await tester.drag(row, const Offset(-120, 0));
      await tester.pump();
    }
  }
  await tester.ensureVisible(b);
  await tester.pump();
  await tester.tap(b);
  await tester.pump();
}

void main() {
  testWidgets(
    '새 MD 문서: 보기 opens with a field and the keyboard; text goes in as typed '
    '(MD-T25, MD-T30)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '');
      await h.pump(tester, id, initialEdit: true);
      expect(find.byKey(MarkdownKeys.view), findsOneWidget);
      expect(find.byKey(MarkdownKeys.editor), findsNothing);
      expect(_field, findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.byKey(MarkdownKeys.liveToolbar), findsOneWidget);
      expect(find.text('여기에 쓰세요'), findsOneWidget);
      await _typeAtCaret(tester, '안녕');
      await _typeAtCaret(tester, ' world');
      await _autosave(tester);
      // No leading newline: an empty document's first block has no separator.
      expect(await h.stored(tester, id), '안녕 world');
      // Enter starts a new paragraph line in the same field (24.15 U′5).
      await _typeAtCaret(tester, '\n');
      expect(_fieldText(tester), '안녕 world\n\n');
      await _typeAtCaret(tester, '둘째 문단');
      await _done(tester);
      expect(_field, findsNothing);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('안녕 world'), findsOneWidget);
      expect(find.text('둘째 문단'), findsOneWidget);
      await _autosave(tester);
      expect(await h.stored(tester, id), '안녕 world\n\n둘째 문단');
    },
  );

  testWidgets(
    'tap a block: its source in place, caret near the tap; other blocks stay '
    'drawn (MD-T22)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '# 제목\n\n첫 **굵은** 문단\n\n끝 문단\n');
      await h.pump(tester, id);
      await tester.tap(find.text('끝 문단'));
      await settleMd(tester);
      expect(_fieldText(tester), '끝 문단');
      expect(find.text('제목'), findsOneWidget);
      // Tap on the first word of the bold paragraph: the caret lands inside it.
      await tester.tapAt(
        tester.getTopLeft(find.text('첫 굵은 문단', findRichText: true)) +
            const Offset(4, 8),
      );
      await settleMd(tester);
      expect(_fieldText(tester), '첫 **굵은** 문단');
      final sel = _textField(tester).controller!.selection;
      expect(sel.extentOffset, lessThanOrEqualTo(2));
      // The keyboard stayed up moving between blocks (one field, one focus — U′5).
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.text('끝 문단'), findsOneWidget);
    },
  );

  testWidgets(
    'editing changes only that block; CRLF and BOM come back (MD-T21)',
    (tester) async {
      final h = await MdHarness.create(tester);
      const raw = '﻿# T\r\n\r\nalpha\r\n\r\n- a\r\n- b\r\n';
      final id = await h.doc(tester, raw);
      await h.pump(tester, id);
      await tester.tap(find.text('alpha'));
      await settleMd(tester);
      await _ime(
        tester,
        const TextEditingValue(
          text: 'alpha!',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await _autosave(tester);
      expect(
        await h.stored(tester, id),
        '﻿# T\r\n\r\nalpha!\r\n\r\n- a\r\n- b\r\n',
      );
    },
  );

  testWidgets('lists: one top-level item per field, Enter continues, an empty item leaves '
      '(MD-T23)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, '- 사과\n- 배\n\n1. 하나\n\n- [ ] 할 일\n');
    await h.pump(tester, id);
    await tester.tap(find.text('배'));
    await settleMd(tester);
    expect(_fieldText(tester), '- 배');
    expect(find.text('사과'), findsOneWidget);
    _textField(tester).controller!.selection = const TextSelection.collapsed(
      offset: 3,
    );
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '- 배\n- ');
    await _typeAtCaret(tester, '감');
    await _typeAtCaret(tester, '\n');
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '- 배\n- 감\n\n');
    await _typeAtCaret(tester, '문단');
    await _done(tester);
    await _autosave(tester);
    expect(
      await h.stored(tester, id),
      '- 사과\n- 배\n- 감\n\n문단\n\n1. 하나\n\n- [ ] 할 일\n',
    );
    await tester.tap(find.text('하나'));
    await settleMd(tester);
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '1. 하나\n2. ');
    await _done(tester);
    await tester.tap(find.text('할 일'));
    await settleMd(tester);
    await _typeAtCaret(tester, '\n');
    expect(_fieldText(tester), '- [ ] 할 일\n- [ ] ');
  });

  testWidgets(
    'Backspace at the start (hardware key): marker, then join (MD-T23)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '첫 문단\n\n## 둘째\n');
      await h.pump(tester, id);
      await tester.tap(find.text('둘째'));
      await settleMd(tester);
      _textField(tester).controller!.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(_fieldText(tester), '둘째');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(_fieldText(tester), '첫 문단둘째');
      expect(_textField(tester).controller!.selection.extentOffset, 4);
      await _done(tester);
      await _autosave(tester);
      expect(await h.stored(tester, id), '첫 문단둘째\n');
    },
  );

  testWidgets('↑ / ↓ move between blocks, Esc closes, Tab indents (MD-T23)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'one\n\ntwo\n\n- a\n- b\n');
    await h.pump(tester, id);
    await tester.tap(find.text('two'));
    await settleMd(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settleMd(tester);
    expect(_fieldText(tester), 'one');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settleMd(tester);
    expect(_fieldText(tester), 'two');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settleMd(tester);
    expect(_fieldText(tester), '- a');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settleMd(tester);
    expect(_fieldText(tester), '- b');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_fieldText(tester), '  - b');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleMd(tester);
    expect(_field, findsNothing);
    await _autosave(tester);
    expect(await h.stored(tester, id), 'one\n\ntwo\n\n- a\n  - b\n');
  });

  testWidgets(
    'toolbar: wraps, starters, templates; 48 dp; finishes composing first '
    '(MD-T31, U′7)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, 'word\n');
      await h.pump(tester, id, size: const Size(390, 844));
      await tester.tap(find.text('word'));
      await settleMd(tester);
      final c = _textField(tester).controller!;
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await _tool(tester, 'bold');
      expect(_fieldText(tester), '**word**');
      await _tool(tester, 'h2');
      expect(_fieldText(tester), '## **word**');
      await _tool(tester, 'bullet');
      expect(_fieldText(tester), '- **word**');
      // A syllable composing, then [할 일]: the composition ends, the edit is one value.
      await _ime(
        tester,
        TextEditingValue(
          text: '${c.text}한',
          selection: TextSelection.collapsed(offset: c.text.length + 1),
          composing: TextRange(start: c.text.length, end: c.text.length + 1),
        ),
      );
      await _tool(tester, 'task');
      expect(_fieldText(tester), '- [ ] **word**한');
      expect(c.value.composing.isValid, isFalse);
      await _tool(tester, 'codeBlock');
      expect(_fieldText(tester), '- [ ] **word**한\n\n```\n\n```');
      for (final e
          in find
              .descendant(
                of: find.byKey(MarkdownKeys.liveToolbar),
                matching: find.byType(InkWell),
              )
              .evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
      await _done(tester);
      await _autosave(tester);
      expect(await h.stored(tester, id), '- [ ] **word**한\n\n```\n\n```\n');
    },
  );

  testWidgets(
    'undo / redo: one step per block edit, the changed block reopens (MD-T27)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, 'aa\n\nbb\n');
      await h.pump(tester, id);
      await tester.tap(find.text('bb'));
      await settleMd(tester);
      await _typeAtCaret(tester, '!');
      await _done(tester);
      await tester.tap(find.text('aa'));
      await settleMd(tester);
      await _typeAtCaret(tester, '?');
      await tester.tap(find.byKey(MarkdownKeys.undo));
      await settleMd(tester);
      expect(_fieldText(tester), 'aa');
      await tester.tap(find.byKey(MarkdownKeys.undo));
      await settleMd(tester);
      expect(_fieldText(tester), 'bb');
      await tester.tap(find.byKey(MarkdownKeys.redo));
      await settleMd(tester);
      expect(_fieldText(tester), 'bb!');
      await _autosave(tester);
      expect(await h.stored(tester, id), 'aa\n\nbb!\n');
    },
  );

  testWidgets('autosave while the field stays open; IME composing delays it; typing never '
      'parses (MD-T26, D′2)', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'x\n');
    await h.pump(tester, id);
    await tester.tap(find.text('x'));
    await settleMd(tester);
    final parses = debugParseCount;
    await _ime(
      tester,
      const TextEditingValue(
        text: 'x한',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await _real(tester);
    expect(await h.stored(tester, id), 'x\n', reason: 'composing: save waits');
    await tester.pump(const Duration(milliseconds: 1200));
    await _real(tester);
    await settleMd(tester, 2);
    expect(await h.stored(tester, id), 'x한\n', reason: 'at most 1 s later');
    await _ime(
      tester,
      const TextEditingValue(
        text: 'x한글',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await _autosave(tester);
    expect(await h.stored(tester, id), 'x한글\n');
    expect(_field, findsOneWidget);
    expect(debugParseCount, parses);
  });

  testWidgets(
    'back: ① the open block closes ② then the screen (saved) (MD-T30)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, 'a\n');
      await h.pump(tester, id);
      await tester.tap(find.text('a'));
      await settleMd(tester);
      await _typeAtCaret(tester, 'b');
      await tester.binding.handlePopRoute();
      await settleMd(tester);
      expect(_field, findsNothing);
      expect(h.closed, 0);
      await _real(tester);
      expect(await h.stored(tester, id), 'ab\n');
      await tester.binding.handlePopRoute();
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      expect(h.closed, 1);
    },
  );

  testWidgets('app paused with a block open: saved at once (kill safety)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'a\n');
    await h.pump(tester, id);
    await tester.tap(find.text('a'));
    await settleMd(tester);
    await _typeAtCaret(tester, '!');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _real(tester);
    await settleMd(tester, 2);
    expect(await h.stored(tester, id), 'a!\n');
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleMd(tester);
    expect(_field, findsOneWidget);
  });

  testWidgets(
    'another device\'s text while a block is open: held, no overwrite (MD-T28)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, 'a\n\nb\n');
      await h.pump(tester, id);
      await tester.tap(find.text('b'));
      await settleMd(tester);
      await _typeAtCaret(tester, '1');
      await _autosave(tester);
      expect(await h.stored(tester, id), 'a\n\nb1\n');
      final doc = (await tester.runAsync(() => h.store.markdown.get(id)))!;
      await tester.runAsync(
        () => h.store.markdown.saveText(
          id,
          'remote\n',
          baseVersion: doc.textVersion,
        ),
      );
      await _real(tester);
      await settleMd(tester);
      expect(_fieldText(tester), 'b1');
      await _typeAtCaret(tester, '2');
      await _autosave(tester);
      expect(await h.stored(tester, id), 'a\n\nb12\n');
      expect(find.byKey(MarkdownKeys.bannerConflictCopy), findsOneWidget);
    },
  );

  testWidgets(
    'a task box of another block while one is open toggles the right box '
    '(MD-T29)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, 'top\n\n- [ ] one\n- [ ] two\n');
      await h.pump(tester, id);
      await tester.tap(find.text('top'));
      await settleMd(tester);
      await _typeAtCaret(tester, ' grows longer');
      await tester.tap(find.byKey(MarkdownKeys.task(1)));
      await settleMd(tester);
      await _real(tester);
      await settleMd(tester);
      expect(_field, findsNothing);
      expect(
        await h.stored(tester, id),
        'top grows longer\n\n- [ ] one\n- [x] two\n',
      );
    },
  );

  testWidgets(
    '원문 still edits the whole source; the editor is not mounted in 보기; '
    '나란히 preview is not live (MD-T30)',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, '# a\n\nb\n');
      await h.pump(tester, id, size: const Size(1400, 900));
      expect(
        find.byKey(MarkdownKeys.editor, skipOffstage: false),
        findsNothing,
      );
      await tester.tap(find.text('b'));
      await settleMd(tester);
      await _typeAtCaret(tester, 'c');
      await tester.tap(find.byKey(MarkdownKeys.mode));
      await settleMd(tester);
      expect(_field, findsNothing);
      final editor = tester.widget<TextField>(find.byKey(MarkdownKeys.editor));
      expect(editor.controller!.text, '# a\n\nbc\n');
      expect(editor.controller!.selection.extentOffset, 7);
      await tester.tap(find.byKey(MarkdownKeys.split));
      await settleMd(tester);
      expect(find.byKey(MarkdownKeys.splitPreview), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(MarkdownKeys.splitPreview),
          matching: find.text('bc'),
        ),
      );
      await settleMd(tester);
      expect(_field, findsNothing);
      expect(find.byKey(MarkdownKeys.liveAddEnd), findsNothing);
    },
  );

  testWidgets(
    'search landing highlights, and the highlighted block opens on a tap',
    (tester) async {
      final h = await MdHarness.create(tester);
      final text = [for (var i = 0; i < 80; i++) '문단 $i 내용'].join('\n\n');
      final id = await h.doc(tester, '$text\n\n찾는 낱말 여기\n');
      await h.pump(tester, id, query: '찾는 낱말');
      await settleMd(tester, 12);
      expect(find.byKey(MarkdownKeys.highlight), findsOneWidget);
      await tester.tap(find.text('찾는 낱말 여기'));
      await settleMd(tester);
      expect(_fieldText(tester), '찾는 낱말 여기');
    },
  );

  testWidgets('read-only documents never open a field (MD-T30)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'text\n');
    await tester.runAsync(() => h.store.library.trashItems([NoteRef(id)]));
    await h.pump(tester, id);
    await tester.tap(find.text('text'));
    await settleMd(tester);
    expect(_field, findsNothing);
    expect(find.byKey(MarkdownKeys.liveAddEnd), findsNothing);
  });

  testWidgets(
    '[+] under the last block adds a paragraph; left empty nothing changes',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(tester, 'a\n');
      await h.pump(tester, id);
      await tester.tap(find.byKey(MarkdownKeys.liveAddEnd));
      await settleMd(tester);
      expect(_fieldText(tester), '');
      await _typeAtCaret(tester, 'x');
      await _typeAtCaret(tester, '');
      await _ime(
        tester,
        const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
      );
      await _done(tester);
      await _autosave(tester);
      expect(await h.stored(tester, id), 'a\n');
      await tester.tap(find.byKey(MarkdownKeys.liveAddEnd));
      await settleMd(tester);
      await _typeAtCaret(tester, 'b');
      await _done(tester);
      await _autosave(tester);
      expect(await h.stored(tester, id), 'a\n\nb\n');
    },
  );

  testWidgets('the open field survives scrolling far away and back (D′12)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final text = [for (var i = 0; i < 120; i++) '줄 $i'].join('\n\n');
    final id = await h.doc(tester, text);
    await h.pump(tester, id, size: const Size(800, 600));
    await tester.tap(find.text('줄 1'));
    await settleMd(tester);
    await _typeAtCaret(tester, '!');
    await tester.drag(find.byKey(MarkdownKeys.view), const Offset(0, -3000));
    await settleMd(tester);
    await tester.drag(find.byKey(MarkdownKeys.view), const Offset(0, 4000));
    await settleMd(tester);
    expect(_fieldText(tester), '줄 1!');
    expect(tester.testTextInput.isVisible, isTrue);
    await _typeAtCaret(tester, '?');
    await _done(tester);
    await _autosave(tester);
    expect(
      (await h.stored(tester, id)).startsWith('줄 0\n\n줄 1!?\n\n줄 2'),
      isTrue,
    );
  });

  testWidgets(
    'a definition draws as a chip and opens; links keep their sheet with '
    '[이 블록 고치기]',
    (tester) async {
      final h = await MdHarness.create(tester);
      final id = await h.doc(
        tester,
        '[docs](https://x.y)\n\n[r]: https://example.com\n',
      );
      await h.pump(tester, id);
      expect(find.byKey(MarkdownKeys.liveDefinition(1)), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.liveDefinition(1)));
      await settleMd(tester);
      expect(_fieldText(tester), '[r]: https://example.com');
      await _done(tester);
      await tester.tapOnText(find.textRange.ofSubstring('docs'));
      await settleMd(tester);
      expect(_field, findsNothing, reason: 'the link wins the tap');
      expect(find.byKey(MarkdownKeys.linkSheet), findsOneWidget);
      await tester.tap(find.byKey(MarkdownKeys.linkSheetEdit));
      await settleMd(tester);
      expect(_fieldText(tester), '[docs](https://x.y)');
    },
  );

  testWidgets('a huge block opens 원문 at that place instead (D′11)', (
    tester,
  ) async {
    final h = await MdHarness.create(tester);
    final big = List.filled(2500, 'longline').join(' ');
    final id = await h.doc(tester, 'a\n\n$big\n');
    await h.pump(tester, id);
    await tester.tapAt(
      tester.getTopLeft(find.byKey(MarkdownKeys.block(1))) +
          const Offset(20, 10),
    );
    await settleMd(tester);
    expect(_field, findsNothing);
    expect(find.byKey(MarkdownKeys.editor), findsOneWidget);
    expect(find.text('이 블록은 길어서 원문에서 고쳐요'), findsOneWidget);
  });

  testWidgets('rotation keeps the open field and its text', (tester) async {
    final h = await MdHarness.create(tester);
    final id = await h.doc(tester, 'a\n\nb\n');
    await h.pump(tester, id, size: const Size(1280, 800));
    await tester.tap(find.text('b'));
    await settleMd(tester);
    await _typeAtCaret(tester, '!');
    tester.view.physicalSize = const Size(800, 1280);
    await settleMd(tester);
    expect(_fieldText(tester), 'b!');
    await _typeAtCaret(tester, '?');
    expect(_fieldText(tester), 'b!?');
    unawaited(Future<void>.value());
  });
}
