// B-1 / B-2 / B-5 / B-7 (08-markdown 4.7, 8.2, 8.3, 8.5): block cutting, the parser setup
// (GFM, math, raw HTML allow-list, footnotes, references across blocks), block keys,
// image classification and the task-box source scan.
import 'dart:convert';

import 'package:feature_markdown/src/parse/block_splitter.dart';
import 'package:feature_markdown/src/parse/md_document.dart';
import 'package:feature_markdown/src/parse/md_model.dart';
import 'package:feature_markdown/src/parse/task_marks.dart';
import 'package:flutter_test/flutter_test.dart';

List<MdNode> _nodes(String text) => [
  for (final b in parseMarkdown(text).blocks) ...b.nodes,
];

MdNode _one(String text) {
  final nodes = _nodes(text);
  expect(nodes, hasLength(1), reason: '$nodes');
  return nodes.single;
}

List<MdInline> _inl(String text) => (_one(text) as MdParagraph).inlines;

List<String> _sources(String text) => [
  for (final b in splitBlocks(text)) text.substring(b.start, b.end),
];

void main() {
  group('block splitter', () {
    test(
      'blank lines cut paragraphs; headings and fences cut without blanks',
      () {
        expect(_sources('a\nb\n\nc\n# H\nd\n```\nx\n\ny\n```\ne'), [
          'a\nb',
          'c',
          '# H',
          'd',
          '```\nx\n\ny\n```',
          'e',
        ]);
      },
    );

    test('a loose list with blank lines and nested items stays one block', () {
      const src = '- a\n\n- b\n  - c\n\n    more\n\n1. x\n\npara';
      expect(_sources(src), ['- a\n\n- b\n  - c\n\n    more\n\n1. x', 'para']);
    });

    test(r'$$ math blocks keep blank lines; one-line $$ is one block', () {
      expect(_sources('\$\$\na\n\nb\n\$\$\n\n\$\$ x \$\$\ntext'), [
        '\$\$\na\n\nb\n\$\$',
        '\$\$ x \$\$',
        'text',
      ]);
    });

    test('front matter only at the very top', () {
      final blocks = splitBlocks('---\ntitle: 가\n---\n# 제목');
      expect(blocks.first.kind, SourceBlockKind.frontMatter);
      expect(blocks, hasLength(2));
      expect(
        splitBlocks('# a\n\n---\nx: 1\n---').first.kind,
        SourceBlockKind.heading,
      );
    });

    test('ranges point into the text', () {
      const src = 'one\n\n  two\nthree\n\n> q';
      for (final b in splitBlocks(src)) {
        expect(src.substring(b.start, b.end).trim(), isNotEmpty);
      }
      expect(splitBlocks(src).last.start, src.indexOf('> q'));
    });
  });

  group('parser', () {
    test('headings, emphasis, strikethrough, line height content', () {
      final doc = parseMarkdown('# 제목 하나\n\n**굵게** *기울임* ~~취소~~');
      final h = doc.blocks.first.nodes.single as MdHeading;
      expect(h.level, 1);
      expect(h.slug, '제목-하나');
      expect(doc.slugs['제목-하나'], 0);
      final p = doc.blocks[1].nodes.single as MdParagraph;
      expect(p.inlines.whereType<MdStyled>().map((s) => s.mark), [
        MdMark.strong,
        MdMark.em,
        MdMark.del,
      ]);
    });

    test('GFM table with alignment and missing cells', () {
      final t = _one(
        '| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 |\n| x | y | z |',
      ) as MdTable;
      expect(t.aligns, [MdAlign.left, MdAlign.center, MdAlign.right]);
      expect(t.header, hasLength(3));
      expect(t.rows, hasLength(2));
      expect(t.rows.first, hasLength(3));
      expect(t.index, 0);
    });

    test('task lists: tight and loose, nested, ordered start kept', () {
      final doc = parseMarkdown(
        '- [ ] 하나\n- [x] 둘\n  - [X] 셋\n\n3. [ ] 넷\n4. 다섯',
      );
      // a list right after a list stays in the same source block
      final lists = doc.blocks.single.nodes.cast<MdList>();
      final list = lists.first;
      expect(list.items.first.task!.checked, isFalse);
      expect(list.items[1].task!.checked, isTrue);
      final nested = list.items[1].children.whereType<MdList>().single;
      expect(nested.items.single.task!.checked, isTrue);
      final ordered = lists.last;
      expect(ordered.ordered, isTrue);
      expect(ordered.start, 3);
      expect(doc.taskCount, 4);
      // the box offsets point at the character inside the brackets
      for (final o in doc.taskOffsets) {
        expect(o, isNotNull);
        expect(doc.source[o!], anyOf(' ', 'x', 'X'));
        expect(doc.source[o - 1], '[');
      }
    });

    test('footnotes resolve across blocks and list at the end', () {
      final doc = parseMarkdown('본문[^a] 그리고[^b].\n\n[^b]: 둘째\n\n[^a]: 첫째');
      final refs = (doc.blocks.first.nodes.single as MdParagraph).inlines
          .whereType<MdFootnoteRef>()
          .toList();
      expect(refs.map((r) => r.number), [1, 2]);
      expect(doc.footnotes.map((f) => f.label), ['a', 'b']);
      expect(doc.blocks[1].nodes, isEmpty);
    });

    test('reference links defined further down resolve', () {
      final inl = parseMarkdown('[문서][d]\n\n[d]: https://example.com/x')
          .blocks
          .first
          .nodes
          .single;
      final link = (inl as MdParagraph).inlines.single as MdLink;
      expect(link.href, 'https://example.com/x');
    });

    test(r'inline math: pandoc rules, $ in code, $5 and $6, escapes', () {
      final a = _inl(r'식 $x^2$ 끝');
      expect(a.whereType<MdMath>().single.tex, 'x^2');
      expect(_inl(r'가격 $5 and $6 이에요').whereType<MdMath>(), isEmpty);
      expect(_inl(r'$ x$').whereType<MdMath>(), isEmpty);
      expect(_inl(r'$x $').whereType<MdMath>(), isEmpty);
      expect(_inl(r'$x$5').whereType<MdMath>(), isEmpty);
      final esc = _inl(r'\$x$ 와 \$');
      expect(esc.whereType<MdMath>(), isEmpty);
      expect((esc.single as MdText).text, r'$x$ 와 $');
      final code = _inl(r'`$x$` 코드');
      expect(code.first, isA<MdCodeSpan>());
      expect((code.first as MdCodeSpan).code, r'$x$');
      expect(_inl(r'\(a+b\) 괄호').first, isA<MdMath>());
      final display = _inl(r'앞 $$\int f$$ 뒤').whereType<MdMath>().single;
      expect(display.display, isTrue);
    });

    test(
      r'block math: $$ pair, one line, \[ \], math fence; code fence keeps $',
      () {
        final doc = parseMarkdown(
          '\$\$\n\\frac{a}{b}\n\$\$\n\n\$\$ x+y \$\$\n\n\\[\nz\n\\]\n\n'
          '```math\nE=mc^2\n```\n\n```dart\nfinal s = r"\$x\$";\n```',
        );
        final maths = [
          for (final b in doc.blocks) ...b.nodes.whereType<MdMathBlock>(),
        ];
        expect(maths.map((m) => m.tex), [r'\frac{a}{b}', 'x+y', 'z', 'E=mc^2']);
        expect(maths.map((m) => m.index), [0, 1, 2, 3]);
        final code = doc.blocks.last.nodes.single as MdCodeBlock;
        expect(code.language, 'dart');
        expect(code.code, r'final s = r"$x$";');
        expect(code.index, 0);
      },
    );

    test('raw HTML: allow-list marks, br, img rules, scripts dropped', () {
      final inl = _inl('a<br>b <b>굵게</b> <span>안</span> <script>x</script>끝');
      expect(inl.whereType<MdBreak>(), hasLength(1));
      expect(inl.whereType<MdStyled>().single.mark, MdMark.strong);
      final text = plainOfInlines(inl);
      expect(text, isNot(contains('<')));
      expect(text, contains('안'));
      expect(text, isNot(contains('x끝')));
      final block = _one(
        '<div align="center">\n<p>가 &amp; 나</p>\n<img src="https://h.example/a.png" alt="그림">\n</div>',
      ) as MdParagraph;
      expect(plainOfInlines(block.inlines), contains('가 & 나'));
      expect(
        block.inlines.whereType<MdImage>().single.source,
        MdImageSource.remote,
      );
    });

    test('images: remote, relative, data (decoded once), too large', () {
      final png = base64Encode(List<int>.filled(30, 7));
      final doc = parseMarkdown(
        '![원격](https://img.example.com/a.png) ![상대](img/a.png) '
        '![데이터](data:image/png;base64,$png) ![svg](data:image/svg+xml;base64,AAAA)',
      );
      final images = (doc.blocks.single.nodes.single as MdParagraph).inlines
          .whereType<MdImage>()
          .toList();
      expect(images.map((i) => i.source), [
        MdImageSource.remote,
        MdImageSource.relative,
        MdImageSource.data,
        MdImageSource.unsupported,
      ]);
      expect(images.first.host, 'img.example.com');
      expect(images[2].bytes, hasLength(30));
      expect(images.map((i) => i.index), [0, 1, 2, 3]);
      final big = base64Encode(List<int>.filled(kMaxDataImageBytes + 3, 1));
      final tooBig =
          (_one(
                '![x](data:image/png;base64,$big)',
              ) as MdParagraph).inlines.single
              as MdImage;
      expect(tooBig.source, MdImageSource.unsupported);
      expect(tooBig.bytes, isNull);
    });

    test('links are numbered in document order, autolinks too', () {
      final doc = parseMarkdown(
        '[a](#x) https://example.com\n\n[b](mailto:a@b.c)',
      );
      final links = [
        for (final b in doc.blocks)
          for (final n in b.nodes)
            ...(n as MdParagraph).inlines.whereType<MdLink>(),
      ];
      expect(links.map((l) => l.index), [0, 1, 2]);
      expect(links[1].href, 'https://example.com');
      expect(doc.linkCount, 3);
    });

    test('front matter becomes an info box, not a rule and a heading', () {
      final doc = parseMarkdown('---\ntitle: 문서\ntags: [a]\n---\n\n본문');
      expect(doc.blocks.first.nodes.single, isA<MdFrontMatter>());
      expect(
        (doc.blocks.first.nodes.single as MdFrontMatter).raw,
        'title: 문서\ntags: [a]',
      );
      expect(doc.blocks[1].nodes.single, isA<MdParagraph>());
    });

    test('quotes, rules, nested lists keep their structure', () {
      final q = _one('> 인용\n> - 목록\n>   - 안쪽') as MdQuote;
      expect(q.children.last, isA<MdList>());
      expect(_one('***'), isA<MdRule>());
    });

    test('blockAt finds the block of an offset', () {
      const src = 'a\n\nbb\n\nccc';
      final doc = parseMarkdown(src);
      expect(doc.blockAt(0), 0);
      expect(doc.blockAt(src.indexOf('bb') + 1), 1);
      expect(doc.blockAt(src.length), 2);
      expect(doc.blockAt(2), 1); // in the blank gap → next block
    });
  });

  group('block keys', () {
    test('editing above a block keeps its key; equal blocks get ordinals', () {
      const below = '\n\n## 아래\n\n같은 문단\n\n같은 문단';
      final a = parseMarkdown('첫 문단$below');
      final b = parseMarkdown('첫 문단을 고쳤어요\n\n새 문단$below');
      List<String> tail(MdDocument d) =>
          d.blocks.skip(d.blocks.length - 3).map((x) => x.key).toList();
      expect(tail(a), tail(b));
      expect(a.blocks.first.key, isNot(b.blocks.first.key));
      final keys = tail(a);
      expect(keys[1].split('-').first, keys[2].split('-').first);
      expect(keys[1].endsWith('-0'), isTrue);
      expect(keys[2].endsWith('-1'), isTrue);
      expect(keys.first, matches(RegExp(r'^[0-9a-f]{8}-\d+$')));
    });
  });

  group('TaskMarks.scan', () {
    test('skips fences, indented code and HTML blocks; allows > prefixes', () {
      const src =
          '- [ ] a\n```\n- [ ] in fence\n```\n\n    - [ ] indented code\n\n'
          '<div>\n- [ ] html\n</div>\n\n> - [x] quoted\n1. [X] num';
      final marks = TaskMarks.scan(src);
      expect(marks.map((o) => src[o]), [' ', 'x', 'X']);
      expect(parseMarkdown(src).taskCount, 3);
      expect(parseMarkdown(src).taskOffsets, marks);
    });

    test('a count mismatch makes that block display-only', () {
      // '[ ]' with no text after it is not a task box for the parser.
      final doc = parseMarkdown('- [ ] a\n\n- [ ]\n- [x] b\n\n- [ ] c');
      expect(doc.taskOffsets.whereType<int>().length, doc.taskCount);
    });
  });

  test('async parse gives the same document for big texts', () async {
    final big = List.filled(3000, '- [ ] 항목 \$x\$ 와 **굵게**\n').join();
    expect(big.length, greaterThan(kParseOffThreadChars));
    final a = await parseMarkdownAsync(big);
    final b = parseMarkdown(big);
    expect(a.blocks.length, b.blocks.length);
    expect(a.taskOffsets, b.taskOffsets);
  });
}
