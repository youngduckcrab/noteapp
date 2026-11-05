// Internal: per-session undo history (CORE 6.7). Memory only.
import '../common/hlc.dart';
import '../sync/outbox_types.dart';
import 'applied_edit.dart';

/// One history step. [expected] holds, per entity, the canonical version the entity must
/// still have for this step to apply (undo stack: the edit's after versions; redo stack:
/// the versions written by the undo). Entities in [skip] conflicted earlier and are skipped.
final class HistoryEntry {
  HistoryEntry(this.edit)
    : expected = {
        for (final d in edit.deltas) EntityRef(d.kind, d.id): d.after?.version,
      },
      bytes = edit.estimatedBytes;

  final AppliedEdit edit;
  Map<EntityRef, Hlc?> expected;
  Set<EntityRef> skip = const {};
  final int bytes;
}

final class EditHistory {
  EditHistory(this.limits);

  final HistoryLimits limits;
  final List<HistoryEntry> _undo = [];
  final List<HistoryEntry> _redo = [];

  /// (entity, version written by undo / redo) → canonical version of the same content
  /// (6.7.3 alias). Values are always canonical, so lookups take one step.
  final Map<(EntityRef, Hlc), Hlc> _alias = {};
  int _bytes = 0;

  HistoryState get state => HistoryState(
    canUndo: _undo.isNotEmpty,
    canRedo: _redo.isNotEmpty,
    undoDepth: _undo.length,
    redoDepth: _redo.length,
    undoLabel: _undo.isEmpty ? null : _undo.last.edit.label,
    redoLabel: _redo.isEmpty ? null : _redo.last.edit.label,
    retainedBytes: _bytes,
  );

  HistoryEntry? get undoTop => _undo.isEmpty ? null : _undo.last;
  HistoryEntry? get redoTop => _redo.isEmpty ? null : _redo.last;

  Hlc? canonical(EntityRef ref, Hlc? version) =>
      version == null ? null : _alias[(ref, version)] ?? version;

  /// [written] (written by undo/redo) now stands for the content of [canonicalOf].
  void alias(EntityRef ref, Hlc written, Hlc? canonicalOf) {
    final target = canonical(ref, canonicalOf);
    if (target == null || target == written) return;
    _alias[(ref, written)] = target;
  }

  /// New local edit: clears redo, drops the oldest beyond maxSteps, then applies the
  /// byte limit (6.7.4) — the entry just pushed always stays.
  void push(AppliedEdit edit) {
    for (final e in _redo) {
      _bytes -= e.bytes;
    }
    _redo.clear();
    final entry = HistoryEntry(edit);
    _undo.add(entry);
    _bytes += entry.bytes;
    while (_undo.length > limits.maxSteps) {
      _bytes -= _undo.removeAt(0).bytes;
    }
    while (_bytes > limits.maxBytes && _undo.length > 1) {
      _bytes -= _undo.removeAt(0).bytes;
    }
    _pruneWhenEmpty();
  }

  /// Undo applied: the top entry moves to the redo stack.
  void moveUndoTopToRedo() {
    _redo.add(_undo.removeLast());
    while (_redo.length > limits.maxSteps) {
      _bytes -= _redo.removeAt(0).bytes;
    }
  }

  /// Redo applied: the top entry moves back to the undo stack.
  void moveRedoTopToUndo() {
    _undo.add(_redo.removeLast());
    while (_undo.length > limits.maxSteps) {
      _bytes -= _undo.removeAt(0).bytes;
    }
  }

  /// The top entry became a no-op (every entity conflicted): it leaves the history.
  void dropUndoTop() {
    _bytes -= _undo.removeLast().bytes;
    _pruneWhenEmpty();
  }

  void dropRedoTop() {
    _bytes -= _redo.removeLast().bytes;
    _pruneWhenEmpty();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _alias.clear();
    _bytes = 0;
  }

  // Aliases are shared by every step that touched the entity, so they are kept while any
  // step is left and dropped together when the history becomes empty.
  void _pruneWhenEmpty() {
    if (_undo.isEmpty && _redo.isEmpty) {
      _alias.clear();
      _bytes = 0;
    }
  }
}
