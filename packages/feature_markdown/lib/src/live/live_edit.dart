// Pure edits of the live field (08-markdown 24.3, 24.4, 24.7, 24.15). The field holds the
// markdown source of one range of the document; nothing here touches the document — the
// editor writes `base[0, start) + replacement + base[end..]` (composeLive), so text
// outside the range is the parsed text, character for character.
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'live_units.dart';

/// The part of the parsed source a live session replaces, and how.
@immutable
final class LiveRange {
  const LiveRange({
    required this.start,
    required this.end,
    this.before = '',
    this.after = '',
    this.pending = false,
  });

  /// Characters [start, end) of the parsed source.
  final int start;
  final int end;

  /// Written in front of / after the field's text (separators the field does not show).
  final String before;
  final String after;

  /// A new block: [before] / [after] (and so anything at all) are written only while
  /// the field is not empty (24.15 D′6).
  final bool pending;

  LiveRange copyWith({int? start, int? end, String? before, String? after}) =>
      LiveRange(
        start: start ?? this.start,
        end: end ?? this.end,
        before: before ?? this.before,
        after: after ?? this.after,
        pending: pending,
      );

  /// What replaces [start, end) when the field holds [field].
  String replacement(String field) =>
      pending && field.isEmpty ? '' : '$before$field$after';

  /// Where the field's offset 0 is in the composed buffer.
  int fieldOffset(String field) =>
      start + (pending && field.isEmpty ? 0 : before.length);

  @override
  String toString() =>
      'LiveRange($start..$end, before ${before.length}, after ${after.length}'
      '${pending ? ', pending' : ''})';
}

/// The buffer while the field holds [field]: only [r]'s range of [base] differs.
String composeLive(String base, LiveRange r, String field) =>
    base.replaceRange(r.start, r.end, r.replacement(field));

/// The range of a new block at the end of the document [base] (after its last block,
/// which ends at [lastBlockEnd]; -1 = no blocks): a blank line in front unless empty.
LiveRange pendingAtEnd(String base, int lastBlockEnd) {
  if (lastBlockEnd < 0) {
    // Nothing but blank lines (or nothing): the text goes in front of them.
    return const LiveRange(start: 0, end: 0, pending: true);
  }
  return LiveRange(
    start: lastBlockEnd,
    end: lastBlockEnd,
    before: '\n\n',
    pending: true,
  );
}

// --- lines ------------------------------------------------------------------------

final RegExp kLiveListLine = RegExp(
  r'^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+|$)(\[[ xX]\](?:[ \t]+|$))?',
);
final RegExp _quoteLine = RegExp(r'^([ \t]{0,3}(?:>[ \t]?)+)');
final RegExp _headingLine = RegExp(r'^ {0,3}#{1,6}(?:[ \t]+|$)');
final RegExp _fenceLine = RegExp(r'^[ \t]*(`{3,}|~{3,})');

/// [start, end) of the line holding [offset].
(int, int) lineAt(String text, int offset) {
  final o = offset.clamp(0, text.length);
  final start = o == 0 ? 0 : text.lastIndexOf('\n', o - 1) + 1;
  var end = text.indexOf('\n', o);
  if (end < 0) end = text.length;
  return (start, end);
}

/// The marker at the start of [line] (heading `# `, list `- ` / `1. ` + task box,
/// quote `> `): its length, or 0.
int lineMarkerLength(String line) {
  final l = kLiveListLine.firstMatch(line);
  if (l != null) return l.group(0)!.length;
  final h = _headingLine.firstMatch(line);
  if (h != null) return h.group(0)!.length;
  final q = _quoteLine.firstMatch(line);
  if (q != null) return q.group(0)!.length;
  return 0;
}

bool _insideFence(String text, int offset) {
  var open = false;
  var start = 0;
  while (start < offset) {
    var end = text.indexOf('\n', start);
    if (end < 0) end = text.length;
    if (end > offset) break;
    if (_fenceLine.hasMatch(text.substring(start, end))) open = !open;
    start = end + 1;
  }
  return open;
}

TextEditingValue _replace(
  String text,
  int from,
  int to,
  String with_,
  int caret,
) => TextEditingValue(
  text: text.replaceRange(from, to, with_),
  selection: TextSelection.collapsed(offset: caret),
);

/// The field after Enter at [v]'s (collapsed) caret, or null for a plain newline.
/// Returning [v] itself means 'do nothing'.
TextEditingValue? liveEnter(TextEditingValue v, LiveKind kind) {
  final text = v.text;
  final sel = v.selection;
  if (!sel.isValid) return null;
  if (kind == LiveKind.code) return null;
  if (text.isEmpty) return v;
  final caret = sel.start;
  if (_insideFence(text, caret)) return null;
  final (ls, le) = lineAt(text, caret);
  final line = text.substring(ls, le);
  final list = kLiveListLine.firstMatch(line);
  if (list != null) {
    final prefix = list.group(0)!;
    final content = line.substring(prefix.length);
    if (content.trim().isEmpty) {
      // An empty item: leave the list (the marker goes, a blank line ends the list).
      if (ls == 0) return _replace(text, ls, le, '', 0);
      return _replace(text, ls, le, '\n', ls + 1);
    }
    final indent = list.group(1)!;
    final number = list.group(3);
    final spaces = list.group(5)!.isEmpty ? ' ' : list.group(5)!;
    final marker = number == null
        ? list.group(2)!
        : '${int.parse(number) + 1}${list.group(4)!}';
    final task = list.group(6) == null ? '' : '[ ] ';
    final next = '\n$indent$marker$spaces$task';
    final at = caret < ls + prefix.length ? ls + prefix.length : caret;
    return _replace(
      text,
      at,
      sel.end < at ? at : sel.end,
      next,
      at + next.length,
    );
  }
  final quote = _quoteLine.firstMatch(line);
  if (quote != null) {
    final prefix = quote.group(0)!;
    if (line.substring(prefix.length).trim().isEmpty) {
      if (ls == 0) return _replace(text, ls, le, '', 0);
      return _replace(text, ls, le, '\n', ls + 1);
    }
    final p = prefix.endsWith(' ') ? prefix : '$prefix ';
    final at = caret < ls + prefix.length ? ls + prefix.length : caret;
    return _replace(text, at, sel.end, '\n$p', at + 1 + p.length);
  }
  if (line.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
    // A continuation line (inside a list item): keep its indent.
    final ws = line.substring(0, line.length - line.trimLeft().length);
    return _replace(text, caret, sel.end, '\n$ws', caret + 1 + ws.length);
  }
  if (line.trim().isEmpty) {
    // Already on an empty line: one more blank line would only add bytes.
    final before = ls >= 1 ? text.substring(0, ls - 1) : '';
    if (ls == 0 || before.endsWith('\n') || before.isEmpty) return v;
    return _replace(text, caret, sel.end, '\n', caret + 1);
  }
  return _replace(text, caret, sel.end, '\n\n', caret + 2);
}

/// Shift+Enter: a line break inside the block (a plain newline; in a list item the new
/// line is indented to the item's content).
TextEditingValue liveShiftEnter(TextEditingValue v, LiveKind kind) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  if (kind == LiveKind.prose) {
    final (ls, le) = lineAt(text, sel.start);
    final line = text.substring(ls, le);
    if (_headingLine.hasMatch(line)) {
      return liveEnter(v, kind) ?? v;
    }
    final list = kLiveListLine.firstMatch(line);
    if (list != null) {
      final pad = ' ' * (list.group(1)!.length + list.group(2)!.length + 1);
      return _replace(
        text,
        sel.start,
        sel.end,
        '\n$pad',
        sel.start + 1 + pad.length,
      );
    }
  }
  return _replace(text, sel.start, sel.end, '\n', sel.start + 1);
}

/// Removes the marker of the field's first line (Backspace at the start): the value and
/// how many characters went, or null when the first line has none.
(TextEditingValue, int)? stripFirstMarker(TextEditingValue v) {
  final text = v.text;
  final (_, le) = lineAt(text, 0);
  final n = lineMarkerLength(text.substring(0, le));
  if (n == 0) return null;
  // Only the marker: leading whitespace of a list item goes too (a nested item becomes
  // a paragraph line of its parent's text, which is what the user sees).
  return (
    TextEditingValue(
      text: text.substring(n),
      selection: const TextSelection.collapsed(offset: 0),
    ),
    n,
  );
}

// --- formatters ---------------------------------------------------------------------

/// Pasted CR LF / lone CR become LF (the buffer is LF only — 4.6, 24.15 D′15).
class LineFeedFormatter extends TextInputFormatter {
  const LineFeedFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\r')) return newValue;
    final text = newValue.text;
    final out = StringBuffer();
    final map = List<int>.filled(text.length + 1, 0);
    var j = 0;
    for (var i = 0; i < text.length; i++) {
      map[i] = j;
      final c = text.codeUnitAt(i);
      if (c == 0x0D) {
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) continue;
        out.writeCharCode(0x0A);
      } else {
        out.writeCharCode(c);
      }
      j++;
    }
    map[text.length] = j;
    int m(int o) => o < 0 ? o : map[o.clamp(0, text.length)];
    final sel = newValue.selection;
    return TextEditingValue(
      text: out.toString(),
      selection: sel.isValid
          ? TextSelection(
              baseOffset: m(sel.baseOffset),
              extentOffset: m(sel.extentOffset),
            )
          : sel,
      composing: newValue.composing.isValid
          ? TextRange(
              start: m(newValue.composing.start),
              end: m(newValue.composing.end),
            )
          : TextRange.empty,
    );
  }
}

/// Turns a typed Enter (one '\n' inserted at a collapsed caret, nothing composing) into
/// [liveEnter]'s result. Anything else passes (Korean IME: the keyboard ends the
/// syllable before it sends the newline, so composing text is never touched).
class LiveEnterFormatter extends TextInputFormatter {
  LiveEnterFormatter(this.kind);

  final LiveKind Function() kind;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sel = oldValue.selection;
    if (!sel.isValid || newValue.composing.isValid) return newValue;
    final o = oldValue.text;
    final n = newValue.text;
    final removed = sel.end - sel.start;
    if (n.length != o.length - removed + 1) return newValue;
    if (sel.start >= n.length || n.codeUnitAt(sel.start) != 0x0A) {
      return newValue;
    }
    if (n.substring(0, sel.start) != o.substring(0, sel.start) ||
        n.substring(sel.start + 1) != o.substring(sel.end)) {
      return newValue;
    }
    final out = liveEnter(
      oldValue.copyWith(composing: TextRange.empty),
      kind(),
    );
    return out ?? newValue;
  }
}

// --- toolbar --------------------------------------------------------------------------

/// Wraps the selection in [mark] (or unwraps it when it is wrapped already); with no
/// selection inserts a pair with the caret in the middle.
TextEditingValue toggleWrap(TextEditingValue v, String mark) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final s = sel.start;
  final e = sel.end;
  final m = mark.length;
  if (s >= m &&
      e + m <= text.length &&
      text.substring(s - m, s) == mark &&
      text.substring(e, e + m) == mark) {
    final out = text.replaceRange(e, e + m, '').replaceRange(s - m, s, '');
    return TextEditingValue(
      text: out,
      selection: TextSelection(baseOffset: s - m, extentOffset: e - m),
    );
  }
  final inner = text.substring(s, e);
  if (inner.length >= 2 * m && inner.startsWith(mark) && inner.endsWith(mark)) {
    final un = inner.substring(m, inner.length - m);
    return TextEditingValue(
      text: text.replaceRange(s, e, un),
      selection: TextSelection(baseOffset: s, extentOffset: s + un.length),
    );
  }
  final out = text.replaceRange(s, e, '$mark$inner$mark');
  return TextEditingValue(
    text: out,
    selection: s == e
        ? TextSelection.collapsed(offset: s + m)
        : TextSelection(baseOffset: s + m, extentOffset: e + m),
  );
}

/// `[selection](` caret `)`; with no selection `[` caret `]()`.
TextEditingValue insertLink(TextEditingValue v) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final inner = text.substring(sel.start, sel.end);
  if (inner.isEmpty) {
    return TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, '[]()'),
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }
  final ins = '[$inner]()';
  return TextEditingValue(
    text: text.replaceRange(sel.start, sel.end, ins),
    selection: TextSelection.collapsed(offset: sel.start + ins.length - 1),
  );
}

/// Line starters of the toolbar.
enum LinePrefix { bullet, numbered, task, quote, h1, h2, h3 }

String? _kindOf(String line) {
  final l = kLiveListLine.firstMatch(line);
  if (l != null) {
    if (l.group(6) != null) return 'task';
    return l.group(3) != null ? 'numbered' : 'bullet';
  }
  final h = _headingLine.firstMatch(line);
  if (h != null) {
    final n = h.group(0)!.trim().length;
    return 'h$n';
  }
  if (_quoteLine.hasMatch(line)) return 'quote';
  return null;
}

/// Puts [p] at the start of every line the selection touches (headings: the first one
/// only), replacing another starter; when every line has [p] already it is removed.
TextEditingValue toggleLinePrefix(TextEditingValue v, LinePrefix p) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final heading =
      p == LinePrefix.h1 || p == LinePrefix.h2 || p == LinePrefix.h3;
  final from = lineAt(text, sel.start).$1;
  final to = heading ? lineAt(text, sel.start).$2 : lineAt(text, sel.end).$2;
  final lines = text.substring(from, to).split('\n');
  final all = lines.every((l) => l.trim().isEmpty || _kindOf(l) == p.name);
  final out = <String>[];
  var n = 1;
  for (final l in lines) {
    if (l.trim().isEmpty && lines.length > 1) {
      out.add(l);
      continue;
    }
    final indent = _kindOf(l) == null || _kindOf(l)!.startsWith('h')
        ? ''
        : (kLiveListLine.firstMatch(l)?.group(1) ?? '');
    final bare = l.substring(lineMarkerLength(l));
    if (all) {
      out.add('$indent$bare');
      continue;
    }
    final starter = switch (p) {
      LinePrefix.bullet => '- ',
      LinePrefix.numbered => '${n++}. ',
      LinePrefix.task => '- [ ] ',
      LinePrefix.quote => '> ',
      LinePrefix.h1 => '# ',
      LinePrefix.h2 => '## ',
      LinePrefix.h3 => '### ',
    };
    out.add('$indent$starter$bare');
  }
  final joined = out.join('\n');
  final delta = joined.length - (to - from);
  return TextEditingValue(
    text: text.replaceRange(from, to, joined),
    selection: TextSelection.collapsed(
      offset: (sel.end + delta).clamp(from, from + joined.length),
    ),
  );
}

/// Block templates of the toolbar, inserted after the caret's line.
enum LiveTemplate { codeBlock, mathBlock, table, rule }

TextEditingValue insertTemplate(TextEditingValue v, LiveTemplate t) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final (ls, le) = lineAt(text, sel.end);
  final emptyLine = text.substring(ls, le).trim().isEmpty;
  final at = emptyLine ? ls : le;
  final lead = emptyLine
      ? (ls == 0 || (ls >= 2 && text.substring(ls - 2, ls) == '\n\n')
            ? ''
            : '\n')
      : '\n\n';
  final (String body, int caret) = switch (t) {
    LiveTemplate.codeBlock => ('```\n\n```', 4),
    LiveTemplate.mathBlock => ('\$\$\n\n\$\$', 3),
    LiveTemplate.table => ('| 제목 | 제목 |\n| --- | --- |\n|  |  |', 28),
    LiveTemplate.rule => ('---\n\n', 5),
  };
  final ins = '$lead$body';
  final end = emptyLine ? le : at;
  return TextEditingValue(
    text: text.replaceRange(at, end, ins),
    selection: TextSelection.collapsed(offset: at + lead.length + caret),
  );
}

/// Indent width for the line at [offset]: the marker width of the nearest list line
/// above (`1. ` → 3, `10. ` → 4, `- ` → 2), else 2.
int indentWidthAt(String text, int offset) {
  var (ls, _) = lineAt(text, offset);
  final own = kLiveListLine.firstMatch(text.substring(ls, lineAt(text, ls).$2));
  final ownIndent = own?.group(1)?.length ?? -1;
  while (ls > 0) {
    final (ps, pe) = lineAt(text, ls - 1);
    final m = kLiveListLine.firstMatch(text.substring(ps, pe));
    if (m != null && (ownIndent < 0 || m.group(1)!.length <= ownIndent)) {
      return m.group(2)!.length +
          (m.group(5)!.isEmpty ? 1 : m.group(5)!.length);
    }
    ls = ps;
  }
  return 2;
}

/// Indents (or outdents) the lines the selection touches (24.15 D′14).
TextEditingValue indentField(TextEditingValue v, {required bool indent}) {
  final text = v.text;
  final sel = v.selection.isValid
      ? v.selection
      : TextSelection.collapsed(offset: text.length);
  final from = lineAt(text, sel.start).$1;
  final to = lineAt(text, sel.end).$2;
  final width = indentWidthAt(text, sel.start);
  final lines = text.substring(from, to).split('\n');
  var firstDelta = 0;
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    String next;
    if (indent) {
      next = '${' ' * width}$l';
    } else {
      var n = 0;
      while (n < width && n < l.length && l[n] == ' ') {
        n++;
      }
      if (n == 0 && l.startsWith('\t')) n = 1;
      next = l.substring(n);
    }
    if (i == 0) firstDelta = next.length - l.length;
    out.add(next);
  }
  final joined = out.join('\n');
  final delta = joined.length - (to - from);
  int clampTo(int o) => o.clamp(from, from + joined.length);
  return TextEditingValue(
    text: text.replaceRange(from, to, joined),
    selection: sel.isCollapsed
        ? TextSelection.collapsed(offset: clampTo(sel.start + firstDelta))
        : TextSelection(
            baseOffset: clampTo(sel.start + firstDelta),
            extentOffset: clampTo(sel.end + delta),
          ),
  );
}

/// The source offset (within [source]) of character [k] of [plain], the drawn text of
/// a paragraph inside [source]: the drawn text is walked against the source, skipping
/// source characters that are not drawn (markers, link targets). Only places a caret,
/// so a miss is harmless (24.4, R15). [source].length when nothing fits.
int sourceOffsetForPlain(String source, String plain, int k) {
  // Placeholders (inline math, images) are not source characters.
  final drawn = plain.replaceAll('￼', '');
  final kk = plain
      .substring(0, k.clamp(0, plain.length))
      .replaceAll('￼', '')
      .length;
  if (kk == 0) {
    // Before the first drawn character: where that character is.
    final lead = drawn.length - drawn.trimLeft().length;
    if (lead >= drawn.length) return source.length;
    final at = _walk(source, drawn.substring(0, lead + 1));
    return at == null ? source.length : at - 1;
  }
  return _walk(source, drawn.substring(0, kk)) ?? source.length;
}

/// The source offset just after [want] walked greedily (see [sourceOffsetForPlain]):
/// the start (of at most 64 where its first character occurs) with the fewest skipped
/// source characters wins. null when it cannot be walked.
int? _walk(String source, String want) {
  final c0 = want.codeUnitAt(0);
  int? best;
  var bestSkips = 1 << 30;
  var tried = 0;
  for (var s0 = 0; s0 < source.length && tried < 64; s0++) {
    if (source.codeUnitAt(s0) != c0) continue;
    tried++;
    var s = s0;
    var skips = 0;
    var ok = true;
    for (var i = 0; i < want.length; i++) {
      final c = want.codeUnitAt(i);
      // Drawn whitespace may be a source newline (soft breaks).
      while (s < source.length &&
          source.codeUnitAt(s) != c &&
          !(c == 0x20 && source.codeUnitAt(s) == 0x0A)) {
        s++;
        skips++;
      }
      if (s >= source.length || skips >= bestSkips) {
        ok = false;
        break;
      }
      s++;
    }
    if (ok && skips < bestSkips) {
      best = s;
      bestSkips = skips;
      if (skips == 0) break;
    }
  }
  return best;
}
