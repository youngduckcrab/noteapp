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
import 'live_units.dart';

/// Units larger than this open the source editor instead (24.15 D′11).
const int kMaxLiveUnitChars = 20000;

/// One open block.
final class LiveSession {
  LiveSession({
    required this.layout,
    required this.range,
    required this.kind,
    required this.expect,
    this.unit,
  }) : setext = unit?.setext ?? false;

  /// The parse the session opened on (its source is `base`).
  final LiveLayout layout;
  LiveRange range;
  LiveKind kind;

  /// The buffer as this session wrote it last.
  String expect;

  /// The unit it opened on (null: a new block).
  LiveUnit? unit;
  bool setext;

  /// The list item's separators were widened already (24.15 U′3).
  bool widened = false;

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
    void add(int from, int to, TextStyle st) {
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
            style: st.merge(
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
    var start = 0;
    var fence = false;
    while (start <= text.length) {
      var end = text.indexOf('\n', start);
      if (end < 0) end = text.length;
      final line = text.substring(start, end);
      var lineStyle = base;
      var marker = 0;
      final fenceLine = RegExp(r'^[ \t]*(`{3,}|~{3,})').hasMatch(line);
      if (fence || fenceLine) {
        lineStyle = s.codeBlock.copyWith(color: base.color);
        if (fenceLine) fence = !fence;
      } else {
        final h = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+|$)').firstMatch(line);
        if (h != null) {
          lineStyle = s.headings[h.group(1)!.length - 1];
          marker = h.group(0)!.length;
        } else {
          marker = lineMarkerLength(line);
        }
      }
      add(start, start + marker, lineStyle.copyWith(color: faded));
      add(start + marker, end, lineStyle);
      if (end < text.length) add(end, end + 1, lineStyle);
      if (end >= text.length) break;
      start = end + 1;
    }
    return TextSpan(style: base, children: spans);
  }
}

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
    _start(
      LiveSession(
        layout: layout,
        range: LiveRange(start: unit.start, end: unit.end),
        kind: unit.kind,
        expect: c.text.text,
        unit: unit,
      ),
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
    if (!_canOpen(layout)) return false;
    final blocks = layout.doc.blocks;
    final last = blocks.isEmpty ? -1 : blocks.last.end;
    _start(
      LiveSession(
        layout: layout,
        range: pendingAtEnd(layout.doc.source, last),
        kind: LiveKind.prose,
        expect: c.text.text,
      ),
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
    return true;
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

  /// Closes the open block (its text is in the buffer already). An emptied block takes
  /// the blank lines in front of it along (the user deleted the block). The caller
  /// re-parses. [keepFocus]: another block opens right away (the keyboard stays).
  /// [tidy]: false when the buffer must not change any more (read-only, history).
  void close({bool keepFocus = false, bool tidy = true}) {
    final s = session;
    if (s == null) return;
    if (tidy &&
        c.canEdit &&
        !s.range.pending &&
        field.text.isEmpty &&
        c.text.text == s.expect) {
      final base = s.base;
      var a = s.range.start;
      var b = s.range.end;
      if (a > 0) {
        while (a > 0 && base.codeUnitAt(a - 1) == 0x0A) {
          a--;
        }
      } else {
        while (b < base.length && base.codeUnitAt(b) == 0x0A) {
          b++;
        }
      }
      if (a != s.range.start || b != s.range.end) {
        s.range = LiveRange(start: a, end: b);
        _write();
      }
    }
    _end();
    if (!keepFocus) focus.unfocus();
    notifyListeners();
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
      final item = s.unit?.item;
      if (item != null && !s.widened) {
        final spans = s.layout.items[s.unit!.block]!;
        final base = s.base;
        var r = s.range;
        final st = r.start;
        final en = r.end;
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
        s.range = r;
        s.widened = true;
      }
      c.undo.seal();
      field.value = strip.$1;
      c.undo.seal();
      return null;
    }
    // Join with the unit before.
    final prev = _unitBefore(s);
    if (prev == null) return null;
    final joinable =
        s.kind == LiveKind.prose &&
        prev.kind == LiveKind.prose &&
        !prev.setext &&
        !s.setext &&
        !prev.definition;
    if (!joinable) {
      if (field.text.isEmpty && !s.range.pending) {
        // An empty block after a code block: it goes, the caret goes back.
        close(keepFocus: true);
        return prev.end;
      }
      if (field.text.isEmpty && s.range.pending) {
        close(keepFocus: true);
        return prev.end;
      }
      return null;
    }
    final prevText = s.base.substring(prev.start, prev.end);
    s.range = LiveRange(
      start: prev.start,
      end: s.range.end,
      after: s.range.after,
    );
    s.unit = prev;
    s.widened = true;
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
