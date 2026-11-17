// Parsing an MD 문서 (08-markdown 8.2, B-1..B-7): cut into top-level blocks
// (block_splitter.dart), each block parsed by dart-lang's markdown parser (GFM + math,
// raw HTML tagged), all blocks sharing ONE markdown Document — the block phase of every
// block runs first, so reference links and footnotes defined further down resolve — then
// converted to the plain data of md_model.dart. Documents over 50 KB are parsed on another
// isolate (`compute`; on the web on the same thread).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

import 'block_keys.dart';
import 'block_splitter.dart';
import 'html_lite.dart';
import 'math_syntax.dart';
import 'md_model.dart';
import 'task_marks.dart';

/// Above this many UTF-16 units the parse runs on another isolate.
const int kParseOffThreadChars = 50 * 1024;

/// Largest decoded `data:` image drawn (2 MB).
const int kMaxDataImageBytes = 2 * 1024 * 1024;

/// [parseMarkdown], on another isolate when [text] is large (not on the web).
Future<MdDocument> parseMarkdownAsync(String text) async {
  if (kIsWeb || text.length <= kParseOffThreadChars) return parseMarkdown(text);
  return compute(parseMarkdown, text, debugLabel: 'markdown parse');
}

/// The first screenful of a large document parsed alone (whole blocks, about [chars]
/// characters): shown at once while the whole document is parsed off the main isolate.
/// References defined further down resolve only in the full parse. null when [text] is
/// small enough to parse whole right away.
MdDocument? parseMarkdownHead(String text, {int chars = 6000}) {
  if (text.length <= kParseOffThreadChars) return null;
  final blocks = splitBlocks(text);
  var end = 0;
  for (final b in blocks) {
    end = b.end;
    if (end >= chars) break;
  }
  if (end > 4 * chars) {
    // One huge first block: a preview of its first lines is enough for a moment.
    final cut = text.lastIndexOf('\n', 4 * chars);
    end = cut > 0 ? cut : 4 * chars;
  }
  return parseMarkdown(text.substring(0, end));
}

/// Parses run on this isolate so far (tests: typing in 편집 never parses).
@visibleForTesting
int debugParseCount = 0;

/// The parsed form of the decoded [text] (no BOM, LF line endings).
MdDocument parseMarkdown(String text) {
  debugParseCount++;
  final sources = splitBlocks(text);
  final doc = md.Document(
    extensionSet: markdownExtensions(),
    encodeHtml: false,
  );
  // Phase 1: the block structure of every block (registers link references and
  // footnote definitions in `doc`).
  final parsed = <List<md.Node>>[];
  for (final b in sources) {
    if (b.kind == SourceBlockKind.frontMatter) {
      parsed.add(const []);
      continue;
    }
    final lines = text.substring(b.start, b.end).split('\n');
    parsed.add(
      md.BlockParser(lines.map(md.Line.new).toList(), doc).parseLines(),
    );
  }
  // Phase 2: inline content (Document._parseInlineContent, which is private).
  for (final nodes in parsed) {
    _parseInlines(doc, nodes);
  }
  // Phase 3: our model.
  final c = _Converter(doc);
  final blocks = <MdBlock>[];
  final taskOffsets = <int?>[];
  final keys = blockKeysOf([
    for (final b in sources) text.substring(b.start, b.end),
  ]);
  for (var i = 0; i < sources.length; i++) {
    final b = sources[i];
    final tasksBefore = c.tasks;
    final List<MdNode> nodes;
    if (b.kind == SourceBlockKind.frontMatter) {
      final lines = text.substring(b.start, b.end).split('\n');
      nodes = [MdFrontMatter(lines.sublist(1, lines.length - 1).join('\n'))];
    } else {
      nodes = c.blocks(parsed[i], topLevel: true, blockIndex: blocks.length);
    }
    final count = c.tasks - tasksBefore;
    if (count > 0) {
      final marks = TaskMarks.scan(text, start: b.start, end: b.end);
      if (marks.length == count &&
          TaskMarks.matches(
            text,
            marks,
            c.taskInfo.sublist(tasksBefore, tasksBefore + count),
          )) {
        taskOffsets.addAll(marks);
      } else {
        taskOffsets.addAll(List<int?>.filled(count, null));
        debugPrint(
          'feature_markdown: block $i has $count task boxes but the source scan '
          'found ${marks.length} (or other ones); its boxes are display-only',
        );
      }
    }
    blocks.add(
      MdBlock(
        key: keys[i],
        start: b.start,
        end: b.end,
        nodes: nodes,
        plainText: _plainOfNodes(nodes),
      ),
    );
  }
  return MdDocument(
    source: text,
    blocks: blocks,
    footnotes: c.footnotes(),
    slugs: c.slugs,
    taskOffsets: taskOffsets,
    taskCount: c.tasks,
    linkCount: c.links,
    codeCount: c.codes,
    tableCount: c.tables,
    mathCount: c.maths,
    imageCount: c.images,
  );
}

void _parseInlines(md.Document doc, List<md.Node> nodes) {
  for (var i = 0; i < nodes.length; i++) {
    final node = nodes[i];
    if (node is md.UnparsedContent) {
      final inline = doc.parseInline(node.textContent);
      nodes
        ..removeAt(i)
        ..insertAll(i, inline);
      i += inline.length - 1;
    } else if (node is md.Element && node.children != null) {
      _parseInlines(doc, node.children!);
    }
  }
}

const Set<String> _blockTags = {
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'blockquote',
  'ul',
  'ol',
  'li',
  'table',
  'hr',
  'section',
  MdTags.blockMath,
  MdTags.blockHtml,
};

bool _isBlock(md.Node n) => n is md.Element && _blockTags.contains(n.tag);

/// Inline content being built, with the open HTML marks.
final class _Inlines {
  final List<(MdMark?, List<MdInline>)> _frames = [(null, <MdInline>[])];

  /// Inside `<script>` / `<style>` / `<iframe>`.
  int dropping = 0;

  void add(MdInline x) {
    if (dropping > 0) return;
    final list = _frames.last.$2;
    if (x is MdText) {
      if (x.text.isEmpty) return;
      if (list.isNotEmpty && list.last is MdText) {
        list.last = MdText((list.last as MdText).text + x.text);
        return;
      }
    }
    list.add(x);
  }

  void open(MdMark mark) => _frames.add((mark, <MdInline>[]));

  void close(MdMark mark) {
    final at = _frames.lastIndexWhere((f) => f.$1 == mark);
    if (at <= 0) return;
    while (_frames.length > at) {
      _pop();
    }
  }

  void _pop() {
    final f = _frames.removeLast();
    if (f.$2.isNotEmpty) _frames.last.$2.add(MdStyled(f.$1!, f.$2));
  }

  List<MdInline> finish() {
    while (_frames.length > 1) {
      _pop();
    }
    return _frames.first.$2;
  }
}

final class _Converter {
  _Converter(this.doc);

  final md.Document doc;
  int tasks = 0;

  /// Per task box in document order: checked, and the plain text of its item's first
  /// paragraph (to check the source scan found the same boxes).
  final List<({bool checked, String text})> taskInfo = [];
  int links = 0;
  int codes = 0;
  int tables = 0;
  int maths = 0;
  int images = 0;
  final Map<String, int> slugs = {};
  final Map<String, int> _slugCounts = {};
  final Map<String, List<MdNode>> _footnoteDefs = {};
  int _blockIndex = 0;

  List<MdFootnote> footnotes() {
    final out = <MdFootnote>[];
    for (final e in _footnoteDefs.entries) {
      if ((doc.footnoteReferences[e.key] ?? 0) <= 0) continue;
      final n = doc.footnoteLabels.indexOf(e.key);
      if (n < 0) continue;
      out.add(MdFootnote(label: e.key, number: n + 1, children: e.value));
    }
    out.sort((a, b) => a.number - b.number);
    return out;
  }

  List<MdNode> blocks(
    List<md.Node> nodes, {
    bool topLevel = false,
    int blockIndex = 0,
  }) {
    if (topLevel) _blockIndex = blockIndex;
    final out = <MdNode>[];
    var pending = <md.Node>[];
    void flushInline() {
      if (pending.isEmpty) return;
      final inl = inlines(pending);
      pending = [];
      if (_plain(inl).trim().isNotEmpty || inl.any((x) => x is! MdText)) {
        out.add(MdParagraph(_trimEnds(inl)));
      }
    }

    for (final n in nodes) {
      if (!_isBlock(n)) {
        pending.add(n);
        continue;
      }
      flushInline();
      final e = n as md.Element;
      if (topLevel && e.tag == 'li' && e.footnoteLabel != null) {
        _footnoteDefs[e.footnoteLabel!] = blocks(e.children ?? const []);
        continue;
      }
      final b = block(e);
      if (b != null) out.add(b);
    }
    flushInline();
    return out;
  }

  MdNode? block(md.Element e) {
    switch (e.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final inl = inlines(e.children ?? const []);
        return MdHeading(
          level: int.parse(e.tag.substring(1)),
          inlines: inl,
          slug: _slug(_plain(inl)),
        );
      case 'p':
        final inl = _trimEnds(inlines(e.children ?? const []));
        return inl.isEmpty ? null : MdParagraph(inl);
      case 'pre':
        final code = e.children?.whereType<md.Element>().firstOrNull;
        final cls = code?.attributes['class'] ?? '';
        final language = cls.startsWith('language-')
            ? cls.substring('language-'.length)
            : null;
        var text = e.textContent;
        if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
        if (language == 'math') {
          return MdMathBlock(tex: text.trim(), index: maths++);
        }
        return MdCodeBlock(
          code: text,
          language: (language == null || language.isEmpty) ? null : language,
          index: codes++,
        );
      case 'blockquote':
        return MdQuote(blocks(e.children ?? const []));
      case 'ul' || 'ol':
        final items = <MdListItem>[];
        for (final li in e.children ?? const <md.Node>[]) {
          if (li is md.Element && li.tag == 'li') items.add(_item(li));
        }
        return MdList(
          ordered: e.tag == 'ol',
          start: int.tryParse(e.attributes['start'] ?? '') ?? 1,
          items: items,
        );
      case 'table':
        return _table(e);
      case 'hr':
        return const MdRule();
      case MdTags.blockMath:
        return MdMathBlock(tex: e.textContent, index: maths++);
      case MdTags.blockHtml:
        final inl = _htmlBlock(e.textContent);
        return inl.isEmpty ? null : MdParagraph(inl);
      default:
        final inner = blocks(e.children ?? const []);
        return inner.isEmpty
            ? null
            : inner.length == 1
            ? inner.first
            : MdQuote(inner);
    }
  }

  MdListItem _item(md.Element li) {
    MdTask? task;
    var children = List<md.Node>.of(li.children ?? const <md.Node>[]);
    bool takeBox(List<md.Node> list) {
      if (list.isNotEmpty &&
          list.first is md.Element &&
          (list.first as md.Element).tag == 'input') {
        final box = list.removeAt(0) as md.Element;
        final checked = box.attributes.containsKey('checked');
        task = MdTask(checked: checked, index: tasks++);
        // Its slot now (nested items convert first); the text is filled in below.
        taskInfo.add((checked: checked, text: ''));
        return true;
      }
      return false;
    }

    if (li.attributes['class'] == 'task-list-item') {
      if (!takeBox(children) &&
          children.isNotEmpty &&
          children.first is md.Element) {
        final first = children.first as md.Element;
        final inner = List<md.Node>.of(first.children ?? const <md.Node>[]);
        if (takeBox(inner)) {
          final copy = md.Element(first.tag, inner)
            ..attributes.addAll(first.attributes);
          children = [copy, ...children.skip(1)];
        }
      }
    }
    final converted = blocks(children);
    final t = task;
    if (t != null) {
      taskInfo[t.index] = (
        checked: t.checked,
        text: converted.isNotEmpty && converted.first is MdParagraph
            ? _plain((converted.first as MdParagraph).inlines)
            : '',
      );
    }
    return MdListItem(children: converted, task: task);
  }

  MdTable _table(md.Element e) {
    final header = <List<MdInline>>[];
    final aligns = <MdAlign>[];
    final rows = <List<List<MdInline>>>[];
    for (final part in e.children ?? const <md.Node>[]) {
      if (part is! md.Element) continue;
      for (final tr in part.children ?? const <md.Node>[]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final cells = <List<MdInline>>[];
        for (final cell in tr.children ?? const <md.Node>[]) {
          if (cell is! md.Element) continue;
          cells.add(_trimEnds(inlines(cell.children ?? const [])));
          if (part.tag == 'thead') {
            aligns.add(switch (cell.attributes['align']) {
              'left' => MdAlign.left,
              'center' => MdAlign.center,
              'right' => MdAlign.right,
              _ => MdAlign.none,
            });
          }
        }
        if (part.tag == 'thead') {
          header.addAll(cells);
        } else {
          while (cells.length < header.length) {
            cells.add(const []);
          }
          rows.add(cells);
        }
      }
    }
    return MdTable(aligns: aligns, header: header, rows: rows, index: tables++);
  }

  // --- inline ---------------------------------------------------------------------

  List<MdInline> inlines(List<md.Node> nodes) {
    final out = _Inlines();
    _inline(nodes, out);
    return out.finish();
  }

  void _inline(List<md.Node> nodes, _Inlines out) {
    for (final n in nodes) {
      if (n is md.Text) {
        out.add(MdText(n.text));
        continue;
      }
      if (n is! md.Element) continue;
      switch (n.tag) {
        case 'strong':
          _marked(MdMark.strong, n, out);
        case 'em':
          _marked(MdMark.em, n, out);
        case 'del':
          _marked(MdMark.del, n, out);
        case 'code':
          out.add(MdCodeSpan(n.textContent));
        case 'br':
          out.add(const MdBreak());
        case 'input':
          break;
        case 'sup' when n.attributes['class'] == 'footnote-ref':
          final a = n.children?.whereType<md.Element>().firstOrNull;
          final href = a?.attributes['href'] ?? '';
          out.add(
            MdFootnoteRef(
              label: Uri.decodeComponent(
                href.startsWith('#fn-') ? href.substring(4) : href,
              ),
              number: int.tryParse(n.textContent) ?? 0,
            ),
          );
        case 'a':
          final children = _Inlines();
          _inline(n.children ?? const [], children);
          out.add(
            MdLink(
              href: n.attributes['href'] ?? '',
              title: n.attributes['title'],
              children: children.finish(),
              index: links++,
            ),
          );
        case 'img':
          out.add(_image(n.attributes['src'] ?? '', n.attributes['alt'] ?? ''));
        case MdTags.inlineMath:
          out.add(MdMath(tex: n.textContent, display: false, index: maths++));
        case MdTags.displayMath:
          out.add(MdMath(tex: n.textContent, display: true, index: maths++));
        case MdTags.inlineHtml:
          _htmlTag(HtmlTag.parse(n.textContent), out);
        default:
          _inline(n.children ?? const [], out);
      }
    }
  }

  void _marked(MdMark mark, md.Element e, _Inlines out) {
    out.open(mark);
    _inline(e.children ?? const [], out);
    out.close(mark);
  }

  void _htmlTag(HtmlTag? tag, _Inlines out) {
    if (tag == null) return;
    if (tag.dropsContent) {
      if (tag.closing) {
        if (out.dropping > 0) out.dropping--;
      } else if (!tag.selfClosing) {
        out.dropping++;
      }
      return;
    }
    if (tag.name == 'br') {
      out.add(const MdBreak());
      return;
    }
    if (tag.name == 'img' && !tag.closing) {
      out.add(_image(tag.attributes['src'] ?? '', tag.attributes['alt'] ?? ''));
      return;
    }
    final mark = tag.mark;
    if (mark == null || tag.selfClosing) return;
    tag.closing ? out.close(mark) : out.open(mark);
  }

  List<MdInline> _htmlBlock(String raw) {
    final out = _Inlines();
    var lineStart = true;
    for (final t in htmlTokens(raw)) {
      final tag = t.tag;
      if (tag == null) {
        var s = decodeEntities(t.text!).replaceAll(RegExp(r'\s+'), ' ');
        if (lineStart) s = s.trimLeft();
        if (s.isEmpty) continue;
        out.add(MdText(s));
        lineStart = false;
        continue;
      }
      if (tag.breaksLine && tag.name != 'br') {
        if (!lineStart && out.dropping == 0) {
          out.add(const MdBreak());
          lineStart = true;
        }
        if (tag.name == 'summary') {
          tag.closing ? out.close(MdMark.strong) : out.open(MdMark.strong);
        }
        continue;
      }
      _htmlTag(tag, out);
      if (tag.name == 'br') lineStart = true;
    }
    return _trimEnds(out.finish());
  }

  MdImage _image(String src, String alt) {
    final index = images++;
    final s = src.trim();
    final data = _dataImage.firstMatch(s);
    if (data != null) {
      final payload = data.group(2)!.replaceAll(RegExp(r'\s'), '');
      final padding = payload.endsWith('==')
          ? 2
          : payload.endsWith('=')
          ? 1
          : 0;
      final size = payload.length * 3 ~/ 4 - padding;
      if (size > 0 && size <= kMaxDataImageBytes) {
        try {
          final Uint8List bytes = base64Decode(payload);
          return MdImage(
            src: 'data:image/${data.group(1)}',
            alt: alt,
            index: index,
            source: MdImageSource.data,
            bytes: bytes,
          );
        } on FormatException {
          // fall through: unsupported
        }
      }
      return MdImage(
        src: 'data:',
        alt: alt,
        index: index,
        source: MdImageSource.unsupported,
      );
    }
    if (s.toLowerCase().startsWith('data:')) {
      return MdImage(
        src: 'data:',
        alt: alt,
        index: index,
        source: MdImageSource.unsupported,
      );
    }
    final uri = Uri.tryParse(s);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    final MdImageSource source;
    if (s.startsWith('//') ||
        scheme == 'http' ||
        scheme == 'https' ||
        scheme == 'ftp' ||
        (scheme.isNotEmpty &&
            scheme != 'file' &&
            (uri?.host ?? '').isNotEmpty)) {
      source = MdImageSource.remote;
    } else if (scheme.isEmpty || scheme == 'file' || scheme.length == 1) {
      // no scheme, file:, or a Windows drive letter
      source = MdImageSource.relative;
    } else {
      source = MdImageSource.unsupported;
    }
    return MdImage(
      src: s.startsWith('//') ? 'https:$s' : s,
      alt: alt,
      index: index,
      source: source,
    );
  }

  String _slug(String heading) {
    var base = heading
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
        .replaceAll(RegExp(r'\s'), '-');
    if (base.isEmpty) base = 'section';
    final n = _slugCounts.update(base, (v) => v + 1, ifAbsent: () => 0);
    final slug = n == 0 ? base : '$base-$n';
    slugs.putIfAbsent(slug, () => _blockIndex);
    return slug;
  }
}

final RegExp _dataImage = RegExp(
  r'^data:image/(png|jpeg|jpg|gif|webp);base64,([\s\S]*)$',
  caseSensitive: false,
);

List<MdInline> _trimEnds(List<MdInline> inl) {
  if (inl.isEmpty) return inl;
  final out = List<MdInline>.of(inl);
  if (out.first case MdText(:final text)) {
    final t = text.trimLeft();
    t.isEmpty ? out.removeAt(0) : out[0] = MdText(t);
  }
  if (out.isNotEmpty) {
    if (out.last case MdText(:final text)) {
      final t = text.trimRight();
      t.isEmpty ? out.removeLast() : out[out.length - 1] = MdText(t);
    }
  }
  while (out.isNotEmpty && out.last is MdBreak) {
    out.removeLast();
  }
  return out;
}

/// Text of inline content without marks.
String plainOfInlines(List<MdInline> inl) => _plain(inl);

String _plain(List<MdInline> inl) {
  final b = StringBuffer();
  void walk(List<MdInline> xs) {
    for (final x in xs) {
      switch (x) {
        case MdText(:final text):
          b.write(text);
        case MdStyled(:final children):
          walk(children);
        case MdCodeSpan(:final code):
          b.write(code);
        case MdLink(:final children):
          walk(children);
        case MdImage(:final alt):
          b.write(alt);
        case MdMath(:final tex):
          b.write(tex);
        case MdBreak():
          b.write('\n');
        case MdFootnoteRef(:final number):
          b.write('[$number]');
      }
    }
  }

  walk(inl);
  return b.toString();
}

String _plainOfNodes(List<MdNode> nodes) {
  final b = StringBuffer();
  void walk(List<MdNode> ns) {
    for (final n in ns) {
      if (b.isNotEmpty) b.write('\n');
      switch (n) {
        case MdHeading(:final inlines):
          b.write(_plain(inlines));
        case MdParagraph(:final inlines):
          b.write(_plain(inlines));
        case MdCodeBlock(:final code):
          b.write(code);
        case MdMathBlock(:final tex):
          b.write(tex);
        case MdQuote(:final children):
          walk(children);
        case MdList(:final items):
          for (final item in items) {
            walk(item.children);
          }
        case MdTable(:final header, :final rows):
          b.write(header.map(_plain).join('\t'));
          for (final r in rows) {
            b
              ..write('\n')
              ..write(r.map(_plain).join('\t'));
          }
        case MdRule():
          break;
        case MdFrontMatter(:final raw):
          b.write(raw);
      }
    }
  }

  walk(nodes);
  return b.toString();
}
