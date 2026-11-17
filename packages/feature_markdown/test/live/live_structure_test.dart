// MD-T34 (08-markdown 24.17): live edits keep the block layout the user meant — Enter
// after a heading or a setext title, items losing their marker by any route, emptied
// blocks, a new block after an unclosed fence, thematic breaks and numbered lines in a
// paragraph; the inline looks of the field. Pure edits and the editor on a controller.
import 'package:feature_markdown/src/live/live_edit.dart';
import 'package:feature_markdown/src/live/live_editor.dart';
import 'package:feature_markdown/src/live/live_inline.dart';
import 'package:feature_markdown/src/live/live_units.dart';
import 'package:feature_markdown/src/parse/block_splitter.dart';
import 'package:feature_markdown/src/parse/md_document.dart';
import 'package:feature_markdown/src/parse/md_model.dart';
import 'package:feature_markdown/src/screen/markdown_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

TextEditingValue _at(String text, [int? caret]) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret ?? text.length),
);

String _show(TextEditingValue v) {
  final c = v.selection.extentOffset;
  return '${v.text.substring(0, c)}|${v.text.substring(c)}';
}

String _enter(String text, [int? caret]) {
  final out = liveEnter(_at(text, caret), LiveKind.prose);
  return out == null ? 'newline' : _show(out);
}

/// The kinds of the top-level blocks of [text] (paragraph, heading, list, …).
List<String> _shape(String text) => [
  for (final b in parseMarkdown(text).blocks)
    for (final n in b.nodes)
      switch (n) {
        MdHeading(:final level) => 'h$level',
        MdParagraph() => 'p',
        MdList(:final items) => 'list${items.length}',
        MdRule() => 'rule',
        MdCodeBlock() => 'code',
        _ => n.runtimeType.toString(),
      },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lines (L′7)', () {
    test('a thematic break is no list item', () {
      expect(_enter('* * *'), '* * *\n\n|');
      expect(_enter('- - -'), '- - -\n\n|');
      expect(lineMarkerLength('* * *'), 0);
      expect(lineMarkerLength('- - -'), 0);
      expect(stripFirstMarker(_at('* * *')), isNull);
      expect(startsListItem('---'), isFalse);
      expect(startsListItem('- a'), isTrue);
      expect(toggleLinePrefix(_at('* * *'), LinePrefix.bullet).text, '- * * *');
    });

    test('a numbered line inside a paragraph is paragraph text', () {
      expect(_enter('foo\n2024. not a list'), 'foo\n2024. not a list\n\n|');
      expect(liveEnterIsParagraph(_at('foo\n2024. x'), LiveKind.prose), isTrue);
      // … unless it can start a list there.
      expect(_enter('2024. first line'), '2024. first line\n2025. |');
      expect(_enter('foo\n1. one'), 'foo\n1. one\n2. |');
      expect(_enter('1. a\n2. b'), '1. a\n2. b\n3. |');
      expect(_enter('foo\n\n7. x'), 'foo\n\n7. x\n8. |');
    });

    test('Enter kinds: paragraph, leave a list, the rest', () {
      expect(liveEnterIsParagraph(_at('# 제목'), LiveKind.prose), isTrue);
      expect(liveEnterIsParagraph(_at('- a'), LiveKind.prose), isFalse);
      expect(liveEnterIsParagraph(_at('a\n\n'), LiveKind.prose), isFalse);
      expect(liveEnterIsParagraph(_at('x'), LiveKind.code), isFalse);
      final seen = <(String, bool)>[];
      final f = LiveEnterFormatter(
        () => LiveKind.prose,
        onParagraph: (old, {required leave}) {
          seen.add((old.text, leave));
          return old;
        },
      );
      TextEditingValue type(String text) =>
          f.formatEditUpdate(_at(text), _at('$text\n'));
      expect(type('문단').text, '문단');
      expect(type('- a\n- ').text, '- a\n- ');
      expect(type('- a').text, '- a\n- ', reason: 'no hook for a list line');
      expect(seen, [('문단', false), ('- a\n- ', true)]);
    });

    test('bare marker lines', () {
      expect(isBareMarkerLine('- '), isTrue);
      expect(isBareMarkerLine('2. '), isTrue);
      expect(isBareMarkerLine('- [ ] '), isTrue);
      expect(isBareMarkerLine('> '), isTrue);
      expect(isBareMarkerLine('- a'), isFalse);
      expect(isBareMarkerLine('---'), isFalse);
    });
  });

  group('ranges', () {
    test('a new block after a block keeps off the next line (L′1)', () {
      expect(textOnNextLine('# T\nbody', 3), isTrue);
      expect(textOnNextLine('# T\n\nbody', 3), isFalse);
      expect(textOnNextLine('# T\n  \nbody', 3), isFalse);
      expect(textOnNextLine('# T', 3), isFalse);
      final base = '# T\nbody';
      final r = pendingAfter(base, 3);
      final out = composeLive(base, r, 'new');
      expect(out, '# T\n\nnew\n\nbody');
      expect(_shape(out), ['h1', 'p', 'p']);
      expect(composeLive(base, r, ''), base);
      expect(composeLive('a\n\nb', pendingBefore(3), 'x'), 'a\n\nx\n\nb');
    });

    test('an emptied block goes, its neighbours stay apart (L′5)', () {
      String empty(String base, int cs, int ce, {bool item = false}) =>
          composeLive(base, emptiedRange(base, cs, ce, item: item), '');
      // Single line breaks on both sides: a blank line stays between.
      expect(empty('para1\n# H\npara2', 6, 9), 'para1\n\npara2');
      expect(_shape(empty('para1\n# H\npara2', 6, 9)), ['p', 'p']);
      expect(empty('a\n\n# H\n\nb', 3, 6), 'a\n\nb');
      expect(empty('a\n\n# H\nb', 3, 6), 'a\n\nb');
      expect(empty('a\n# H\n\nb', 2, 5), 'a\n\nb');
      // Start and end of the document.
      expect(empty('# H\n\nb', 0, 3), 'b');
      expect(empty('a\n\n# H\n', 3, 6), 'a\n');
      expect(empty('# H', 0, 3), '');
      // A middle list item goes with its line break: one list stays.
      expect(empty('- a\n- b\n- c', 4, 7, item: true), '- a\n- c');
      expect(empty('p\n\n- a\n- b', 3, 6, item: true), 'p\n\n- b');
      // The last item: the blank line before what follows stays.
      expect(empty('- a\n- b\n\npara', 4, 7), '- a\n\npara');
    });

    test('a change maps offsets outside it', () {
      expect(mapThroughChange('abcdef', 'abXYZef', 1), 1);
      expect(mapThroughChange('abcdef', 'abXYZef', 4), 5);
      expect(mapThroughChange('abcdef', 'abXYZef', 2), isNull);
      expect(mapThroughChange('a\n\n\n- [ ] t', 'a\n- [ ] t', 4), 2);
      expect(mapThroughChange('same', 'same', 3), 3);
    });

    test('a fence or HTML block with no closer runs to the end (L′4)', () {
      expect(runsToEnd('```\ncode'), isTrue);
      expect(runsToEnd('```'), isTrue);
      expect(runsToEnd('```\ncode\n```'), isFalse);
      expect(runsToEnd('~~~~\nx\n~~~'), isTrue);
      expect(runsToEnd('<!-- note'), isTrue);
      expect(runsToEnd('<!-- note -->'), isFalse);
      expect(runsToEnd('<pre>\nx'), isTrue);
      expect(runsToEnd('<pre>\nx\n</pre>'), isFalse);
      expect(runsToEnd('para'), isFalse);
      final doc = parseMarkdown('para\n\n```\ncode');
      expect(LiveLayout.of(doc).openTail, LiveLayout.of(doc).units.last);
      expect(LiveLayout.of(parseMarkdown('a\n\n```\nb\n```')).openTail, isNull);
    });
  });

  group('inline looks (L′9)', () {
    List<(String, int)> runs(String line) => [
      for (final r in liveInlineRuns(line))
        (line.substring(r.start, r.end), r.flags),
    ];
    const m = LiveInline.marker;

    test('emphasis, code, math, links: markers faded, the text styled', () {
      expect(runs('a **굵게** b'), [
        ('**', m),
        ('굵게', LiveInline.bold),
        ('**', m),
      ]);
      expect(runs('*기울임* ~~취소~~'), [
        ('*', m),
        ('기울임', LiveInline.italic),
        ('*', m),
        ('~~', m),
        ('취소', LiveInline.strike),
        ('~~', m),
      ]);
      expect(runs('`a*b*` and \$x^2\$'), [
        ('`', m),
        ('a*b*', LiveInline.code),
        ('`', m),
        ('\$', m),
        ('x^2', LiveInline.math),
        ('\$', m),
      ]);
      expect(runs('[계획 문서](https://example.com/plan)'), [
        ('[', m),
        ('계획 문서', LiveInline.link),
        ('](https://example.com/plan)', m),
      ]);
      expect(
        runs('***둘 다***').map((r) => r.$2),
        contains(LiveInline.bold | LiveInline.italic),
      );
    });

    test('no looks for lone markers, escapes, prices, snake_case', () {
      expect(runs('2 * 3 * 4'), isEmpty);
      expect(runs(r'\*literal\*'), isEmpty);
      expect(runs('costs \$5 and \$6'), isEmpty);
      expect(runs('snake_case_name'), isEmpty);
      expect(runs('**unclosed'), isEmpty);
      expect(runs(''), isEmpty);
    });
  });

  group('the editor', () {
    late NoteStore store;
    setUp(() => store = createFakeNoteStore());
    tearDown(() => store.close());

    Future<(MarkdownController, LiveEditor)> open(String raw) async {
      final note = await store.markdown.create(title: 'p', text: raw);
      final c = MarkdownController(
        noteId: note.id,
        repository: store.markdown,
        flushStore: () async {},
        debounce: const Duration(hours: 1),
        maxWait: const Duration(hours: 1),
      );
      for (var i = 0; i < 100 && !c.loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final ed = LiveEditor(c);
      addTearDown(() {
        ed.dispose();
        c.dispose();
      });
      return (c, ed);
    }

    LiveLayout layoutOf(MarkdownController c) =>
        LiveLayout.of(parseMarkdown(c.text.text));

    test('an item that loses its marker by the toolbar or Enter stands apart (L′3)', () async {
      final (c, ed) = await open('- a\n- b\n- c');
      var l = layoutOf(c);
      ed.open(l, l.units[1]);
      ed.apply((v) => toggleLinePrefix(v, LinePrefix.bullet));
      expect(ed.field.text, 'b');
      expect(c.text.text, '- a\n\nb\n\n- c');
      expect(_shape(c.text.text), ['list1', 'p', 'list1']);
      // Marker back: the item is one of the list again, nothing else changed.
      ed.apply((v) => toggleLinePrefix(v, LinePrefix.bullet));
      expect(c.text.text, '- a\n- b\n- c');
      ed.close();
      // Enter on an empty first line of an item.
      c.text.text = '- a\n- \n- c';
      l = layoutOf(c);
      ed.open(l, l.units[1], caret: 2);
      ed.field.value = liveEnter(ed.field.value, LiveKind.prose)!;
      expect(ed.field.text, '');
      ed.field.text = 'x';
      expect(_shape(c.text.text), ['list1', 'p', 'list1']);
    });

    test('emptying blocks keeps the blocks around apart (L′5)', () async {
      final (c, ed) = await open('para1\n# H\npara2');
      var l = layoutOf(c);
      ed.open(l, l.units[1]);
      ed.field.text = '';
      ed.close();
      expect(c.text.text, 'para1\n\npara2');
      // An emptied middle item goes with its line; the list stays one list.
      c.text.text = '- a\n- b\n- c';
      l = layoutOf(c);
      ed.open(l, l.units[1], caret: 0);
      ed.field.text = '';
      ed.close();
      expect(c.text.text, '- a\n- c');
      // … also after its marker went first (the range was widened meanwhile).
      c.text.text = '- a\n- b\n- c';
      l = layoutOf(c);
      ed.open(l, l.units[1], caret: 0);
      expect(ed.backspaceAtStart(), isNull);
      expect(c.text.text, '- a\n\nb\n\n- c');
      ed.field.text = '';
      ed.close();
      expect(c.text.text, '- a\n- c');
    });

    test('a marker line this session added goes at close (UX 7)', () async {
      final (c, ed) = await open('- a\n');
      var l = layoutOf(c);
      ed.open(l, l.units.single);
      ed.field.value = liveEnter(ed.field.value, LiveKind.prose)!;
      expect(c.text.text, '- a\n- \n');
      ed.close();
      expect(c.text.text, '- a\n');
      // One that was there stays.
      c.text.text = '- a\n- ';
      l = layoutOf(c);
      ed.open(l, l.units.first);
      ed.close();
      expect(c.text.text, '- a\n- ');
      // A quote line too.
      c.text.text = '> q';
      l = layoutOf(c);
      ed.open(l, l.units.single);
      ed.field.value = liveEnter(ed.field.value, LiveKind.prose)!;
      expect(ed.field.text, '> q\n> ');
      ed.close();
      expect(c.text.text, '> q');
    });

    test('a paragraph made in the field keeps off a following line (L′1 large documents)', () async {
      final (c, ed) = await open('# Title\nbody text');
      final l = layoutOf(c);
      ed.open(l, l.units.first);
      final old = ed.field.value;
      expect(ed.paragraphInField(old), isNull);
      ed.field.value = liveEnter(old, LiveKind.prose)!;
      ed.field.text = '# Title\n\nnew para';
      expect(c.text.text, '# Title\n\nnew para\n\nbody text');
      expect(_shape(c.text.text), ['h1', 'p', 'p']);
      // A rule followed by text, the same.
      ed.close();
      c.text.text = '---\ntext';
      final l2 = layoutOf(c);
      ed.open(l2, l2.units.first);
      ed.paragraphInField(ed.field.value);
      ed.field.text = '---\n\nx';
      expect(_shape(c.text.text), ['rule', 'p', 'p']);
    });

    test('Enter on a setext title: the paragraph goes after the underline '
        '(L′2)', () async {
      final (c, ed) = await open('Title\n---\n\nbody');
      final l = layoutOf(c);
      expect(l.units.first.setext, isTrue);
      ed.open(l, l.units.first, caret: 5);
      final out = ed.paragraphInField(ed.field.value)!;
      expect(_show(out), 'Title\n---\n\n|');
      ed.field.value = out;
      ed.field.text = 'Title\n---\n\nx';
      expect(_shape(c.text.text), ['h2', 'p', 'p']);
    });

    test('Backspace in an empty new block between blocks: nothing stays '
        '(L′1)', () async {
      final (c, ed) = await open('# T\nbody');
      final l = layoutOf(c);
      expect(ed.openNew(l, pendingAfter(c.text.text, 3)), isTrue);
      expect(ed.backspaceAtStart(), 3);
      expect(ed.isOpen, isFalse);
      expect(c.text.text, '# T\nbody');
      expect(c.dirty, isFalse);
    });
  });
}
