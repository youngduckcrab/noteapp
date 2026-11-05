// lib/src/repo/folder_tree.dart — contract 00-overview 7.2.9 / CORE 4.5.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../common/sort_keys.dart';
import '../model/folder.dart';

int _bySortKey(Folder a, Folder b) =>
    compareSortKeyThenId(a.sortKey, a.id, b.sortKey, b.id);

@immutable
final class FolderTree {
  FolderTree(Iterable<Folder> activeFolders)
    : _byId = {for (final f in activeFolders) f.id: f} {
    for (final f in _byId.values) {
      final parent = f.parentId;
      final key = parent != null && _byId.containsKey(parent) ? parent : null;
      (_children[key] ??= []).add(f);
    }
    for (final list in _children.values) {
      list.sort(_bySortKey);
    }
  }

  final Map<FolderId, Folder> _byId;

  /// Key null = roots (top level + orphans).
  final Map<FolderId?, List<Folder>> _children = {};

  int get length => _byId.length;

  /// Every active folder, including ones caught in a sync cycle.
  Iterable<Folder> get folders => _byId.values;

  /// Includes orphans (parent missing/deleted).
  List<Folder> get roots => List.unmodifiable(_children[null] ?? const []);

  /// Ordered by (sortKey, id).
  List<Folder> childrenOf(FolderId? parentId) {
    if (parentId != null && !_byId.containsKey(parentId)) return const [];
    return List.unmodifiable(_children[parentId] ?? const []);
  }

  Folder? byId(FolderId id) => _byId[id];

  /// Top level → id (breadcrumb); cycle-safe.
  List<Folder> pathTo(FolderId id) {
    final path = <Folder>[];
    final seen = <FolderId>{};
    FolderId? cur = id;
    while (cur != null && seen.add(cur)) {
      final f = _byId[cur];
      if (f == null) break;
      path.add(f);
      cur = f.parentId;
    }
    return path.reversed.toList(growable: false);
  }

  Set<FolderId> descendantsOf(FolderId id) {
    final out = <FolderId>{};
    final queue = <FolderId>[id];
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      for (final c in _children[cur] ?? const <Folder>[]) {
        if (c.id != id && out.add(c.id)) queue.add(c.id);
      }
    }
    return out;
  }

  bool isSelfOrDescendant(FolderId candidate, {required FolderId of}) =>
      candidate == of || descendantsOf(of).contains(candidate);

  /// Cycles among parentId links (can only appear after sync merges). For SYNC.
  List<List<FolderId>> findCycles() {
    final cycles = <List<FolderId>>[];
    final done = <FolderId>{};
    final ids = _byId.keys.toList()..sort();
    for (final start in ids) {
      if (done.contains(start)) continue;
      final order = <FolderId>[];
      final index = <FolderId, int>{};
      FolderId? cur = start;
      while (cur != null && _byId.containsKey(cur) && !done.contains(cur)) {
        final at = index[cur];
        if (at != null) {
          final cycle = order.sublist(at);
          // Deterministic rotation: start at the smallest id.
          var minI = 0;
          for (var i = 1; i < cycle.length; i++) {
            if (cycle[i].compareTo(cycle[minI]) < 0) minI = i;
          }
          cycles.add([...cycle.sublist(minI), ...cycle.sublist(0, minI)]);
          break;
        }
        index[cur] = order.length;
        order.add(cur);
        cur = _byId[cur]!.parentId;
      }
      done.addAll(order);
    }
    return cycles;
  }

  @override
  bool operator ==(Object other) {
    if (other is! FolderTree || other.length != length) return false;
    for (final e in _byId.entries) {
      if (other._byId[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      const UnorderedIterableEquality<Folder>().hash(_byId.values);

  @override
  String toString() => 'FolderTree($length folders)';
}
