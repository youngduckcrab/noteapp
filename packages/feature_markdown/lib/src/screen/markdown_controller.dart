// The one owner of an open MD 문서's state (08-markdown 8.5, 8.7; B-7, B-9): the decoded
// text buffer (the editor's TextEditingController — the view draws it too, so 보기 never
// flashes an older text), the base version, dirty / save state, and the echo rules for
// incoming changes. Every change (typing, task boxes, restore) goes through the buffer and
// `saveText(baseVersion)`, so another device's text is never overwritten silently (L1).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart';

import '../edit/autosave.dart';
import '../edit/line_endings.dart';

/// Above this many UTF-16 units the editor does not open (view only — 08-markdown 8.7).
const int kMaxEditUnits = 150000;

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
    Duration debounce = const Duration(milliseconds: 700),
    Duration maxWait = const Duration(seconds: 5),
  }) {
    _scheduler = AutosaveScheduler(
      onDue: () => unawaited(save()),
      isComposing: () => text.value.composing.isValid,
      debounce: debounce,
      maxWait: maxWait,
    );
    text.addListener(_onText);
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

  /// The decoded buffer (no BOM, LF only).
  final TextEditingController text = TextEditingController();

  /// Undo / redo of the editor (session only).
  final UndoHistoryController undo = UndoHistoryController();

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
      _apply(codec.decode(d.text));
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
        // Clean buffer: take the new text, keep the cursor where it was.
        codec = incoming;
        _apply(decoded);
        base = d.textVersion;
      }
      // Dirty: keep the buffer; the next save's base check keeps the stored text as a
      // conflict copy (CORE L1).
    }
    notifyListeners();
  }

  void _apply(String value) {
    _applying = true;
    final sel = text.selection;
    int clampOffset(int o) => o.clamp(0, value.length);
    text.value = TextEditingValue(
      text: value,
      selection: sel.isValid
          ? TextSelection(
              baseOffset: clampOffset(sel.baseOffset),
              extentOffset: clampOffset(sel.extentOffset),
            )
          : const TextSelection.collapsed(offset: 0),
    );
    _lastText = value;
    _applying = false;
    revision++;
  }

  void _onText() {
    if (_applying || text.text == _lastText) return;
    _lastText = text.text;
    if (!loaded || doc == null) return;
    dirty = true;
    if (state != MdSaveState.saving) state = MdSaveState.pending;
    _scheduler.changed();
    notifyListeners();
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
    revision++;
    return flush();
  }

  /// Flips task box at [offset] of the buffer (the character between the brackets).
  /// False when that character is not a box mark any more.
  Future<bool> toggleTaskAt(int offset) async {
    final s = text.text;
    if (offset < 0 || offset >= s.length || !canEdit) return false;
    final c = s[offset];
    if (c != ' ' && c != 'x' && c != 'X') return false;
    if (offset == 0 || s[offset - 1] != '[') return false;
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
    text.removeListener(_onText);
    text.dispose();
    undo.dispose();
    super.dispose();
  }
}
