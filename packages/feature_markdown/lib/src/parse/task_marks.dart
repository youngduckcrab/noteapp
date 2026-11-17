// Where the task boxes are in the source (08-markdown 8.5, B-7). The markdown AST has no
// positions, so the lines are scanned: list items whose text starts with `[ ]`, `[x]` or
// `[X]`, also behind `>` quote markers, skipping fenced code, indented code (also inside
// list items) and HTML blocks. A block's boxes can be toggled only when this scan found
// the same boxes as the parser (md_document.dart): same count, and box by box the same
// checked state and the same first word of the item's text ([matches]). Otherwise they
// are shown display-only — a tap never edits a line the reader cannot see as that box.
final RegExp _task = RegExp(
  r'^\s*(?:[-*+]|\d{1,9}[.)])[ \t]+\[( |x|X)\](?=[ \t])',
);
final RegExp _quotePrefix = RegExp(r'^ {0,3}(?:>[ \t]?)+');

/// Inside a list item a quote may start at the item's content indent.
final RegExp _quotePrefixInList = RegExp(r'^[ \t]*(?:>[ \t]?)+');
final RegExp _listMarker = RegExp(r'^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)');
final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
final RegExp _fence = RegExp(r'^\s*(`{3,}|~{3,})');
final RegExp _htmlStart = RegExp(r'^ {0,3}<(?:[A-Za-z!/?])');

abstract final class TaskMarks {
  /// Offsets (in [source]) of the character inside each task box's brackets, in document
  /// order, for the lines of [source] in [start, end).
  static List<int> scan(String source, {int start = 0, int? end}) {
    final stop = end ?? source.length;
    final out = <int>[];
    String? fence;
    var inHtml = false;
    var previousBlank = true;
    var inList = false;
    // The content indent of the last list item line (where its text starts).
    var contentIndent = 0;
    var pos = start;
    while (pos <= stop && pos <= source.length) {
      var lineEnd = source.indexOf('\n', pos);
      if (lineEnd < 0 || lineEnd > stop) lineEnd = stop;
      final raw = source.substring(pos, lineEnd);
      final quote = (inList ? _quotePrefixInList : _quotePrefix).firstMatch(
        raw,
      );
      final prefix = quote == null ? 0 : quote.end;
      final line = raw.substring(prefix);
      final blank = line.trim().isEmpty;
      if (fence != null) {
        final t = line.trim();
        if (t.startsWith(fence) && t.replaceAll(fence[0], '').trim().isEmpty) {
          fence = null;
        }
      } else if (inHtml) {
        if (blank) inHtml = false;
      } else {
        final f = _fence.firstMatch(line);
        if (f != null) {
          fence = f.group(1)!;
          if (!line.startsWith(' ') && !line.startsWith('\t')) inList = false;
        } else if (!blank &&
            previousBlank &&
            !inList &&
            line.startsWith('    ')) {
          // indented code (not a list continuation)
        } else if (!blank &&
            previousBlank &&
            inList &&
            _indentOf(line) >= contentIndent + 4) {
          // indented code inside a list item
        } else if (!blank && previousBlank && _htmlStart.hasMatch(line)) {
          inHtml = true;
          inList = false;
        } else {
          final m = _task.firstMatch(line);
          if (m != null) {
            out.add(pos + prefix + m.start + m.group(0)!.lastIndexOf('[') + 1);
          }
          if (!blank) {
            final marker = _listMarker.firstMatch(line);
            if (marker != null) {
              contentIndent = _indentOf(marker.group(0)!, all: true);
            }
            inList =
                marker != null ||
                (inList &&
                    (line.startsWith(' ') ||
                        line.startsWith('\t') ||
                        !previousBlank));
          }
        }
      }
      previousBlank = blank;
      if (lineEnd >= stop) break;
      pos = lineEnd + 1;
    }
    return out;
  }

  /// The scanned [marks] are the parser's boxes [boxes] (same order): at each mark the
  /// source has `[`, the mark, `]`; the checked state is the parser's; and the first word
  /// of the text after the box is the first word of the item's text (when both have one).
  static bool matches(
    String source,
    List<int> marks,
    List<({bool checked, String text})> boxes,
  ) {
    if (marks.length != boxes.length) return false;
    for (var k = 0; k < marks.length; k++) {
      final at = marks[k];
      if (at <= 0 || at + 1 >= source.length) return false;
      if (source[at - 1] != '[' || source[at + 1] != ']') return false;
      final c = source[at];
      final checked = c == 'x' || c == 'X';
      if (!checked && c != ' ') return false;
      if (checked != boxes[k].checked) return false;
      var lineEnd = source.indexOf('\n', at);
      if (lineEnd < 0) lineEnd = source.length;
      final mine = _firstWord(source.substring(at + 2, lineEnd));
      final theirs = _firstWord(boxes[k].text);
      if (mine.isNotEmpty && theirs.isNotEmpty && mine != theirs) return false;
    }
    return true;
  }

  static String _firstWord(String s) {
    for (final w in s.split(_notWord)) {
      if (w.isNotEmpty) return w;
    }
    return '';
  }

  /// The column after the leading white space of [s] (tabs to multiples of 4); with
  /// [all] the column after the whole of [s].
  static int _indentOf(String s, {bool all = false}) {
    var n = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x09) {
        n += 4 - n % 4;
      } else if (c == 0x20 || all) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }
}
