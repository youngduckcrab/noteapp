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
      refs = {for (final d in edit.deltas) EntityRef(d.kind, d.id)},
      bytes = edit.estimatedBytes;

  final AppliedEdit edit;

  /// Every entity this step touches (alias bookkeeping).
  final Set<EntityRef> refs;
  Map<EntityRef, Hlc?> expected;
  Set<EntityRef> skip = const {};
  final int bytes;
}

final class EditHistory {
  EditHistory(this.limits);

  final HistoryLimits limits;
  final List<HistoryEntry> _undo = [];
  final List<HistoryEntry> _redo = [];

  /// entity → (version written by undo / redo → canonical version of the same content)
  /// (6.7.3 alias). Values are always canonical, so lookups take one step. An entity's
  /// aliases are kept while any step in the history touches it (another step may still
  /// need one after the step that wrote it left, e.g. erase, undo, new edit, undo add)
  /// and dropped with the last such step (T11).
  final Map<EntityRef, Map<Hlc, Hlc>> _alias = {};

  /// Steps (undo + redo stacks) touching each entity.
  final Map<EntityRef, int> _steps = {};
  int _bytes = 0;

  /// Entities with aliases (tests: alias clean-up).
  int get debugAliasedEntityCount => _alias.length;

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
      version == null ? null : _alias[ref]?[version] ?? version;

  /// [written] (written by undo/redo) now stands for the content of [canonicalOf].
  void alias(EntityRef ref, Hlc written, Hlc? canonicalOf) {
    final target = canonical(ref, canonicalOf);
    if (target == null || target == written) return;
    if (!_steps.containsKey(ref)) return; // no step left that could ask
    (_alias[ref] ??= {})[written] = target;
  }

  void _added(HistoryEntry e) {
    _bytes += e.bytes;
    for (final r in e.refs) {
      _steps.update(r, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  void _removed(HistoryEntry e) {
    _bytes -= e.bytes;
    for (final r in e.refs) {
      final n = (_steps[r] ?? 1) - 1;
      if (n <= 0) {
        _steps.remove(r);
        _alias.remove(r);
      } else {
        _steps[r] = n;
      }
    }
  }

  /// New local edit: clears redo, drops the oldest beyond maxSteps, then applies the
  /// byte limit (6.7.4) — the entry just pushed always stays.
  void push(AppliedEdit edit) {
    final entry = HistoryEntry(edit);
    // Count the new step first so aliases its entities still need survive the redo clear.
    _added(entry);
    _redo.forEach(_removed);
    _redo.clear();
    _undo.add(entry);
    while (_undo.length > limits.maxSteps) {
      _removed(_undo.removeAt(0));
    }
    while (_bytes > limits.maxBytes && _undo.length > 1) {
      _removed(_undo.removeAt(0));
    }
    _pruneWhenEmpty();
  }

  /// Undo applied: the top entry moves to the redo stack.
  void moveUndoTopToRedo() {
    _redo.add(_undo.removeLast());
    while (_redo.length > limits.maxSteps) {
      _removed(_redo.removeAt(0));
    }
  }

  /// Redo applied: the top entry moves back to the undo stack.
  void moveRedoTopToUndo() {
    _undo.add(_redo.removeLast());
    while (_undo.length > limits.maxSteps) {
      _removed(_undo.removeAt(0));
    }
  }

  /// The top entry became a no-op (every entity conflicted): it leaves the history.
  void dropUndoTop() {
    _removed(_undo.removeLast());
    _pruneWhenEmpty();
  }

  void dropRedoTop() {
    _removed(_redo.removeLast());
    _pruneWhenEmpty();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _alias.clear();
    _steps.clear();
    _bytes = 0;
  }

  void _pruneWhenEmpty() {
    if (_undo.isEmpty && _redo.isEmpty) {
      _alias.clear();
      _steps.clear();
      _bytes = 0;
    }
  }
}
