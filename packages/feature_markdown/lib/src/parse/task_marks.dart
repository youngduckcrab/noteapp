// Where the task boxes are in the source (08-markdown 8.5, B-7). The markdown AST has no
// positions, so the lines are scanned: list items whose text starts with `[ ]`, `[x]` or
// `[X]`, also behind `>` quote markers, skipping fenced code, indented code and HTML
// blocks. A block's boxes can be toggled only when this count equals the parser's count
// for the block (md_document.dart); otherwise they are shown display-only.
final RegExp _task = RegExp(
  r'^\s*(?:[-*+]|\d{1,9}[.)])[ \t]+\[( |x|X)\](?=[ \t])',
);
final RegExp _quotePrefix = RegExp(r'^ {0,3}(?:>[ \t]?)+');
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
    var pos = start;
    while (pos <= stop && pos <= source.length) {
      var lineEnd = source.indexOf('\n', pos);
      if (lineEnd < 0 || lineEnd > stop) lineEnd = stop;
      final raw = source.substring(pos, lineEnd);
      final quote = _quotePrefix.firstMatch(raw);
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
        } else if (!blank && previousBlank && _htmlStart.hasMatch(line)) {
          inHtml = true;
          inList = false;
        } else {
          final m = _task.firstMatch(line);
          if (m != null) {
            out.add(pos + prefix + m.start + m.group(0)!.lastIndexOf('[') + 1);
          }
          if (!blank) {
            inList =
                RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])[ \t]').hasMatch(line) ||
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
}
