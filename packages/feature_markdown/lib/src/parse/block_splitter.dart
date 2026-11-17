// Top-level blocks of an MD 문서 with their source ranges (08-markdown 4.7, B-1/B-2).
//
// The markdown package's AST carries no source positions, so the document is first cut
// into top-level blocks by these line rules, and each block is parsed on its own (all
// blocks share one markdown Document, so reference links and footnotes still work across
// blocks — md_document.dart). Search landing, the task marks and the block keys all use
// these ranges. Offsets are in the editor's decoded text (no BOM, LF only — 4.6).
import 'package:meta/meta.dart';

/// What started a source block (only the cutting rules depend on it).
enum SourceBlockKind {
  frontMatter,
  fence,
  math,
  html,
  heading,
  rule,
  list,
  footnote,
  indentedCode,
  paragraph,
}

/// Lines [startLine]..[endLine] (inclusive) of the text = characters [start, end).
@immutable
final class SourceBlock {
  const SourceBlock({
    required this.kind,
    required this.start,
    required this.end,
    required this.startLine,
    required this.endLine,
  });

  final SourceBlockKind kind;
  final int start;
  final int end;
  final int startLine;
  final int endLine;

  @override
  bool operator ==(Object other) =>
      other is SourceBlock &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.startLine == startLine &&
      other.endLine == endLine;

  @override
  int get hashCode => Object.hash(kind, start, end, startLine, endLine);

  @override
  String toString() => 'SourceBlock(${kind.name}, $start..$end)';
}

final RegExp _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final RegExp _dollarMath = RegExp(r'^ {0,3}\$\$');
final RegExp _bracketMath = RegExp(r'^ {0,3}\\\[');
final RegExp _heading = RegExp(r'^ {0,3}#{1,6}(?:[ \t]|$)');
final RegExp _rule = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');
final RegExp _listItem = RegExp(r'^ {0,3}(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)');
final RegExp _footnote = RegExp(r'^ {0,3}\[\^[^\]\s]+\]:');
final RegExp _indented = RegExp(r'^(?: {4}|\t)');
final RegExp _htmlComment = RegExp(r'^ {0,3}<!--');
final RegExp _htmlRaw = RegExp(
  r'^ {0,3}<(pre|script|style|textarea)(?:[\s>]|$)',
  caseSensitive: false,
);

bool _blank(String line) => line.trim().isEmpty;

bool _isIndented(String line) => line.startsWith(' ') || line.startsWith('\t');

/// The line start offsets of [text] (one more entry than lines: the end).
List<int> lineStartsOf(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  starts.add(text.length + 1);
  return starts;
}

/// The top-level blocks of [text] in order; blank lines between blocks belong to none.
List<SourceBlock> splitBlocks(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  final starts = lineStartsOf(text);
  final out = <SourceBlock>[];
  void emit(SourceBlockKind kind, int from, int to) {
    // `to` inclusive; the end excludes the line break.
    out.add(
      SourceBlock(
        kind: kind,
        start: starts[from],
        end: starts[to] + lines[to].length,
        startLine: from,
        endLine: to,
      ),
    );
  }

  final n = lines.length;
  var i = 0;
  // YAML front matter: '---' on the first line, closed by '---' or '...'.
  if (lines.first.trimRight() == '---') {
    for (var j = 1; j < n; j++) {
      final t = lines[j].trimRight();
      if (t == '---' || t == '...') {
        emit(SourceBlockKind.frontMatter, 0, j);
        i = j + 1;
        break;
      }
    }
  }
  while (i < n) {
    final line = lines[i];
    if (_blank(line)) {
      i++;
      continue;
    }
    final start = i;
    final fence = _fenceOpen.firstMatch(line);
    if (fence != null &&
        !(fence.group(1)!.startsWith('`') && fence.group(2)!.contains('`'))) {
      final marker = fence.group(1)!;
      i++;
      while (i < n && !_closesFence(lines[i], marker)) {
        i++;
      }
      if (i >= n) i = n - 1;
      emit(SourceBlockKind.fence, start, i);
      i++;
      continue;
    }
    if (_dollarMath.hasMatch(line) || _bracketMath.hasMatch(line)) {
      final dollar = _dollarMath.hasMatch(line);
      final close = dollar ? r'$$' : r'\]';
      final rest = line.substring(line.indexOf(dollar ? r'$$' : r'\[') + 2);
      if (!rest.contains(close)) {
        i++;
        while (i < n && !lines[i].contains(close)) {
          i++;
        }
        if (i >= n) i = n - 1;
      }
      emit(SourceBlockKind.math, start, i);
      i++;
      continue;
    }
    if (_htmlComment.hasMatch(line) || _htmlRaw.hasMatch(line)) {
      final raw = _htmlRaw.firstMatch(line);
      final close = raw == null ? '-->' : '</${raw.group(1)!.toLowerCase()}>';
      while (i < n && !lines[i].toLowerCase().contains(close)) {
        i++;
      }
      if (i >= n) i = n - 1;
      emit(SourceBlockKind.html, start, i);
      i++;
      continue;
    }
    if (_heading.hasMatch(line)) {
      emit(SourceBlockKind.heading, i, i);
      i++;
      continue;
    }
    if (_rule.hasMatch(line)) {
      emit(SourceBlockKind.rule, i, i);
      i++;
      continue;
    }
    final kind = _listItem.hasMatch(line)
        ? SourceBlockKind.list
        : _footnote.hasMatch(line)
        ? SourceBlockKind.footnote
        : _indented.hasMatch(line)
        ? SourceBlockKind.indentedCode
        : SourceBlockKind.paragraph;
    i++;
    var last = start;
    while (i < n) {
      final l = lines[i];
      if (_blank(l)) {
        if (kind == SourceBlockKind.paragraph) break;
        var k = i + 1;
        while (k < n && _blank(lines[k])) {
          k++;
        }
        if (k >= n) break;
        final next = lines[k];
        final continues = switch (kind) {
          SourceBlockKind.indentedCode => _indented.hasMatch(next),
          SourceBlockKind.list => _isIndented(next) || _listItem.hasMatch(next),
          _ => _isIndented(next),
        };
        if (!continues) break;
        i = k;
        continue;
      }
      if (kind == SourceBlockKind.indentedCode && !_indented.hasMatch(l)) {
        break;
      }
      final indented = _isIndented(l);
      if (!(kind == SourceBlockKind.list && indented)) {
        if (_heading.hasMatch(l) ||
            _dollarMath.hasMatch(l) ||
            _bracketMath.hasMatch(l) ||
            _htmlComment.hasMatch(l) ||
            _htmlRaw.hasMatch(l)) {
          break;
        }
        final f = _fenceOpen.firstMatch(l);
        if (f != null && !indented) break;
      }
      // A fence inside a list item (indented): keep it whole, blank lines included.
      final inner = _fenceOpen.firstMatch(l.trimLeft());
      if (kind == SourceBlockKind.list && indented && inner != null) {
        final marker = inner.group(1)!;
        var j = i + 1;
        while (j < n && !_closesFence(lines[j], marker)) {
          j++;
        }
        if (j < n) {
          last = j;
          i = j + 1;
          continue;
        }
      }
      last = i;
      i++;
    }
    emit(kind, start, last);
    // `i` may sit on a blank line or on the next block's first line.
    if (i <= last) i = last + 1;
  }
  return out;
}

bool _closesFence(String line, String marker) {
  final t = line.trim();
  if (t.isEmpty || t[0] != marker[0]) return false;
  var count = 0;
  while (count < t.length && t[count] == marker[0]) {
    count++;
  }
  return count >= marker.length && t.substring(count).trim().isEmpty;
}
