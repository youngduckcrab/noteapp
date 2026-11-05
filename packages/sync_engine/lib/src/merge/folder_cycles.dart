// Internal (not exported). Folder cycles after an apply group (6.7.2): two devices moving
// folders under each other offline can make a parent loop that no single device created.
// The latest move in the loop (largest {parentId, sortKey} version, ties → larger id) is
// undone by moving that folder to the top level — every device that repairs writes the same
// value, so concurrent repairs converge.
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../model/field_versions_ext.dart';
import '../model/sync_doc.dart';
import 'merge_recorder.dart';

/// The merge unit of a folder move (6.3.1).
const Set<String> kFolderMoveUnit = {'parentId', 'sortKey'};

/// One parent loop, starting at its smallest id, in parent order.
@immutable
final class FolderCycle {
  FolderCycle(List<FolderId> path) : members = List.unmodifiable(_rotate(path));

  final List<FolderId> members;

  /// Sorted ids: the same loop found from any member has the same key.
  String get key => (List.of(members)..sort()).join(',');

  static List<FolderId> _rotate(List<FolderId> path) {
    var start = 0;
    for (var i = 1; i < path.length; i++) {
      if (path[i].compareTo(path[start]) < 0) start = i;
    }
    return [...path.sublist(start), ...path.sublist(0, start)];
  }

  @override
  bool operator ==(Object other) => other is FolderCycle && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'FolderCycle(${members.join(' → ')})';
}

/// How to break one loop: move [folderId] to the top level.
@immutable
final class CycleRepair {
  const CycleRepair({
    required this.write,
    required this.folderId,
    required this.cycle,
    required this.ownMove,
  });

  /// parentId = null, fields = the whole move unit {parentId, sortKey} (sortKey re-stamped).
  final RepairWrite write;
  final FolderId folderId;
  final FolderCycle cycle;

  /// This device made the losing move (its parentId version node): repair now; otherwise the
  /// engine checks again after cycleRepairGrace.
  final bool ownMove;

  @override
  String toString() => 'CycleRepair($folderId of $cycle, own: $ownMove)';
}

final class FolderCycleDetector {
  FolderCycleDetector({required this.sync, this.maxSteps = 10000});

  final SyncStore sync;

  /// Longest parent walk.
  final int maxSteps;

  /// Folders whose state this group changed: created / taken / merged (kept wrote nothing).
  static List<FolderId> candidatesOf(
    Map<EntityRef, MergeOutcomeKind> outcomes,
  ) => [
    for (final MapEntry(:key, :value) in outcomes.entries)
      if (key.kind == EntityKind.folder && value != MergeOutcomeKind.kept)
        key.id,
  ]..sort();

  /// Cycles of one apply group's outcomes, with their repairs.
  Future<List<CycleRepair>> check(
    Map<EntityRef, MergeOutcomeKind> outcomes,
  ) async {
    final start = candidatesOf(outcomes);
    if (start.isEmpty) return const [];
    return repairsOf(await findCycles(start));
  }

  /// Loops reachable from [start] by parent links, deleted folders included. Walks every
  /// start folder one level at a time with one readVersioned per level.
  Future<List<FolderCycle>> findCycles(Iterable<FolderId> start) async {
    final cache = <FolderId, VersionedEntity?>{};
    Future<void> load(Iterable<FolderId> ids) async {
      final missing = {
        for (final id in ids)
          if (!cache.containsKey(id)) id,
      }.toList()..sort();
      if (missing.isEmpty) return;
      final rows = await sync.readVersioned([
        for (final id in missing) EntityRef(EntityKind.folder, id),
      ]);
      for (final (i, id) in missing.indexed) {
        cache[id] = rows[i];
      }
    }

    String? parentOf(FolderId id) {
      final entity = cache[id]?.entity;
      if (entity is! Folder) return null;
      final parent = entity.parentId;
      return parent == null || parent.isEmpty ? null : parent;
    }

    final firsts = {...start}.toList()..sort();
    await load(firsts);
    var walks = [for (final f in firsts) _Walk(f)];
    final found = <String, FolderCycle>{};
    for (var step = 0; walks.isNotEmpty && step < maxSteps; step++) {
      final next = <_Walk>[];
      final toLoad = <FolderId>{};
      for (final walk in walks) {
        final parent = parentOf(walk.current);
        if (parent == null) continue; // top level, or the parent row is unknown
        final at = walk.indexOf[parent];
        if (at != null) {
          final cycle = FolderCycle(walk.path.sublist(at));
          found.putIfAbsent(cycle.key, () => cycle);
          continue;
        }
        walk.add(parent);
        next.add(walk);
        toLoad.add(parent);
      }
      await load(toLoad);
      walks = next;
    }
    return found.values.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  /// The repair of each loop (rows read again; a loop with a missing row is skipped).
  Future<List<CycleRepair>> repairsOf(List<FolderCycle> cycles) async {
    final out = <CycleRepair>[];
    for (final cycle in cycles) {
      final rows = await sync.readVersioned([
        for (final id in cycle.members) EntityRef(EntityKind.folder, id),
      ]);
      if (rows.any((r) => r == null)) continue;
      VersionedEntity? loser;
      Hlc? loserVersion;
      for (final row in rows.cast<VersionedEntity>()) {
        final v = row.versions.ofUnit(kFolderMoveUnit);
        final better =
            loser == null ||
            v > loserVersion! ||
            (v == loserVersion && row.entity.id.compareTo(loser.entity.id) > 0);
        if (better) {
          loser = row;
          loserVersion = v;
        }
      }
      final row = loser!;
      out.add(
        CycleRepair(
          write: (
            entity: SyncDoc.fromEntity(row.entity)
                .withFields({'parentId': null})
                .toEntity(),
            fields: kFolderMoveUnit,
          ),
          folderId: row.entity.id,
          cycle: cycle,
          ownMove: row.versions.of('parentId').nodeId == sync.deviceNodeId,
        ),
      );
    }
    return out;
  }
}

final class _Walk {
  _Walk(FolderId first) {
    add(first);
  }

  final List<FolderId> path = [];
  final Map<FolderId, int> indexOf = {};

  FolderId get current => path.last;

  void add(FolderId id) {
    indexOf[id] = path.length;
    path.add(id);
  }
}
