// The live block editor (08-markdown 24, 24.15): one small field that edits one range of
// the rendered document in place. The screen owns one LiveEditor for its whole life —
// one TextEditingController, one FocusNode and one GlobalKey for the field, so moving
// to another block keeps the keyboard and the IME connection (24.15 U′5, D′12).
//
// Data rule (24.3, D′1, D′3): a session remembers the parsed source it opened on (`base`)
// and its range. On every field change the buffer becomes
// `base[0, start) + replacement + base[end..]` — text outside the range is the parsed
// text, character for character. Before each write the buffer must still be what the
// session wrote last (`expect`); when anything else changed it, the session closes
// without writing.
import 'package:material_ui/material_ui.dart';

import '../parse/md_model.dart';
import '../render/md_style.dart';
import '../screen/markdown_controller.dart';
import 'live_edit.dart';
import 'live_inline.dart';
import 'live_units.dart';

/// Units larger than this open the source editor instead (24.15 D′11).
const int kMaxLiveUnitChars = 20000;

/// Tables larger than this open the source editor instead: their pipe text wraps into
/// an unreadable field (24.17 L′11).
const int kMaxLiveTableChars = 4000;

/// One open block.
final class LiveSession {
  LiveSession({
    required this.layout,
    required this.range,
    required this.kind,
    required this.expect,
    this.unit,
  }) : setext = unit?.setext ?? false,
       coreStart = range.start,
       coreEnd = range.end;

  /// The parse the session opened on (its source is `base`).
  final LiveLayout layout;
  LiveRange range;
  LiveKind kind;

  /// The buffer as this session wrote it last.
  String expect;

  /// The unit it opened on (null: a new block).
  LiveUnit? unit;
  bool setext;

  /// Characters [coreStart, coreEnd) of [base]: the block(s) the field shows, without
  /// the separators a range may take along (emptying removes exactly these and the
  /// blank lines around them).
  int coreStart;
  int coreEnd;

  /// A list item's range as it opened, and the same with blank lines on both sides: the
  /// latter while its first line has no list marker (it left the list — 24.15 U′3,
  /// 24.17 L′3). Null once the range is fixed (a join, a non-item unit).
  LiveRange? itemRange;
  LiveRange? itemWide;

  /// A blank line goes after the range already (Enter made a paragraph while a text line
  /// follows directly — 24.17 L′1).
  bool spacedAfter = false;

  /// The field's text when the session opened ('' for a new block).
  String opened = '';

  String get base => layout.doc.source;
  MdDocument get doc => layout.doc;

  /// Length change of the buffer against [base] while the field holds [field].
  int delta(String field) =>
      range.replacement(field).length - (range.end - range.start);

  /// Maps an offset of [base] outside the range to the buffer (null inside it).
  int? mapOffset(int offset, String field) {
    if (offset < range.start) return offset;
    if (offset >= range.end) return offset + delta(field);
    return null;
  }
}

/// The field's controller: draws block-level looks (heading sizes, faded markers,
/// monospace code) over the source without changing it (24.5).
class LiveFieldController extends TextEditingController {
  MdStyle? style;
  LiveKind kind = LiveKind.prose;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final s = this.style;
    if (s == null || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final base = style ?? s.body;
    final faded = s.tokens.textSecondary;
    final spans = <InlineSpan>[];
    // [from, to) in [st]; the composing part is drawn in [plain] (no inline looks while
    // the IME is still composing a syllable there), underlined.
    void add(int from, int to, TextStyle st, [TextStyle? plain]) {
      if (to <= from) return;
      if (composing.isValid && composing.start < to && composing.end > from) {
        final a = composing.start.clamp(from, to);
        final b = composing.end.clamp(from, to);
        if (a > from) {
          spans.add(TextSpan(text: text.substring(from, a), style: st));
        }
        spans.add(
          TextSpan(
            text: text.substring(a, b),
            style: (plain ?? st).merge(
              const TextStyle(decoration: TextDecoration.underline),
            ),
          ),
        );
        if (to > b) spans.add(TextSpan(text: text.substring(b, to), style: st));
      } else {
        spans.add(TextSpan(text: text.substring(from, to), style: st));
      }
    }

    if (kind == LiveKind.code) {
      add(0, text.length, base);
      return TextSpan(style: base, children: spans);
    }
    TextStyle look(TextStyle line, int f) {
      if (f & LiveInline.marker != 0) return line.copyWith(color: faded);
      var st = line;
      if (f & (LiveInline.code | LiveInline.math) != 0) {
        st = st.copyWith(
          fontFamily: s.inlineCode.fontFamily,
          fontFamilyFallback: s.inlineCode.fontFamilyFallback,
          color: s.inlineCode.color,
          backgroundColor: s.inlineCode.backgroundColor,
        );
      }
      if (f & LiveInline.link != 0) st = s.link(st);
      if (f & LiveInline.bold != 0) {
        st = st.copyWith(fontWeight: FontWeight.w700);
      }
      if (f & LiveInline.italic != 0) {
        st = st.copyWith(fontStyle: FontStyle.italic);
      }
      if (f & LiveInline.strike != 0) {
        st = st.copyWith(
          decoration: TextDecoration.combine([
            if (st.decoration != null) st.decoration!,
            TextDecoration.lineThrough,
          ]),
        );
      }
      return st;
    }

    var start = 0;
    var fence = false;
    while (start <= text.length) {
      var end = text.indexOf('\n', start);
      if (end < 0) end = text.length;
      final line = text.substring(start, end);
      var lineStyle = base;
      var marker = 0;
      final fenceLine = _fenceLine.hasMatch(line);
      final code = fence || fenceLine;
      if (code) {
        lineStyle = s.codeBlock.copyWith(color: base.color);
        if (fenceLine) fence = !fence;
      } else {
        final h = _headingLine.firstMatch(line);
        if (h != null) {
          lineStyle = s.headings[h.group(1)!.length - 1];
          marker = h.group(0)!.length;
        } else {
          marker = lineMarkerLength(line);
        }
      }
      add(start, start + marker, lineStyle.copyWith(color: faded));
      if (code) {
        add(start + marker, end, lineStyle);
      } else {
        var at = start + marker;
        for (final r in liveInlineRuns(line.substring(marker))) {
          add(at, start + marker + r.start, lineStyle);
          add(
            start + marker + r.start,
            start + marker + r.end,
            look(lineStyle, r.flags),
            lineStyle,
          );
          at = start + marker + r.end;
        }
        add(at, end, lineStyle);
      }
      if (end < text.length) add(end, end + 1, lineStyle);
      if (end >= text.length) break;
      start = end + 1;
    }
    return TextSpan(style: base, children: spans);
  }
}

final RegExp _fenceLine = RegExp(r'^[ \t]*(`{3,}|~{3,})');
final RegExp _headingLine = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+|$)');

class LiveEditor extends ChangeNotifier {
  LiveEditor(this.c) {
    field.addListener(_onField);
    focus.addListener(_onFocus);
  }

  final MarkdownController c;
  final LiveFieldController field = LiveFieldController();
  final FocusNode focus = FocusNode(debugLabel: 'md live field');

  /// Keeps the field's state (and the IME connection) when it moves between blocks.
  final GlobalKey fieldKey = GlobalKey(debugLabel: 'md live field');

  LiveSession? session;
  bool _setting = false;

  /// Writes refused because the buffer had changed under the session (tests).
  @visibleForTesting
  int aborts = 0;

  /// The field had focus once (the toolbar shows while a session is open).
  bool focused = false;

  bool get isOpen => session != null;

  /// Opens [unit] of [layout] (whose source must be the buffer) with the caret at
  /// [caret] (an offset of the unit's text; null = its end). False when it cannot.
  bool open(LiveLayout layout, LiveUnit unit, {int? caret}) {
    if (!_canOpen(layout)) return false;
    if (unit.end - unit.start > kMaxLiveUnitChars) return false;
    final text = layout.doc.source.substring(unit.start, unit.end);
    final session = LiveSession(
      layout: layout,
      range: LiveRange(start: unit.start, end: unit.end),
      kind: unit.kind,
      expect: c.text.text,
      unit: unit,
    )..opened = text;
    if (unit.item != null) {
      session
        ..itemRange = session.range
        ..itemWide = _itemWide(layout, unit);
    }
    _start(
      session,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: (caret ?? text.length).clamp(0, text.length),
        ),
      ),
    );
    return true;
  }

  /// Opens a new, empty block at the end of the document (or in an empty one).
  bool openAtEnd(LiveLayout layout) {
    final blocks = layout.doc.blocks;
    final last = blocks.isEmpty ? -1 : blocks.last.end;
    return openNew(layout, pendingAtEnd(layout.doc.source, last));
  }

  /// Opens a new, empty block at [range] (a pending range of [layout]'s source).
  bool openNew(LiveLayout layout, LiveRange range) {
    if (!_canOpen(layout)) return false;
    _start(
      LiveSession(
        layout: layout,
        range: range,
        kind: LiveKind.prose,
        expect: c.text.text,
      ),
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    return true;
  }

  /// [unit]'s range with blank lines in front (not the first item) and after (not the
  /// last item) where it has single line breaks: what the range becomes while the item
  /// has no marker, so it stands apart from the items around it.
  static LiveRange _itemWide(LiveLayout layout, LiveUnit unit) {
    final spans = layout.items[unit.block]!;
    final item = unit.item!;
    final base = layout.doc.source;
    var r = LiveRange(start: unit.start, end: unit.end);
    final st = unit.start;
    final en = unit.end;
    if (item > 0 &&
        st >= 1 &&
        base.codeUnitAt(st - 1) == 0x0A &&
        !(st >= 2 && base.codeUnitAt(st - 2) == 0x0A)) {
      r = r.copyWith(start: st - 1, before: '\n\n');
    }
    if (item < spans.length - 1 &&
        en + 1 < base.length &&
        base.codeUnitAt(en) == 0x0A &&
        base.codeUnitAt(en + 1) != 0x0A) {
      r = r.copyWith(end: en + 1, after: '\n\n');
    }
    return r;
  }

  bool _canOpen(LiveLayout layout) =>
      c.canEdit && layout.doc.source == c.text.text;

  void _start(LiveSession s, TextEditingValue v) {
    c.undo.seal();
    c.liveHold = true;
    session = s;
    field.kind = s.kind;
    _setting = true;
    field.value = v;
    _setting = false;
    notifyListeners();
  }

  void _onFocus() {
    if (focus.hasFocus && !focused) {
      focused = true;
      notifyListeners();
    }
  }

  void _onField() {
    if (_setting) return;
    _write();
  }

  /// Writes the field into the buffer (24.3).
  void _write() {
    final s = session;
    if (s == null) return;
    final buf = c.text;
    if (buf.text != s.expect) {
      _abort('the buffer changed under the open block');
      return;
    }
    final f = field.value;
    final item = s.itemRange;
    if (item != null) {
      final first = f.text.substring(0, lineAt(f.text, 0).$2);
      s.range = f.text.isNotEmpty && !startsListItem(first)
          ? s.itemWide!
          : item;
    }
    final composed = composeLive(s.base, s.range, f.text);
    final off = s.range.fieldOffset(f.text);
    final len = composed.length;
    int at(int o) => (o + off).clamp(0, len);
    final sel = f.selection.isValid
        ? TextSelection(
            baseOffset: at(f.selection.baseOffset),
            extentOffset: at(f.selection.extentOffset),
          )
        : TextSelection.collapsed(offset: at(f.text.length));
    final comp = f.composing.isValid && f.composing.end <= f.text.length
        ? TextRange(start: at(f.composing.start), end: at(f.composing.end))
        : TextRange.empty;
    s.expect = composed;
    buf.value = TextEditingValue(
      text: composed,
      selection: sel,
      composing: comp,
    );
  }

  void _abort(String why) {
    aborts++;
    debugPrint('feature_markdown: live block closed without writing: $why');
    _end();
    focus.unfocus();
    notifyListeners();
  }

  void _end() {
    session = null;
    focused = false;
    c.undo.seal();
    c.liveHold = false;
  }

  /// Closes the open block (its text is in the buffer already). A last line that is only
  /// a list / quote marker this session added goes (Enter, then 완료). An emptied block
  /// takes the blank lines around it along (the user deleted the block); the blocks on
  /// both sides stay apart. The caller re-parses. [keepFocus]: another block opens right
  /// away (the keyboard stays). [tidy]: false when the buffer must not change any more
  /// (read-only, history).
  void close({bool keepFocus = false, bool tidy = true}) {
    final s = session;
    if (s == null) return;
    if (tidy && c.canEdit && c.text.text == s.expect) {
      _dropAddedMarkerLine(s);
      if (!s.range.pending && field.text.isEmpty && c.text.text == s.expect) {
        final u = s.unit;
        final item =
            s.itemRange != null &&
            u != null &&
            u.item! < s.layout.items[u.block]!.length - 1;
        s
          ..itemRange = null
          ..range = emptiedRange(s.base, s.coreStart, s.coreEnd, item: item);
        _write();
      }
    }
    _end();
    if (!keepFocus) focus.unfocus();
    notifyListeners();
  }

  void _dropAddedMarkerLine(LiveSession s) {
    if (s.kind != LiveKind.prose) return;
    final text = field.text;
    final nl = text.lastIndexOf('\n');
    if (nl < 0) return;
    final last = text.substring(nl + 1);
    if (!isBareMarkerLine(last)) return;
    if (s.opened.endsWith('\n$last')) return;
    _setting = true;
    field.value = TextEditingValue(
      text: text.substring(0, nl),
      selection: TextSelection.collapsed(offset: nl),
    );
    _setting = false;
    _write();
  }

  /// Runs a toolbar / key edit on the field: the IME composition is finished first, the
  /// edit is one undo step (24.15 U′7, D′10).
  void apply(TextEditingValue Function(TextEditingValue v) edit) {
    if (session == null) return;
    final v = field.value.copyWith(composing: TextRange.empty);
    final next = edit(v);
    c.undo.seal();
    if (next.text == field.text) {
      field.value = next.copyWith(composing: TextRange.empty);
    } else {
      field.value = next;
    }
    c.undo.seal();
  }

  /// Enter made a new paragraph inside the field (a large document, a split that cannot
  /// happen — 24.17 L′1, L′2): a text line right after the range gets a blank line in
  /// front, so the new paragraph does not run into it; on a setext title the paragraph
  /// goes after the underline. The field's value to use instead, or null.
  TextEditingValue? paragraphInField(TextEditingValue old) {
    final s = session;
    if (s == null) return null;
    if (!s.spacedAfter &&
        !s.range.pending &&
        s.itemRange == null &&
        s.range.after.isEmpty &&
        textOnNextLine(s.base, s.range.end)) {
      s
        ..range = s.range.copyWith(after: '\n')
        ..spacedAfter = true;
    }
    if (s.setext) {
      final t = old.text;
      final le = lineAt(t, old.selection.start).$2;
      if (le < t.length) {
        final out = '$t\n\n';
        return TextEditingValue(
          text: out,
          selection: TextSelection.collapsed(offset: out.length),
        );
      }
    }
    return null;
  }

  /// Shift+Enter.
  void shiftEnter() {
    final s = session;
    if (s == null) return;
    apply((v) => liveShiftEnter(v, s.kind));
  }

  /// Backspace with the caret at the start of the field (or [블록 합치기]): removes the
  /// first line's marker, else joins with the block before (24.4, 24.15 U′3, D′9).
  /// Returns an offset of the buffer to move to when the block cannot be joined (the
  /// caller closes this one and opens the block there), or null.
  int? backspaceAtStart() {
    final s = session;
    if (s == null) return null;
    final strip = s.kind == LiveKind.prose
        ? stripFirstMarker(field.value)
        : null;
    if (strip != null) {
      // A list item that loses its marker stands apart (_write widens its range).
      c.undo.seal();
      field.value = strip.$1;
      c.undo.seal();
      return null;
    }
    // Join with the unit before.
    final prev = _unitBefore(s);
    if (prev == null) return null;
    if (s.range.pending && field.text.isEmpty) {
      // An empty new block goes; the caret goes back to the block before.
      close(keepFocus: true);
      return prev.end;
    }
    final joinable =
        s.kind == LiveKind.prose &&
        prev.kind == LiveKind.prose &&
        !prev.setext &&
        !s.setext &&
        !prev.definition;
    if (!joinable) {
      if (field.text.isEmpty) {
        // An empty block after a code block: it goes, the caret goes back.
        close(keepFocus: true);
        return prev.end;
      }
      return null;
    }
    final prevText = s.base.substring(prev.start, prev.end);
    // The range now runs from the block before to this one's end; what was between
    // (blank lines, a widened item's separators) goes — that is the join.
    s
      ..range = LiveRange(
        start: prev.start,
        end: s.range.end,
        after: s.range.pending ? '' : s.range.after,
      )
      ..coreStart = prev.start
      ..coreEnd = s.coreEnd < prev.end ? prev.end : s.coreEnd
      ..itemRange = null
      ..unit = prev
      ..setext = false
      ..opened = '$prevText${s.opened}';
    c.undo.seal();
    final joined = '$prevText${field.text}';
    if (joined == field.text) {
      _write();
    } else {
      field.value = TextEditingValue(
        text: joined,
        selection: TextSelection.collapsed(offset: prevText.length),
      );
    }
    c.undo.seal();
    return null;
  }

  LiveUnit? _unitBefore(LiveSession s) {
    LiveUnit? best;
    for (final u in s.layout.units) {
      if (u.end <= s.range.start && (s.range.pending || u != s.unit)) {
        best = u;
      } else if (u.start >= s.range.start) {
        break;
      }
    }
    return best;
  }

  @override
  void dispose() {
    field.removeListener(_onField);
    focus.removeListener(_onFocus);
    if (session != null) _end();
    field.dispose();
    focus.dispose();
    super.dispose();
  }
}
