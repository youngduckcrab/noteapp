// MD-T22 / MD-T23 / MD-T31 (08-markdown 24.2 … 24.7, 24.15): the pure edits of the live
// field, the list item spans and the edit units.
import 'package:feature_markdown/src/live/live_edit.dart';
import 'package:feature_markdown/src/live/live_units.dart';
import 'package:feature_markdown/src/parse/list_items.dart';
import 'package:feature_markdown/src/parse/md_document.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _at(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

String _show(TextEditingValue v) {
  final c = v.selection.extentOffset;
  return '${v.text.substring(0, c)}|${v.text.substring(c)}';
}

void main() {
  group('Enter (24.15 U′5)', () {
    String enter(String text, [int? caret, LiveKind kind = LiveKind.prose]) {
      final out = liveEnter(_at(text, caret), kind);
      return out == null ? 'newline' : _show(out);
    }

    test('paragraph and heading: a new paragraph line in the same field', () {
      expect(enter('첫 문단'), '첫 문단\n\n|');
      expect(enter('# 제목'), '# 제목\n\n|');
      expect(enter('ab', 1), 'a\n\n|b');
    });

    test('lists continue: bullet, number + 1, task box, indent kept', () {
      expect(enter('- 사과'), '- 사과\n- |');
      expect(enter('* a'), '* a\n* |');
      expect(enter('1. 하나'), '1. 하나\n2. |');
      expect(enter('9) nine'), '9) nine\n10) |');
      expect(enter('- [x] done'), '- [x] done\n- [ ] |');
      expect(enter('  - nested'), '  - nested\n  - |');
      // Caret inside the marker counts as just after it.
      expect(enter('- abc', 1), '- \n- |abc');
    });

    test('an empty item or quote line leaves the list', () {
      expect(enter('- a\n- '), '- a\n\n|');
      expect(enter('- [ ] '), '|');
      expect(enter('> 인용\n> '), '> 인용\n\n|');
      expect(enter('> 인용'), '> 인용\n> |');
    });

    test('code fields, fences inside prose: a plain newline', () {
      expect(enter('x = 1', null, LiveKind.code), 'newline');
      expect(enter('```\ncode'), 'newline');
      expect(enter('```\ncode\n```'), '```\ncode\n```\n\n|');
    });

    test('nothing to split: an empty field or an empty line stays', () {
      expect(enter(''), '|');
      expect(enter('a\n\n'), 'a\n\n|');
    });

    test('a continuation line keeps its indent', () {
      expect(enter('- a\n  more'), '- a\n  more\n  |');
    });

    test('Shift+Enter: a newline; in an item indented to its content', () {
      expect(_show(liveShiftEnter(_at('ab', 1), LiveKind.prose)), 'a\n|b');
      expect(_show(liveShiftEnter(_at('- ab'), LiveKind.prose)), '- ab\n  |');
      expect(_show(liveShiftEnter(_at('# T'), LiveKind.prose)), '# T\n\n|');
    });
  });

  group('the Enter formatter', () {
    final f = LiveEnterFormatter(() => LiveKind.prose);

    test('a typed newline at the caret becomes liveEnter', () {
      final out = f.formatEditUpdate(_at('- a'), _at('- a\n'));
      expect(_show(out), '- a\n- |');
    });

    test('while composing (Korean IME) nothing is rewritten', () {
      final composing = TextEditingValue(
        text: '한\n',
        selection: const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 1),
      );
      expect(f.formatEditUpdate(_at('한'), composing), composing);
    });

    test('pastes and other edits pass', () {
      final paste = _at('a\nb\nc');
      expect(f.formatEditUpdate(_at('a'), paste), paste);
    });

    test('CR LF and lone CR become LF', () {
      const lf = LineFeedFormatter();
      final out = lf.formatEditUpdate(_at(''), _at('a\r\nb\rc'));
      expect(out.text, 'a\nb\nc');
      expect(out.selection.extentOffset, 5);
    });
  });

  group('markers', () {
    test('Backspace at the start strips the first line marker', () {
      expect(stripFirstMarker(_at('- [ ] 할 일'))!.$1.text, '할 일');
      expect(stripFirstMarker(_at('## 제목'))!.$1.text, '제목');
      expect(stripFirstMarker(_at('> 인용'))!.$1.text, '인용');
      expect(stripFirstMarker(_at('12. 번호'))!.$1.text, '번호');
      expect(stripFirstMarker(_at('글')), isNull);
    });
  });

  group('toolbar (MD-T31)', () {
    TextEditingValue sel(String text, int a, int b) => TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: a, extentOffset: b),
    );

    test('wrap and unwrap', () {
      final b = toggleWrap(sel('a word b', 2, 6), '**');
      expect(b.text, 'a **word** b');
      expect(b.selection, const TextSelection(baseOffset: 4, extentOffset: 8));
      expect(toggleWrap(b, '**').text, 'a word b');
      expect(toggleWrap(sel('**x**', 0, 5), '**').text, 'x');
      expect(_show(toggleWrap(_at('ab', 1), '`')), 'a`|`b');
      expect(toggleWrap(sel('a~~b~~', 3, 4), '~~').text, 'ab');
    });

    test('link', () {
      expect(_show(insertLink(_at('go '))), 'go [|]()');
      expect(_show(insertLink(sel('see docs', 4, 8))), 'see [docs](|)');
    });

    test('line starters swap, number and toggle off', () {
      expect(toggleLinePrefix(_at('a'), LinePrefix.bullet).text, '- a');
      expect(toggleLinePrefix(_at('- a'), LinePrefix.bullet).text, 'a');
      expect(toggleLinePrefix(_at('- a'), LinePrefix.task).text, '- [ ] a');
      expect(
        toggleLinePrefix(sel('a\nb', 0, 3), LinePrefix.numbered).text,
        '1. a\n2. b',
      );
      expect(toggleLinePrefix(_at('# a'), LinePrefix.h2).text, '## a');
      expect(toggleLinePrefix(_at('## a'), LinePrefix.h2).text, 'a');
      expect(toggleLinePrefix(_at('a'), LinePrefix.quote).text, '> a');
      // An empty field (a fresh block) takes the marker; the caret follows it.
      for (final (p, m) in [
        (LinePrefix.h1, '# '),
        (LinePrefix.bullet, '- '),
        (LinePrefix.task, '- [ ] '),
        (LinePrefix.numbered, '1. '),
        (LinePrefix.quote, '> '),
      ]) {
        final v = toggleLinePrefix(_at(''), p);
        expect(v.text, m);
        expect(v.selection.baseOffset, m.length);
        expect(toggleLinePrefix(v, p).text, '');
      }
      // Headings take the caret's line only.
      expect(toggleLinePrefix(sel('a\nb', 0, 3), LinePrefix.h1).text, '# a\nb');
    });

    test('block templates go after the caret line', () {
      expect(
        _show(insertTemplate(_at('글'), LiveTemplate.codeBlock)),
        '글\n\n```\n|\n```',
      );
      expect(
        _show(insertTemplate(_at(''), LiveTemplate.mathBlock)),
        '\$\$\n|\n\$\$',
      );
      expect(
        _show(insertTemplate(_at('a'), LiveTemplate.rule)),
        'a\n\n---\n\n|',
      );
      final t = insertTemplate(_at('a'), LiveTemplate.table);
      expect(t.text, 'a\n\n| 제목 | 제목 |\n| --- | --- |\n|  |  |');
      expect(_show(t).endsWith('\n| | |  |'), isTrue);
    });

    test('indent by the marker width above (24.15 D′14)', () {
      expect(
        indentField(_at('1. a\n2. b'), indent: true).text,
        '1. a\n   2. b',
      );
      expect(indentField(_at('10. a\nb'), indent: true).text, '10. a\n    b');
      expect(indentField(_at('- a\n- b'), indent: true).text, '- a\n  - b');
      expect(indentField(_at('- a\n  - b'), indent: false).text, '- a\n- b');
      expect(indentField(_at('\tx'), indent: false).text, 'x');
    });
  });

  group('compose (24.3, D′6)', () {
    test('only the range changes; a new block exists only once typed', () {
      const base = 'a\n\nb\n';
      const r = LiveRange(start: 3, end: 4);
      expect(composeLive(base, r, 'B!'), 'a\n\nB!\n');
      final end = pendingAtEnd(base, 4);
      expect(composeLive(base, end, ''), base);
      expect(composeLive(base, end, 'c'), 'a\n\nb\n\nc\n');
      const empty = LiveRange(start: 0, end: 0, pending: true);
      expect(composeLive('', empty, '첫'), '첫');
    });
  });

  group('tap → caret (R15)', () {
    test('drawn text walks back to the source', () {
      expect(sourceOffsetForPlain('**굵게** 글', '굵게 글', 2), 4);
      expect(sourceOffsetForPlain('[링크](http://x) 뒤', '링크 뒤', 4), 16);
      expect(sourceOffsetForPlain('[링크](http://x) 뒤', '링크 뒤', 1), 2);
      expect(sourceOffsetForPlain('- [ ] 할 일', '할 일', 1), 7);
      expect(sourceOffsetForPlain('`a` b', 'a b', 3), 5);
      expect(sourceOffsetForPlain('abc', 'zzz', 2), 3);
      expect(sourceOffsetForPlain('# 제목', '제목', 0), 2);
    });
  });

  group('list item spans (24.15 D′8)', () {
    List<(int, int)> spans(String text) {
      final s = scanTopLevelItems(text, 0, text.length)!;
      return [for (final x in s) (x.start, x.end)];
    }

    test('top-level items own their nested items and continuations', () {
      const t = '- p\n  - c\n\n  p cont\n- q';
      expect(spans(t), [(0, 19), (20, 23)]);
      expect(t.substring(0, 19), '- p\n  - c\n\n  p cont');
    });

    test('ordered, loose, tasks, tabs', () {
      expect(spans('1. a\n2. b\n\n3. c'), [(0, 4), (5, 9), (11, 15)]);
      expect(spans('- [ ] a\n- [x] b'), [(0, 7), (8, 15)]);
      expect(spans('- a\n\t- b\n- c'), [(0, 8), (9, 12)]);
      expect(spans('10. a\n    - x\n11. b'), [(0, 13), (14, 19)]);
    });

    test('units: per item when the parser agrees, else the whole block', () {
      final doc = parseMarkdown(
        '# T\n\n- a\n- b\n  - c\n\n```\nx\n```\n\n[r]: http://x\n',
      );
      final layout = LiveLayout.of(doc);
      final kinds = [
        for (final u in layout.units)
          (u.block, u.item, doc.source.substring(u.start, u.end), u.kind),
      ];
      expect(kinds, [
        (0, null, '# T', LiveKind.prose),
        (1, 0, '- a', LiveKind.prose),
        (1, 1, '- b\n  - c', LiveKind.prose),
        (2, null, '```\nx\n```', LiveKind.code),
        (3, null, '[r]: http://x', LiveKind.code),
      ]);
      expect(layout.units.last.definition, isTrue);
      // Two lists in one block (marker change, or a blank line before a numbered
      // list): still one unit per item.
      final mixed = LiveLayout.of(parseMarkdown('- a\n* b\n\n1. c'));
      expect([for (final u in mixed.units) u.item], [0, 1, 2]);
      // Spans that do not agree with the parser's items: not used.
      final doc2 = parseMarkdown('- a\n- b');
      expect(
        itemSpansMatch(doc2.source, doc2.blocks.single, const [
          ItemSpan(0, 7, 2),
        ]),
        isFalse,
      );
    });

    test('a block the markdown package gives up on is drawn as text', () {
      // markdown 7.3.1 throws 'parseLines is not advancing' on this one.
      final doc = parseMarkdown('a\n\n[]()\n| --- | --- |\n\nb');
      expect(doc.blocks, hasLength(3));
      expect(doc.blocks[1].plainText, contains('[]()'));
    });

    test('setext headings are marked', () {
      final layout = LiveLayout.of(parseMarkdown('Title\n===\n\npara'));
      expect(layout.units.first.setext, isTrue);
      expect(layout.units.last.setext, isFalse);
    });
  });
}
