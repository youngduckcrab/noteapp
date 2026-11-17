// Math and raw-HTML syntaxes added to the markdown parser (08-markdown 8.2, B-1).
//
// Inline `$…$` follows the pandoc rules: no white space just inside the dollar signs, no
// digit right after the closing one ('$5 and $6' stays text), `\$` is a literal dollar
// (EscapeSyntax consumes it before these are tried at the `$`). `$$…$$` inside a line is
// display math; `\(…\)` is inline math. Block math is a `$$` line pair (or one line
// `$$ … $$`) or `\[ … \]`; a ```math fence is turned into block math by md_document.
// Code spans and fences are parsed by their own syntaxes first, so a `$` in code is code.
import 'package:markdown/markdown.dart' as md;

/// Element tags the converter (md_document.dart) understands.
abstract final class MdTags {
  static const String inlineMath = 'x-math';
  static const String displayMath = 'x-math-display';
  static const String blockMath = 'x-math-block';
  static const String inlineHtml = 'x-html';
  static const String blockHtml = 'x-html-block';
}

/// `$$…$$` inside a paragraph.
final class DisplayDollarMathSyntax extends md.InlineSyntax {
  DisplayDollarMathSyntax()
    : super(r'\$\$((?:\\[\s\S]|[^\\$])+?)\$\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(MdTags.displayMath, match[1]!.trim()));
    return true;
  }
}

/// `$…$` with the pandoc rules.
final class DollarMathSyntax extends md.InlineSyntax {
  DollarMathSyntax()
    : super(
        r'\$(?![\s$])((?:\\[\s\S]|[^\\$])+?)(?<!\s)\$(?!\d)',
        startCharacter: 0x24,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(MdTags.inlineMath, match[1]!));
    return true;
  }
}

/// `\(…\)`.
final class ParenMathSyntax extends md.InlineSyntax {
  ParenMathSyntax() : super(r'\\\(([\s\S]+?)\\\)', startCharacter: 0x5C);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(MdTags.inlineMath, match[1]!.trim()));
    return true;
  }
}

/// `$$` … `$$` (also on one line) and `\[` … `\]` as a block. Only when it is closed:
/// like pandoc, a `$$` line with no closing `$$` after it is ordinary text (otherwise the
/// rest of the document would vanish into one math error — review A6).
final class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  static final RegExp _open = RegExp(r'^ {0,3}(\$\$|\\\[)');
  static final Expando<_Closers> _closers = Expando('math closers');

  @override
  RegExp get pattern => _open;

  @override
  bool canParse(md.BlockParser parser) {
    final first = parser.current.content;
    final m = _open.firstMatch(first);
    if (m == null) return false;
    final close = m[1] == r'$$' ? r'$$' : r'\]';
    if (first.substring(m.end).contains(close)) return true;
    final c = _closers[parser] ??= _Closers(parser.lines);
    final at = c.index[parser.current] ?? -1;
    return (close == r'$$' ? c.lastDollar : c.lastBracket) > at;
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final first = parser.current.content;
    final m = _open.firstMatch(first)!;
    final close = m[1] == r'$$' ? r'$$' : r'\]';
    final rest = first.substring(m.end);
    final closeAt = rest.indexOf(close);
    if (closeAt >= 0) {
      parser.advance();
      return md.Element.text(
        MdTags.blockMath,
        rest.substring(0, closeAt).trim(),
      );
    }
    final lines = <String>[rest];
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      final at = line.indexOf(close);
      parser.advance();
      if (at >= 0) {
        lines.add(line.substring(0, at));
        break;
      }
      lines.add(line);
    }
    return md.Element.text(MdTags.blockMath, lines.join('\n').trim());
  }
}

/// Where the closers are in one block parser's lines (computed once per parser, so a
/// block of many `$$` lines stays linear).
final class _Closers {
  _Closers(List<md.Line> lines) {
    for (var i = 0; i < lines.length; i++) {
      index[lines[i]] = i;
      if (lines[i].content.contains(r'$$')) lastDollar = i;
      if (lines[i].content.contains(r'\]')) lastBracket = i;
    }
  }

  final Map<md.Line, int> index = Map.identity();
  int lastDollar = -1;
  int lastBracket = -1;
}

/// A long run of word characters without spaces (a pasted hash, base64, a minified line)
/// as plain text in one step. Without it two syntaxes of the markdown package scan the
/// rest of the run at every position of it — quadratic: the word syntax
/// (`[A-Za-z0-9]+(?=\s)`) and the GFM e-mail autolink (`[-_.+a-z0-9]+@…`). A
/// 16,000-character run took 7.6 s, a 500,000-character one did not finish (review A5).
/// It is tried right after the GFM autolink syntax, so URLs and e-mail addresses are still
/// links; inside such a run (256+ characters, no space) emphasis is not looked for.
final class LongRunSyntax extends md.InlineSyntax {
  LongRunSyntax() : super(r'[-_.+/=A-Za-z0-9]{256,}');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(match[0]!));
    return true;
  }
}

/// Inline raw HTML kept apart from text (encodeHtml is off, so the stock syntax would
/// give a plain Text node that the converter could not tell from prose).
final class TaggedInlineHtmlSyntax extends md.InlineHtmlSyntax {
  TaggedInlineHtmlSyntax();

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(MdTags.inlineHtml, match[0]!));
    return true;
  }
}

/// An HTML block kept apart from text (see [TaggedInlineHtmlSyntax]).
final class TaggedHtmlBlockSyntax extends md.HtmlBlockSyntax {
  const TaggedHtmlBlockSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final node = super.parse(parser);
    return md.Element.text(MdTags.blockHtml, node.textContent);
  }
}

/// The parser's extension set: GitHub flavoured (not gitHubWeb — its emoji table is
/// large), with the tagged HTML syntax in place of the stock one, plus math.
md.ExtensionSet markdownExtensions() => md.ExtensionSet(
  [
    const MathBlockSyntax(),
    const TaggedHtmlBlockSyntax(),
    ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
  ],
  [
    DisplayDollarMathSyntax(),
    DollarMathSyntax(),
    ParenMathSyntax(),
    TaggedInlineHtmlSyntax(),
    for (final s in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
      if (s is md.AutolinkExtensionSyntax) ...[
        s,
        LongRunSyntax(),
      ] else if (s is! md.InlineHtmlSyntax)
        s,
  ],
);
