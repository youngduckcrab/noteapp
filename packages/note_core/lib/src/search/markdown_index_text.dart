// lib/src/search/markdown_index_text.dart (internal) — (v2.17-md, C217M-08, m5-7/08-markdown 6)
// The search units of an MD 문서 body, without a Markdown parser: top-level blocks split at
// blank lines (a fenced code block — ``` or ~~~ up to its closing fence — and a `$$` math
// block stay one block), a light clean-up per line (the MarkdownPreviewText rules: heading /
// quote / list / task markers, link targets, image syntax, HTML tags and inline marks removed;
// lines inside a fence kept as they are), and blocks longer than [maxUnitChars] split into
// several units of at most that length (never inside a surrogate pair) — nothing is cut off.

abstract final class MarkdownIndexText {
  /// The longest unit (UTF-16 code units).
  static const int maxUnitChars = 1000;

  static final RegExp _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
  static final RegExp _mathFence = RegExp(r'^\s{0,3}\$\$');
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}(\s+|$)');
  static final RegExp _headingClose = RegExp(r'\s+#+\s*$');
  static final RegExp _quote = RegExp(r'^\s{0,3}>\s?');
  static final RegExp _list = RegExp(r'^\s*(?:[-*+]|\d{1,9}[.)])\s+');
  static final RegExp _task = RegExp(r'^\[[ xX]\]\s+');
  static final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');
  static final RegExp _tableRule = RegExp(
    r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$',
  );
  static final RegExp _image = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
  static final RegExp _link = RegExp(r'\[([^\]]*)\]\([^)]*\)');
  static final RegExp _refDef = RegExp(r'^\s{0,3}\[[^\]]+\]:\s*\S+.*$');
  static final RegExp _tag = RegExp(r'<\/?[A-Za-z][^<>]*>');
  static final RegExp _marks = RegExp(r'(\*{1,3}|_{2,3}|~~|`+)');
  static final RegExp _spaces = RegExp(r'[ \t]+');

  /// The unit bodies of [text] in document order (empty blocks left out).
  static List<String> units(String text) {
    var lines = text
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    // YAML front matter ('---' first line … '---' or '...') is one block of its own.
    final blocks = <String>[];
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final end = lines.indexWhere(
        (l) => l.trim() == '---' || l.trim() == '...',
        1,
      );
      if (end > 0) {
        _add(blocks, lines.sublist(1, end).join('\n'));
        lines = lines.sublist(end + 1);
      }
    }
    final current = <String>[];
    void flush() {
      if (current.isEmpty) return;
      _add(blocks, current.join('\n'));
      current.clear();
    }

    String? fence; // the open code fence marker ('```', '~~~~', '$$')
    for (final raw in lines) {
      if (fence != null) {
        final t = raw.trimLeft();
        if (t.startsWith(fence) &&
            (fence == r'$$' || t.substring(fence.length).trim().isEmpty)) {
          if (fence == r'$$') {
            final rest = t.substring(2).trim();
            if (rest.isNotEmpty) current.add(rest);
          }
          fence = null;
          flush();
        } else {
          current.add(raw);
        }
        continue;
      }
      final fm = _fence.firstMatch(raw);
      if (fm != null) {
        flush();
        fence = fm.group(1);
        continue;
      }
      if (_mathFence.hasMatch(raw)) {
        flush();
        final rest = raw.trimLeft().substring(2);
        final close = rest.indexOf(r'$$');
        if (close >= 0) {
          // One-line $$ … $$.
          current.add(rest.substring(0, close).trim());
          flush();
        } else {
          fence = r'$$';
          if (rest.trim().isNotEmpty) current.add(rest.trim());
        }
        continue;
      }
      if (raw.trim().isEmpty) {
        flush();
        continue;
      }
      final line = _clean(raw);
      if (line != null && line.isNotEmpty) current.add(line);
    }
    flush();
    return [for (final b in blocks) ..._split(b)];
  }

  static void _add(List<String> blocks, String block) {
    final t = block.trim();
    if (t.isNotEmpty) blocks.add(t);
  }

  /// One line without block markers and inline marks; null for a line with no text
  /// (rules, table separator rows, reference definitions).
  static String? _clean(String raw) {
    if (_rule.hasMatch(raw) || _refDef.hasMatch(raw)) return null;
    if (_tableRule.hasMatch(raw) && raw.contains('-')) return null;
    var line = raw;
    if (_heading.hasMatch(line)) {
      line = line.replaceFirst(_heading, '').replaceFirst(_headingClose, '');
    }
    while (_quote.hasMatch(line)) {
      line = line.replaceFirst(_quote, '');
    }
    line = line.replaceFirst(_list, '').replaceFirst(_task, '');
    return line
        .replaceAllMapped(_image, (m) => m.group(1)!)
        .replaceAllMapped(_link, (m) => m.group(1)!)
        .replaceAll(_tag, '')
        .replaceAll(_marks, '')
        .replaceAll('|', ' ')
        .replaceAll(_spaces, ' ')
        .trim();
  }

  /// [block] in pieces of at most [maxUnitChars], cut at the last space / line break of a
  /// piece when there is one in its second half.
  static List<String> _split(String block) {
    if (block.length <= maxUnitChars) return [block];
    final out = <String>[];
    var start = 0;
    while (block.length - start > maxUnitChars) {
      var end = start + maxUnitChars;
      final unit = block.codeUnitAt(end - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) end--;
      final soft = _lastBreak(block, start + maxUnitChars ~/ 2, end);
      if (soft > start) end = soft;
      final piece = block.substring(start, end).trim();
      if (piece.isNotEmpty) out.add(piece);
      start = end;
    }
    final rest = block.substring(start).trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  static int _lastBreak(String s, int from, int to) {
    for (var i = to - 1; i >= from; i--) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x0A) return i + 1;
    }
    return -1;
  }
}
