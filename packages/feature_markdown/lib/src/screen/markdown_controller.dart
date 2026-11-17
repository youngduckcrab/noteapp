// The one owner of an open MD 문서's state (08-markdown 8.5, 8.7; B-7, B-9): the decoded
// text buffer (the editor's TextEditingController — the view draws it too, so 보기 never
// flashes an older text), the base version, dirty / save state, and the echo rules for
// incoming changes. Every change (typing, task boxes, restore) goes through the buffer and
// `saveText(baseVersion)`, so another device's text is never overwritten silently (L1).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart';

import '../edit/autosave.dart';
import '../edit/bounded_undo.dart';
import '../edit/line_endings.dart';

/// Above this many UTF-16 units the editor does not open (view only — 08-markdown 8.7).
const int kMaxEditUnits = 150000;

/// Flutter's TextField keeps its own, unbounded undo stack of the field (one text copy per
/// 500 ms of typing). It is not used (BoundedUndoHistory is), so once it may hold about this
/// many UTF-16 units the field gets a fresh TextEditingController with the same value,
/// which empties that stack (UndoHistory clears it when its value notifier changes).
const int kFieldHistoryUnits = 4000000;

enum MdSaveState {
  /// Nothing to save.
  saved,

  /// Changed, a save is scheduled.
  pending,

  /// A save is running.
  saving,

  /// The last save failed; the text stays in the buffer.
  failed,
}

enum MdSaveFailure { tooLarge, error }

class MarkdownController extends ChangeNotifier {
  MarkdownController({
    required this.noteId,
    required this.repository,
    required this.flushStore,
    this.onSaved,
    Duration debounce = const Duration(milliseconds: 700),
    Duration maxWait = const Duration(seconds: 5),
    BoundedUndoHistory? undo,
  }) : undo = undo ?? BoundedUndoHistory() {
    _scheduler = AutosaveScheduler(
      onDue: () => unawaited(save()),
      isComposing: () => text.value.composing.isValid,
      debounce: debounce,
      maxWait: maxWait,
    );
    _text.addListener(_onText);
    _sub = repository
        .watch(noteId)
        .listen(
          _onDoc,
          onError: (Object e, StackTrace s) {
            loadError = e;
            notifyListeners();
          },
        );
  }

  final NoteId noteId;
  final MarkdownRepository repository;

  /// `noteStore.flush()` (after a flush on app hide / pause / detach).
  final Future<void> Function() flushStore;

  /// After every successful save (the screen drops text it kept for later).
  final VoidCallback? onSaved;

  /// The decoded buffer (no BOM, LF only). The instance can change (see
  /// [kFieldHistoryUnits]); listeners of this controller are told when it does.
  TextEditingController get text => _text;
  TextEditingController _text = TextEditingController();
  final List<TextEditingController> _retired = [];
  int _fieldHistoryUnits = 0;
  Duration _fieldHistoryAt = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  /// Undo / redo of the editor (session only, capped — 08-markdown 8.7 U4).
  final BoundedUndoHistory undo;

  late final AutosaveScheduler _scheduler;
  StreamSubscription<MarkdownDoc?>? _sub;

  /// The latest document from the store (null before the first event or when missing).
  MarkdownDoc? doc;

  /// The first event came.
  bool loaded = false;

  /// The first event was null: no such MD 문서 (or not an MD 문서).
  bool missing = false;
  Object? loadError;

  LineEndingCodec codec = const LineEndingCodec(bom: false, crlf: false);
  Hlc? base;
  Hlc? _lastOwn;
  bool dirty = false;
  MdSaveState state = MdSaveState.saved;
  MdSaveFailure? failure;

  /// Set by a save that kept another device's text as a conflict copy.
  NoteId? conflictCopyId;

  /// Bumped on every buffer replacement from outside (the view re-parses).
  int revision = 0;

  String _lastText = '';
  bool _applying = false;
  bool _fromHistory = false;
  Future<bool>? _saving;
  bool _disposed = false;

  bool get tooLargeToEdit => text.text.length > kMaxEditUnits;

  /// Editing is possible now.
  bool get canEdit =>
      doc != null && !doc!.isReadOnly && !tooLargeToEdit && loadError == null;

  /// The original text of the buffer (BOM and CRLF restored). When nothing was edited this
  /// is the stored text byte for byte.
  String get encoded {
    final d = doc;
    if (d != null && !dirty && codec.decode(d.text) == text.text) return d.text;
    return codec.encode(text.text);
  }

  void _onDoc(MarkdownDoc? d) {
    if (_disposed) return;
    if (d == null) {
      missing = !loaded || doc == null;
      doc = null;
      loaded = true;
      notifyListeners();
      return;
    }
    final had = doc;
    doc = d;
    missing = false;
    final firstBody = had == null || (!had.bodyPresent && d.bodyPresent);
    if (!loaded || (firstBody && !dirty)) {
      codec = LineEndingCodec.of(d.text);
      _apply(codec.decode(d.text), keepCursor: false);
      base = d.textVersion;
      loaded = true;
      dirty = false;
      state = MdSaveState.saved;
    } else if (d.textVersion != null && d.textVersion == _lastOwn) {
      // our own save coming back
    } else {
      final incoming = LineEndingCodec.of(d.text);
      final decoded = incoming.decode(d.text);
      if (decoded == text.text) {
        base = d.textVersion;
        if (_saving == null && state != MdSaveState.failed) {
          codec = incoming;
          dirty = false;
          state = MdSaveState.saved;
          _scheduler.cancel();
        }
      } else if (!dirty && _saving == null) {
        // Clean buffer: take the new text, keep the cursor at the same place of the text
        // around it. The undo history starts again here: an undo across another device's
        // change would write the older text over it without a conflict copy.
        codec = incoming;
        _apply(decoded);
        base = d.textVersion;
      }
      // Dirty: keep the buffer; the next save's base check keeps the stored text as a
      // conflict copy (CORE L1).
    }
    notifyListeners();
  }

  /// Replaces the buffer with an outside text (load, another device). With [keepCursor]
  /// the selection is moved with the text around it: unchanged text before the change
  /// keeps its offsets, text after it shifts by the change's length.
  void _apply(String value, {bool keepCursor = true}) {
    _applying = true;
    final old = text.text;
    final sel = text.selection;
    final TextSelection next;
    if (keepCursor && sel.isValid) {
      final map = mapOffsetThroughChange(old, value);
      next = TextSelection(
        baseOffset: map(sel.baseOffset),
        extentOffset: map(sel.extentOffset),
      );
    } else {
      next = const TextSelection.collapsed(offset: 0);
    }
    text.value = TextEditingValue(text: value, selection: next);
    _lastText = value;
    _applying = false;
    undo.reset(text.value);
    revision++;
  }

  void _onText() {
    if (_applying || text.text == _lastText) return;
    _lastText = text.text;
    if (!loaded || doc == null) return;
    if (!_fromHistory) undo.record(text.value);
    _countFieldHistory();
    dirty = true;
    if (state != MdSaveState.saving) state = MdSaveState.pending;
    _scheduler.changed();
    notifyListeners();
  }

  /// Mirrors what Flutter's own field history holds (one copy per 500 ms of changes) and
  /// gives the field a fresh controller once that is large (see [kFieldHistoryUnits]).
  void _countFieldHistory() {
    final now = _clock.elapsed;
    if (now - _fieldHistoryAt < const Duration(milliseconds: 500)) return;
    _fieldHistoryAt = now;
    _fieldHistoryUnits += _text.text.length;
    if (_fieldHistoryUnits > kFieldHistoryUnits) renewField();
  }

  /// A fresh TextEditingController with the same value (and listener). Not while an IME
  /// composition is open (tried again at the next change).
  @visibleForTesting
  void renewField() {
    if (_disposed || _text.value.composing.isValid) return;
    final old = _text;
    final next = TextEditingController.fromValue(old.value)
      ..addListener(_onText);
    old.removeListener(_onText);
    _text = next;
    _fieldHistoryUnits = 0;
    // The field still holds the old one until it rebuilds: dispose it later.
    for (final r in _retired) {
      r.dispose();
    }
    _retired
      ..clear()
      ..add(old);
    notifyListeners();
  }

  /// One step back in the editor's history (saved like typing).
  void undoStep() => _fromHistoryValue(undo.undo());

  /// One step forward.
  void redoStep() => _fromHistoryValue(undo.redo());

  void _fromHistoryValue(TextEditingValue? v) {
    if (v == null || !canEdit) return;
    _fromHistory = true;
    try {
      text.value = v.copyWith(composing: TextRange.empty);
    } finally {
      _fromHistory = false;
    }
  }

  /// Replaces the buffer as one edit (task toggle, restore) and saves at once.
  Future<bool> replaceText(String value) {
    text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(
        offset: text.selection.isValid
            ? text.selection.extentOffset.clamp(0, value.length)
            : 0,
      ),
    );
    undo.record(text.value, single: true);
    revision++;
    return flush();
  }

  /// Puts back text kept from an earlier session ('저장 못 한 글' → [복원]) and saves it
  /// against [base], the version it was written on: when the document changed since, the
  /// store keeps the newer text as a conflict copy (CORE L1) instead of losing it.
  Future<bool> restoreText(String value, {required Hlc? base}) {
    this.base = base;
    return replaceText(value);
  }

  /// [버리고 나가기]: the buffer's changes are given up (nothing more is saved).
  void discard() {
    _scheduler.cancel();
    dirty = false;
    if (state != MdSaveState.saving) state = MdSaveState.saved;
    failure = null;
    _notify();
  }

  /// Flips task box at [offset] of the buffer (the character between the brackets).
  /// False when that is not a box any more (`[`, mark, `]`).
  Future<bool> toggleTaskAt(int offset) async {
    final s = text.text;
    if (offset <= 0 || offset + 1 >= s.length || !canEdit) return false;
    final c = s[offset];
    if (c != ' ' && c != 'x' && c != 'X') return false;
    if (s[offset - 1] != '[' || s[offset + 1] != ']') return false;
    final next = s.replaceRange(offset, offset + 1, c == ' ' ? 'x' : ' ');
    return replaceText(next);
  }

  /// Saves the buffer now if it changed. True when nothing is left unsaved.
  Future<bool> save() async {
    if (_disposed) return !dirty;
    final running = _saving;
    if (running != null) {
      await running;
      if (!dirty) return true;
      if (_saving != null) return _saving!;
    }
    if (!dirty && state != MdSaveState.failed) return true;
    final f = _saveOnce();
    _saving = f;
    try {
      return await f;
    } finally {
      if (identical(_saving, f)) _saving = null;
    }
  }

  Future<bool> _saveOnce() async {
    final snapshot = text.text;
    final raw = codec.encode(snapshot);
    state = MdSaveState.saving;
    _notify();
    try {
      final result = await repository.saveText(noteId, raw, baseVersion: base);
      base = result.textVersion;
      _lastOwn = result.textVersion;
      if (result.outcome == MarkdownSaveOutcome.savedWithConflictCopy) {
        conflictCopyId = result.conflictCopyId;
      }
      failure = null;
      if (text.text == snapshot) {
        dirty = false;
        state = MdSaveState.saved;
      } else {
        state = MdSaveState.pending;
        if (!_disposed) _scheduler.changed();
      }
      onSaved?.call();
      return !dirty;
    } on MarkdownTooLargeException {
      failure = MdSaveFailure.tooLarge;
      state = MdSaveState.failed;
      return false;
    } on Object catch (e) {
      debugPrint('feature_markdown: save failed: $e');
      failure = MdSaveFailure.error;
      state = MdSaveState.failed;
      return false;
    } finally {
      _notify();
    }
  }

  /// Saves at once (switch to 보기, back, dispose, app hidden), composition or not; with
  /// [store] also `noteStore.flush()`. True when nothing is left unsaved.
  Future<bool> flush({bool store = false}) async {
    _scheduler.cancel();
    var ok = true;
    for (var i = 0; i < 4; i++) {
      final running = _saving;
      if (running != null) await running;
      if (!dirty) break;
      ok = await save();
      if (!ok) break;
    }
    ok = ok && !dirty;
    if (store) {
      try {
        await flushStore();
      } on Object catch (e) {
        debugPrint('feature_markdown: store flush failed: $e');
      }
    }
    return ok;
  }

  void dismissConflictCopy() {
    conflictCopyId = null;
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduler.dispose();
    unawaited(_sub?.cancel());
    _text.removeListener(_onText);
    _text.dispose();
    for (final r in _retired) {
      r.dispose();
    }
    _retired.clear();
    undo.dispose();
    super.dispose();
  }
}

/// Maps an offset of [before] to [after] for a change between them: the common start and
/// end of both texts are unchanged, so offsets in the start stay, offsets in the end shift
/// by the length difference, offsets inside the changed part go to its start.
int Function(int) mapOffsetThroughChange(String before, String after) {
  final minLen = before.length < after.length ? before.length : after.length;
  var p = 0;
  while (p < minLen && before.codeUnitAt(p) == after.codeUnitAt(p)) {
    p++;
  }
  var q = 0;
  while (q < minLen - p &&
      before.codeUnitAt(before.length - 1 - q) ==
          after.codeUnitAt(after.length - 1 - q)) {
    q++;
  }
  final delta = after.length - before.length;
  return (int o) {
    if (o <= p) return o.clamp(0, after.length);
    if (o >= before.length - q) return (o + delta).clamp(0, after.length);
    return p;
  };
}
