// MD-T21 (08-markdown 24.3, 24.15 D′13): the byte rule of live editing as a property.
// 40 generated documents (BOM, CRLF, lone CR, Korean, emoji, front matter, tables, nested
// and loose lists, tasks, footnotes, link definitions, setext headings) × 200 random
// field edits (typing, deleting, Enter, Backspace at the start, toolbar edits, IME
// composing, closing and opening other blocks). After every step, the decoded buffer
// equals the parsed source with only the open range replaced; opening and closing a
// block without typing changes nothing; the saved bytes are the codec's encoding of the
// buffer (BOM and line endings restored).
import 'dart:async';
import 'dart:math';

import 'package:feature_markdown/src/edit/line_endings.dart';
import 'package:feature_markdown/src/live/live_edit.dart';
import 'package:feature_markdown/src/live/live_editor.dart';
import 'package:feature_markdown/src/live/live_units.dart';
import 'package:feature_markdown/src/parse/md_document.dart';
import 'package:feature_markdown/src/screen/markdown_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

const List<String> _fragments = [
  '# 제목 하나',
  '## Second heading',
  '첫 문단입니다. **굵게** 와 *기울임* 그리고 `code`.',
  'A paragraph\nwith a soft break and an emoji 😀 and 한글.',
  '- 사과\n- 배\n  - 작은 배\n- 감',
  '- [ ] 할 일\n- [x] 끝난 일\n  - [ ] 안쪽 할 일',
  '1. one\n2. two\n   - inner\n3. three',
  '- loose\n\n- list\n\n- items',
  '> 인용 문단\n> 둘째 줄',
  '```dart\nvoid main() {\n  print("hi");\n}\n```',
  '\$\$\nE = mc^2\n\$\$',
  '| a | b |\n| --- | --- |\n| 1 | 2 |',
  'Setext title\n===',
  '---',
  'Footnote ref[^1] here.',
  '[^1]: The note text.',
  '[ref]: https://example.com',
  'See [ref] and [link](https://x.y).',
  '<!-- html comment -->',
  '    indented code',
  '- a\n* b',
  '- [ ] same\n- [ ] same',
  '---',
  '# 제목 하나',
];

String _doc(Random r) {
  final parts = <String>[];
  if (r.nextInt(5) == 0) parts.add('---\ntitle: 문서\n---');
  final n = 3 + r.nextInt(9);
  for (var i = 0; i < n; i++) {
    parts.add(_fragments[r.nextInt(_fragments.length)]);
  }
  final seps = ['\n\n', '\n\n', '\n\n\n', '\n'];
  final b = StringBuffer(parts.first);
  for (final p in parts.skip(1)) {
    b
      ..write(seps[r.nextInt(seps.length)])
      ..write(p);
  }
  if (r.nextBool()) b.write('\n');
  var text = b.toString();
  switch (r.nextInt(4)) {
    case 0:
      text = text.replaceAll('\n', '\r\n');
    case 1:
      text = '﻿$text';
    case 2:
      text = '﻿${text.replaceAll('\n', '\r\n')}';
  }
  return text;
}

const List<String> _typed = ['a', '한', ' ', '😀', '**', '- ', '\n', 'xyz', '#'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoteStore store;
  setUp(() => store = createFakeNoteStore());
  tearDown(() => store.close());

  Future<MarkdownController> open(String raw) async {
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
    expect(c.loaded, isTrue);
    return c;
  }

  test(
    '40 documents × 200 random live edits: only the open range changes',
    () async {
      final r = Random(24);
      var steps = 0;
      var opened = 0;
      for (var d = 0; d < 40; d++) {
        final raw = _doc(r);
        final c = await open(raw);
        final codec = LineEndingCodec.of(raw);
        expect(c.text.text, codec.decode(raw));
        final ed = LiveEditor(c);
        void check(String why) {
          final s = ed.session;
          if (s == null) return;
          final buf = c.text.text;
          final head = s.base.substring(0, s.range.start);
          final tail = s.base.substring(s.range.end);
          expect(
            buf.startsWith(head),
            isTrue,
            reason: '$why: head changed (doc $d)',
          );
          expect(
            buf.endsWith(tail),
            isTrue,
            reason: '$why: tail changed (doc $d)',
          );
          expect(
            buf.length,
            head.length +
                s.range.replacement(ed.field.text).length +
                tail.length,
            reason: why,
          );
          final off = s.range.fieldOffset(ed.field.text);
          expect(
            buf.substring(off, off + ed.field.text.length),
            ed.field.text,
            reason: '$why: the field is not where it should be',
          );
        }

        for (var step = 0; step < 200; step++) {
          steps++;
          if (!ed.isOpen) {
            final layout = LiveLayout.of(parseMarkdown(c.text.text));
            final before = c.text.text;
            if (layout.units.isEmpty || r.nextInt(6) == 0) {
              expect(ed.openAtEnd(layout), isTrue);
            } else {
              final u = layout.units[r.nextInt(layout.units.length)];
              if (!ed.open(layout, u, caret: r.nextInt(u.end - u.start + 1))) {
                continue;
              }
              expect(ed.field.text, before.substring(u.start, u.end));
            }
            opened++;
            expect(c.text.text, before, reason: 'opening changed the buffer');
            continue;
          }
          final v = ed.field.value;
          final len = v.text.length;
          final s = ed.session!;
          switch (r.nextInt(10)) {
            case 0 || 1 || 2:
              final at = r.nextInt(len + 1);
              final t = _typed[r.nextInt(_typed.length)];
              final next = TextEditingValue(
                text: v.text.replaceRange(at, at, t),
                selection: TextSelection.collapsed(offset: at + t.length),
              );
              ed.field.value = t == '\n'
                  ? (liveEnter(
                          v.copyWith(
                            selection: TextSelection.collapsed(offset: at),
                          ),
                          s.kind,
                        ) ??
                        next)
                  : next;
            case 3:
              if (len > 0) {
                final a = r.nextInt(len);
                final b = a + 1 + r.nextInt(min(4, len - a));
                ed.field.value = TextEditingValue(
                  text: v.text.replaceRange(a, b, ''),
                  selection: TextSelection.collapsed(offset: a),
                );
              }
            case 4:
              // Korean IME: a syllable composing, then committed.
              final at = r.nextInt(len + 1);
              ed.field.value = TextEditingValue(
                text: v.text.replaceRange(at, at, 'ㅎ'),
                selection: TextSelection.collapsed(offset: at + 1),
                composing: TextRange(start: at, end: at + 1),
              );
              check('composing');
              expect(c.text.value.composing.isValid, isTrue);
              ed.field.value = TextEditingValue(
                text: v.text.replaceRange(at, at, '한'),
                selection: TextSelection.collapsed(offset: at + 1),
              );
            case 5:
              ed.field.selection = const TextSelection.collapsed(offset: 0);
              final to = ed.backspaceAtStart();
              if (to != null) expect(ed.isOpen, isFalse);
            case 6:
              ed.apply(
                (x) => switch (r.nextInt(5)) {
                  0 => toggleWrap(x, '**'),
                  1 => toggleLinePrefix(x, LinePrefix.values[r.nextInt(7)]),
                  2 => insertTemplate(x, LiveTemplate.values[r.nextInt(4)]),
                  3 => indentField(x, indent: r.nextBool()),
                  _ => insertLink(x),
                },
              );
            case 7:
              ed.shiftEnter();
            default:
              ed.close();
              expect(c.liveHold, isFalse);
          }
          check('step $step');
        }
        ed.close();
        // Saved bytes = the codec's encoding of the buffer.
        expect(await c.flush(), isTrue);
        final stored = (await store.markdown.get(c.noteId))!.text;
        expect(stored, c.dirty ? isNot(anything) : c.codec.encode(c.text.text));
        expect(stored.startsWith('﻿'), raw.startsWith('﻿'));
        expect(ed.aborts, 0);
        ed.dispose();
        c.dispose();
      }
      expect(steps, 8000);
      expect(opened, greaterThan(400));
    },
  );

  test(
    'open and close without typing: nothing saved, bytes the same',
    () async {
      final r = Random(7);
      for (var d = 0; d < 10; d++) {
        final raw = _doc(r);
        final c = await open(raw);
        final ed = LiveEditor(c);
        final layout = LiveLayout.of(parseMarkdown(c.text.text));
        for (final u in layout.units) {
          expect(ed.open(layout, u), isTrue);
          ed.close();
        }
        expect(ed.openAtEnd(layout), isTrue);
        ed.close();
        expect(c.dirty, isFalse);
        expect(c.encoded, raw);
        ed.dispose();
        c.dispose();
      }
    },
  );

  test(
    'a write is refused when the buffer changed under the block (D′1, D′3)',
    () async {
      final c = await open('a\n\nb');
      final ed = LiveEditor(c);
      final layout = LiveLayout.of(parseMarkdown(c.text.text));
      ed.open(layout, layout.units.last);
      c.text.text = 'other text';
      ed.field.text = 'b!';
      expect(ed.aborts, 1);
      expect(ed.isOpen, isFalse);
      expect(c.text.text, 'other text');
      ed.dispose();
      c.dispose();
    },
  );

  test('another device\'s text is held while a block is open (D′1)', () async {
    final c = await open('a\n\nb');
    final ed = LiveEditor(c);
    final layout = LiveLayout.of(parseMarkdown(c.text.text));
    ed.open(layout, layout.units.last);
    ed.field.text = 'b2';
    expect(await c.flush(), isTrue);
    expect(c.dirty, isFalse);
    // Another device writes on the saved version.
    final now = (await store.markdown.get(c.noteId))!;
    await store.markdown.saveText(
      c.noteId,
      'remote',
      baseVersion: now.textVersion,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.text.text, 'a\n\nb2', reason: 'not applied under the open block');
    ed.field.text = 'b23';
    expect(c.text.text, 'a\n\nb23');
    expect(ed.aborts, 0);
    ed.close();
    expect(await c.flush(), isTrue);
    // Our text was saved on the older base: the store kept 'remote' as a copy.
    expect(c.conflictCopyId, isNotNull);
    expect((await store.markdown.get(c.noteId))!.text, 'a\n\nb23');
    ed.dispose();
    c.dispose();
  });

  test('held text is taken when the block closes clean (D′1)', () async {
    final c = await open('a\n\nb');
    final ed = LiveEditor(c);
    final layout = LiveLayout.of(parseMarkdown(c.text.text));
    ed.open(layout, layout.units.first);
    final now = (await store.markdown.get(c.noteId))!;
    await store.markdown.saveText(
      c.noteId,
      'remote',
      baseVersion: now.textVersion,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.text.text, 'a\n\nb');
    ed.close();
    expect(c.text.text, 'remote');
    ed.dispose();
    c.dispose();
  });

  test('undo groups end at open and close (D′10)', () async {
    final c = await open('a\n\nb');
    final ed = LiveEditor(c);
    var layout = LiveLayout.of(parseMarkdown(c.text.text));
    ed.open(layout, layout.units.first);
    ed.field.text = 'a1';
    ed.close();
    layout = LiveLayout.of(parseMarkdown(c.text.text));
    ed.open(layout, layout.units.last);
    ed.field.text = 'b1';
    ed.close();
    c.undoStep();
    expect(c.text.text, 'a1\n\nb');
    c.undoStep();
    expect(c.text.text, 'a\n\nb');
    ed.dispose();
    c.dispose();
  });

  test(
    'Backspace on a list item: marker, then the list splits, then joins (U′3)',
    () async {
      final c = await open('- a\n- b\n- c');
      final ed = LiveEditor(c);
      final layout = LiveLayout.of(parseMarkdown(c.text.text));
      ed.open(layout, layout.units[1], caret: 0);
      expect(ed.backspaceAtStart(), isNull);
      expect(c.text.text, '- a\n\nb\n\n- c');
      ed.close();
      final doc = parseMarkdown(c.text.text);
      expect(doc.blocks.length, 3);
      final l2 = LiveLayout.of(doc);
      ed.open(l2, l2.units[1], caret: 0);
      expect(ed.backspaceAtStart(), isNull);
      expect(c.text.text, '- ab\n\n- c');
      expect(ed.field.text, '- ab');
      expect(ed.field.selection.extentOffset, 3);
      ed.dispose();
      c.dispose();
    },
  );

  test(
    'an emptied block takes its blank lines along; a code block is not joined',
    () async {
      final c = await open('para\n\n```\nx\n```\n\nlast\n');
      final ed = LiveEditor(c);
      final layout = LiveLayout.of(parseMarkdown(c.text.text));
      ed.open(layout, layout.units.last);
      ed.field.text = '';
      expect(c.text.text, 'para\n\n```\nx\n```\n\n\n');
      ed.field.selection = const TextSelection.collapsed(offset: 0);
      final to = ed.backspaceAtStart();
      expect(to, isNotNull);
      expect(c.text.text, 'para\n\n```\nx\n```\n');
      ed.dispose();
      c.dispose();
    },
  );

  test('joining a paragraph into a heading keeps the rest', () async {
    final c = await open('# T\n\nbody\n\nend');
    final ed = LiveEditor(c);
    final layout = LiveLayout.of(parseMarkdown(c.text.text));
    ed.open(layout, layout.units[1], caret: 0);
    expect(ed.backspaceAtStart(), isNull);
    expect(c.text.text, '# Tbody\n\nend');
    unawaited(Future<void>.value());
    ed.dispose();
    c.dispose();
  });
}
