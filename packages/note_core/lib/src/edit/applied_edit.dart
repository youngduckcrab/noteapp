// lib/src/edit/applied_edit.dart — contract 00-overview 7.2.7 / CORE 4.3, 6.7.4.
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';

/// One entity's state before/after an edit. before == null: created.
@immutable
final class EntityDelta {
  const EntityDelta({
    required this.kind,
    required this.id,
    this.before,
    this.after,
  });

  final EntityKind kind;
  final String id;
  final SyncEntity? before;
  final SyncEntity? after; // after.version is set

  /// 6.7.4: 96 B per delta (256 B for a page) + the point arrays it keeps alive
  /// (once when before and after share the same array). (v2.0, m5-7/02-core 6.4.4) + the
  /// PageObject.estimatedBytes of the objects it keeps (once when the same instance).
  int get estimatedBytes {
    if (kind == EntityKind.page || before is Page || after is Page) return 256;
    var bytes = 96;
    final b = before, a = after;
    if (b is PageObject) bytes += b.estimatedBytes;
    if (a is PageObject && !identical(a, b)) bytes += a.estimatedBytes;
    final bp = b is Stroke ? b.points : null;
    final ap = a is Stroke ? a.points : null;
    if (bp != null) bytes += bp.length * 24;
    if (ap != null && !identical(ap, bp)) bytes += ap.length * 24;
    return bytes;
  }

  @override
  String toString() =>
      'EntityDelta(${kind.name} $id: '
      '${before == null
          ? 'created'
          : after?.isDeleted ?? false
          ? 'deleted'
          : 'updated'})';
}

/// A resolved, applied edit = one history step.
@immutable
final class AppliedEdit {
  const AppliedEdit({
    required this.label,
    required this.deltas,
    required this.version,
    required this.affectedPageIds,
    this.insertedPageIds = const [],
    this.insertedElementIds = const [],
  });

  final String label;
  final List<EntityDelta> deltas;
  final Hlc version; // shared by all deltas of this edit
  final Set<PageId> affectedPageIds;
  final List<PageId> insertedPageIds;
  final List<ElementId> insertedElementIds;

  bool get isEmpty => deltas.isEmpty;

  /// 6.7.4
  int get estimatedBytes => deltas.fold(0, (sum, d) => sum + d.estimatedBytes);

  @override
  String toString() =>
      'AppliedEdit($label, ${deltas.length} deltas, pages: $affectedPageIds)';
}

final class CommandReceipt {
  const CommandReceipt({required this.edit, required this.persisted});
  final AppliedEdit edit;
  final Future<void> persisted; // completes after the DB commit
}

@immutable
final class HistoryLimits {
  const HistoryLimits({this.maxSteps = 100, this.maxBytes = 64 * 1024 * 1024});

  /// CORE uses 32 MiB on web (bool.fromEnvironment('dart.library.js_interop')).
  static const HistoryLimits platformDefault =
      bool.fromEnvironment('dart.library.js_interop')
      ? HistoryLimits(maxBytes: 32 * 1024 * 1024)
      : HistoryLimits();

  final int maxSteps;
  final int maxBytes;

  @override
  bool operator ==(Object other) =>
      other is HistoryLimits &&
      other.maxSteps == maxSteps &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(maxSteps, maxBytes);
}

@immutable
final class HistoryState {
  const HistoryState({
    required this.canUndo,
    required this.canRedo,
    required this.undoDepth,
    required this.redoDepth,
    this.undoLabel,
    this.redoLabel,
    required this.retainedBytes,
  });

  static const HistoryState empty = HistoryState(
    canUndo: false,
    canRedo: false,
    undoDepth: 0,
    redoDepth: 0,
    retainedBytes: 0,
  );

  final bool canUndo, canRedo;
  final int undoDepth, redoDepth, retainedBytes;
  final String? undoLabel, redoLabel;

  @override
  bool operator ==(Object other) =>
      other is HistoryState &&
      other.canUndo == canUndo &&
      other.canRedo == canRedo &&
      other.undoDepth == undoDepth &&
      other.redoDepth == redoDepth &&
      other.retainedBytes == retainedBytes &&
      other.undoLabel == undoLabel &&
      other.redoLabel == redoLabel;

  @override
  int get hashCode => Object.hash(
    canUndo,
    canRedo,
    undoDepth,
    redoDepth,
    retainedBytes,
    undoLabel,
    redoLabel,
  );

  @override
  String toString() =>
      'HistoryState(undo: $undoDepth${undoLabel == null ? '' : ' $undoLabel'}, '
      'redo: $redoDepth${redoLabel == null ? '' : ' $redoLabel'}, $retainedBytes B)';
}

@immutable
final class UndoRedoResult {
  const UndoRedoResult({
    required this.applied,
    this.edit,
    this.skippedEntities = 0,
    this.skippedEntries = 0,
  });

  static const UndoRedoResult nothing = UndoRedoResult(applied: false);

  final bool applied;
  final AppliedEdit? edit; // what was actually written
  final int skippedEntities; // conflicted with remote changes (6.7.3)
  final int skippedEntries; // whole entries that became no-ops

  /// EDITOR scrolls to the first one
  Set<PageId> get affectedPageIds => edit?.affectedPageIds ?? const {};

  @override
  String toString() =>
      'UndoRedoResult(applied: $applied, skipped: $skippedEntities/$skippedEntries)';
}
