// The edit units of the live view (08-markdown 24.2, 24.15 D′8): one top-level block is
// one unit, a list block is one unit per top-level item (when the source spans agree
// with the parser), definitions that draw nothing get a chip. Every unit is a range of
// the parsed source; the live field edits exactly that range (live_edit.dart).
import 'package:meta/meta.dart';

import '../parse/block_splitter.dart';
import '../parse/list_items.dart';
import '../parse/md_model.dart';

/// How a unit's field looks and how Enter behaves in it.
enum LiveKind {
  /// Paragraphs, headings, list items, quotes: body font, Enter makes a new paragraph /
  /// item line.
  prose,

  /// Code, math, HTML, front matter, tables, definitions: monospace, Enter is a newline.
  code,
}

/// One tappable edit unit: characters [start, end) of [LiveLayout.doc]'s source.
@immutable
final class LiveUnit {
  const LiveUnit({
    required this.block,
    required this.start,
    required this.end,
    required this.kind,
    this.item,
    this.setext = false,
    this.definition = false,
  });

  /// Index of the block in MdDocument.blocks.
  final int block;

  /// The top-level item of a list block (null: the whole block).
  final int? item;
  final int start;
  final int end;
  final LiveKind kind;

  /// A setext heading (`Title` + `===` / `---` line): no heading buttons, no joining.
  final bool setext;

  /// A footnote / link reference definition (drawn as a chip).
  final bool definition;

  @override
  bool operator ==(Object other) =>
      other is LiveUnit &&
      other.block == block &&
      other.item == item &&
      other.start == start &&
      other.end == end &&
      other.kind == kind &&
      other.setext == setext &&
      other.definition == definition;

  @override
  int get hashCode =>
      Object.hash(block, item, start, end, kind, setext, definition);

  @override
  String toString() =>
      'LiveUnit(block $block${item == null ? '' : ' item $item'}, '
      '$start..$end, ${kind.name})';
}

final RegExp _setextUnderline = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');

/// The edit units of one parse.
final class LiveLayout {
  LiveLayout._(this.doc, this.units, this.items, this._firstUnit);

  factory LiveLayout.of(MdDocument doc) {
    final text = doc.source;
    final sources = splitBlocks(text);
    final units = <LiveUnit>[];
    final items = <int, List<ItemSpan>>{};
    final firstUnit = <int>[];
    for (var b = 0; b < doc.blocks.length; b++) {
      final block = doc.blocks[b];
      firstUnit.add(units.length);
      final kind = b < sources.length
          ? sources[b].kind
          : SourceBlockKind.paragraph;
      if (kind == SourceBlockKind.list) {
        final spans = scanTopLevelItems(text, block.start, block.end);
        if (spans != null && itemSpansMatch(text, block, spans)) {
          items[b] = spans;
          for (var i = 0; i < spans.length; i++) {
            units.add(
              LiveUnit(
                block: b,
                item: i,
                start: spans[i].start,
                end: spans[i].end,
                kind: LiveKind.prose,
              ),
            );
          }
          continue;
        }
      }
      final nodes = block.nodes;
      final code = switch (kind) {
        SourceBlockKind.fence ||
        SourceBlockKind.math ||
        SourceBlockKind.html ||
        SourceBlockKind.frontMatter ||
        SourceBlockKind.indentedCode ||
        SourceBlockKind.footnote => true,
        _ => nodes.isEmpty || (nodes.length == 1 && nodes.single is MdTable),
      };
      final src = text.substring(block.start, block.end);
      final lastLine = src.substring(src.lastIndexOf('\n') + 1);
      final setext =
          nodes.length == 1 &&
          nodes.single is MdHeading &&
          kind == SourceBlockKind.paragraph &&
          src.contains('\n') &&
          _setextUnderline.hasMatch(lastLine);
      units.add(
        LiveUnit(
          block: b,
          start: block.start,
          end: block.end,
          kind: code ? LiveKind.code : LiveKind.prose,
          setext: setext,
          definition: nodes.isEmpty,
        ),
      );
    }
    return LiveLayout._(doc, units, items, firstUnit);
  }

  final MdDocument doc;
  final List<LiveUnit> units;

  /// Top-level item spans of the list blocks edited per item.
  final Map<int, List<ItemSpan>> items;
  final List<int> _firstUnit;

  /// The units of block [b].
  Iterable<LiveUnit> unitsOfBlock(int b) sync* {
    if (b < 0 || b >= _firstUnit.length) return;
    for (var u = _firstUnit[b]; u < units.length && units[u].block == b; u++) {
      yield units[u];
    }
  }

  /// The index of the unit holding [offset] (or the nearest one before it); -1 when
  /// there are none.
  int indexAt(int offset) {
    var best = -1;
    for (var i = 0; i < units.length; i++) {
      if (units[i].start <= offset) {
        best = i;
      } else {
        break;
      }
    }
    return best;
  }
}
