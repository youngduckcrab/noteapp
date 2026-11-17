// Source ranges of the top-level items of a list block (08-markdown 24.2, 24.15 D′8): the
// live view edits a list one top-level item at a time — its marker line up to the next
// top-level marker line, nested items and continuation paragraphs included. Found from
// the source by indentation (the parser keeps no positions) and used only when they agree
// with the parser's items; otherwise the whole list block is one unit (nothing is lost,
// it is just less handy).
import 'package:meta/meta.dart';

import 'md_model.dart';

/// One top-level list item: characters [start, end) of the decoded text (no trailing
/// blank lines), [markerEnd] = just after its marker and the spaces after it.
@immutable
final class ItemSpan {
  const ItemSpan(this.start, this.end, this.markerEnd);

  final int start;
  final int end;
  final int markerEnd;

  @override
  bool operator ==(Object other) =>
      other is ItemSpan &&
      other.start == start &&
      other.end == end &&
      other.markerEnd == markerEnd;

  @override
  int get hashCode => Object.hash(start, end, markerEnd);

  @override
  String toString() => 'ItemSpan($start..$end, marker..$markerEnd)';
}

final RegExp _marker = RegExp(r'^( {0,3})([-*+]|\d{1,9}[.)])([ \t]+|$)');

/// Columns of [s]'s leading whitespace (tabs stop every 4 columns).
int indentColumns(String s) {
  var col = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x20) {
      col++;
    } else if (c == 0x09) {
      col += 4 - col % 4;
    } else {
      break;
    }
  }
  return col;
}

/// The top-level item spans of the list block [start, end) of [text], or null when the
/// block does not start with a list marker.
List<ItemSpan>? scanTopLevelItems(String text, int start, int end) {
  final out = <ItemSpan>[];
  var contentIndent = 0;
  var lineStart = start;
  var itemStart = -1;
  var markerEnd = -1;
  var lastNonBlankEnd = -1;
  while (lineStart <= end) {
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd < 0 || lineEnd > end) lineEnd = end;
    final line = text.substring(lineStart, lineEnd);
    final blank = line.trim().isEmpty;
    if (!blank) {
      final m = _marker.firstMatch(line);
      final indent = indentColumns(line);
      final topLevel =
          m != null && (itemStart < 0 || indent < contentIndent) && indent <= 3;
      if (topLevel) {
        if (itemStart >= 0) {
          out.add(ItemSpan(itemStart, lastNonBlankEnd, markerEnd));
        }
        itemStart = lineStart;
        final spaces = m.group(3)!;
        final markerWidth = m.group(1)!.length + m.group(2)!.length;
        // CommonMark: 1–4 spaces after the marker count; more = code (then 1).
        final gap = spaces.isEmpty || spaces.length > 4 ? 1 : spaces.length;
        contentIndent = markerWidth + gap;
        markerEnd =
            lineStart + m.group(1)!.length + m.group(2)!.length + spaces.length;
      } else if (itemStart < 0) {
        return null;
      }
      lastNonBlankEnd = lineEnd;
    }
    if (lineEnd >= end) break;
    lineStart = lineEnd + 1;
  }
  if (itemStart < 0) return null;
  out.add(ItemSpan(itemStart, lastNonBlankEnd, markerEnd));
  return out;
}

/// The items of [block] when all its nodes are lists (a block can hold several: a
/// marker change or a blank line between a bullet and a numbered list), in order, with
/// the list each belongs to; null otherwise.
List<(MdList, MdListItem)>? blockListItems(MdBlock block) {
  if (block.nodes.isEmpty) return null;
  final out = <(MdList, MdListItem)>[];
  for (final n in block.nodes) {
    if (n is! MdList) return null;
    for (final i in n.items) {
      out.add((n, i));
    }
  }
  return out;
}

/// [spans] fit [block]: its nodes are lists with as many items in all, the spans tile
/// the block (only whitespace between them), and every item's first words are in its
/// span.
bool itemSpansMatch(String text, MdBlock block, List<ItemSpan> spans) {
  final items = blockListItems(block);
  if (items == null || items.length != spans.length) return false;
  if (spans.first.start != block.start || spans.last.end != block.end) {
    return false;
  }
  for (var i = 0; i < spans.length; i++) {
    final s = spans[i];
    if (s.end < s.markerEnd || s.start >= s.end) return false;
    if (i > 0 && text.substring(spans[i - 1].end, s.start).trim().isNotEmpty) {
      return false;
    }
    final first = _firstText(items[i].$2);
    if (first.isNotEmpty && !text.substring(s.start, s.end).contains(first)) {
      return false;
    }
  }
  return true;
}

String _firstText(MdListItem item) {
  for (final c in item.children) {
    if (c is MdParagraph) {
      final words = StringBuffer();
      for (final i in c.inlines) {
        if (i is MdText) {
          words.write(i.text);
        } else {
          break;
        }
      }
      final t = words.toString().trimLeft();
      final cut = t.indexOf(RegExp(r'\s'));
      final word = cut < 0 ? t : t.substring(0, cut);
      return word.length > 6 ? word.substring(0, 6) : word;
    }
    return '';
  }
  return '';
}
