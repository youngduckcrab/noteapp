// The parsed form of an MD 문서 that the renderers draw (08-markdown 8.1-8.3). Plain data
// only (no closures, no Flutter types): documents over 50 KB are parsed on another
// isolate and sent back whole.
import 'dart:typed_data';

import 'package:meta/meta.dart';

// --- inline -----------------------------------------------------------------------

sealed class MdInline {
  const MdInline();
}

final class MdText extends MdInline {
  const MdText(this.text);
  final String text;
}

enum MdMark { strong, em, del, code, sub, sup, kbd }

/// Emphasis, strikethrough and the inline HTML marks.
final class MdStyled extends MdInline {
  const MdStyled(this.mark, this.children);
  final MdMark mark;
  final List<MdInline> children;
}

final class MdCodeSpan extends MdInline {
  const MdCodeSpan(this.code);
  final String code;
}

/// A link; [index] counts links in document order (MarkdownKeys.link).
final class MdLink extends MdInline {
  const MdLink({
    required this.href,
    required this.title,
    required this.children,
    required this.index,
  });
  final String href;
  final String? title;
  final List<MdInline> children;
  final int index;
}

enum MdImageSource {
  /// http(s) or another URL with a host: never fetched (placeholder).
  remote,

  /// `data:image/(png|jpeg|gif|webp);base64,…` up to 2 MB decoded: drawn.
  data,

  /// A path relative to the original file: the file was not imported.
  relative,

  /// Anything else (a `data:` URI that is too large, not an image, broken).
  unsupported,
}

final class MdImage extends MdInline {
  const MdImage({
    required this.src,
    required this.alt,
    required this.index,
    required this.source,
    this.bytes,
  });
  final String src;
  final String alt;
  final int index;
  final MdImageSource source;

  /// Decoded once while parsing (only for [MdImageSource.data]).
  final Uint8List? bytes;

  /// The host of a remote image ('' otherwise).
  String get host =>
      source == MdImageSource.remote ? (Uri.tryParse(src)?.host ?? '') : '';
}

/// `$…$` (inline) or `$$…$$` written inside a paragraph ([display]).
final class MdMath extends MdInline {
  const MdMath({required this.tex, required this.display, required this.index});
  final String tex;
  final bool display;
  final int index;
}

final class MdBreak extends MdInline {
  const MdBreak();
}

/// `[^label]` → its number in the footnotes list.
final class MdFootnoteRef extends MdInline {
  const MdFootnoteRef({required this.label, required this.number});
  final String label;
  final int number;
}

// --- blocks -----------------------------------------------------------------------

sealed class MdNode {
  const MdNode();
}

final class MdHeading extends MdNode {
  const MdHeading({
    required this.level,
    required this.inlines,
    required this.slug,
  });
  final int level;
  final List<MdInline> inlines;

  /// The '#anchor' of the heading (GitHub style, unique in the document).
  final String slug;
}

final class MdParagraph extends MdNode {
  const MdParagraph(this.inlines);
  final List<MdInline> inlines;
}

final class MdCodeBlock extends MdNode {
  const MdCodeBlock({
    required this.code,
    required this.language,
    required this.index,
  });
  final String code;
  final String? language;
  final int index;
}

final class MdMathBlock extends MdNode {
  const MdMathBlock({required this.tex, required this.index});
  final String tex;
  final int index;
}

final class MdQuote extends MdNode {
  const MdQuote(this.children);
  final List<MdNode> children;
}

/// A task box of a list item; [index] counts task boxes in document order.
@immutable
final class MdTask {
  const MdTask({required this.checked, required this.index});
  final bool checked;
  final int index;
}

final class MdListItem {
  const MdListItem({required this.children, this.task});
  final List<MdNode> children;
  final MdTask? task;
}

final class MdList extends MdNode {
  const MdList({
    required this.ordered,
    required this.start,
    required this.items,
  });
  final bool ordered;

  /// The first number of an ordered list (kept from the source).
  final int start;
  final List<MdListItem> items;
}

enum MdAlign { none, left, center, right }

final class MdTable extends MdNode {
  const MdTable({
    required this.aligns,
    required this.header,
    required this.rows,
    required this.index,
  });
  final List<MdAlign> aligns;
  final List<List<MdInline>> header;
  final List<List<List<MdInline>>> rows;
  final int index;
}

final class MdRule extends MdNode {
  const MdRule();
}

/// The YAML front matter ('---' … '---' at the top), shown as a folded info box.
final class MdFrontMatter extends MdNode {
  const MdFrontMatter(this.raw);
  final String raw;
}

/// One footnote of the list at the end of the document.
final class MdFootnote {
  const MdFootnote({
    required this.label,
    required this.number,
    required this.children,
  });
  final String label;
  final int number;
  final List<MdNode> children;
}

/// One top-level block: its source range in the decoded text, its key and what it
/// parsed to (a link reference definition parses to nothing).
final class MdBlock {
  const MdBlock({
    required this.key,
    required this.start,
    required this.end,
    required this.nodes,
    required this.plainText,
  });

  /// SHA-1 prefix of the block's source + ordinal among equal hashes (block_keys.dart).
  final String key;
  final int start;
  final int end;
  final List<MdNode> nodes;

  /// The block's text without marks (estimates, accessibility, tests).
  final String plainText;
}

/// The parsed document.
final class MdDocument {
  const MdDocument({
    required this.source,
    required this.blocks,
    required this.footnotes,
    required this.slugs,
    required this.taskOffsets,
    required this.taskCount,
    required this.linkCount,
    required this.codeCount,
    required this.tableCount,
    required this.mathCount,
    required this.imageCount,
  });

  static const MdDocument empty = MdDocument(
    source: '',
    blocks: [],
    footnotes: [],
    slugs: {},
    taskOffsets: [],
    taskCount: 0,
    linkCount: 0,
    codeCount: 0,
    tableCount: 0,
    mathCount: 0,
    imageCount: 0,
  );

  /// The decoded text this was parsed from.
  final String source;
  final List<MdBlock> blocks;
  final List<MdFootnote> footnotes;

  /// Heading slug → block index ('#heading' links).
  final Map<String, int> slugs;

  /// For task box i: the offset in [source] of the character between its brackets, or
  /// null when that box's block could not be matched to the source (display only).
  final List<int?> taskOffsets;
  final int taskCount;
  final int linkCount;
  final int codeCount;
  final int tableCount;
  final int mathCount;
  final int imageCount;

  /// The block whose range contains [offset] (or the first block after it).
  int blockAt(int offset) {
    if (blocks.isEmpty) return -1;
    var lo = 0;
    var hi = blocks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (blocks[mid].end < offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
