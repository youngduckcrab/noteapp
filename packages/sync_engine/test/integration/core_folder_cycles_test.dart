// T16 (integration stage, contract 7.7 step 5 v1.2 — C12-05 "폴더 순환 판정 대조"): on the
// same folder state, FolderCycleDetector.findCycles (6.7.2, over SyncStore rows) finds the
// loops CORE's FolderTree.findCycles() finds (CORE 5.4 S-4+) — the same members in the same
// order (parent order from the smallest id). FolderTree takes active folders only; the
// detector also walks through deleted folders (6.7.2), so loops with a deleted member are
// left out of the comparison. Seeded random parent graphs plus fixed cases.
@Tags(['integration'])
library;

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/folder_cycles.dart';
import 'package:sync_engine/testing.dart';

import '../support/fake_time.dart';
import '../support/merge_rig.dart';

typedef _Graph = Map<String, ({String? parent, bool deleted})>;

/// Loops of [graph] by SYNC (every folder a start: [all], and [sync] = those without a
/// deleted member) and by CORE (active folders only), as member lists, sorted.
({List<List<String>> all, List<List<String>> sync, List<List<String>> core})
_cycles(_Graph graph) {
  late List<List<String>> sync;
  late List<Folder> active;
  fakeAsync((async) {
    final store = FakeLocalStore(
      nodeId: kNodeA,
      clock: async.getClock(kMergeStart),
      ownerId: 'user-1',
    );
    store.localWrite([
      for (final MapEntry(key: id, value: f) in graph.entries)
        folderWrite(id, parentId: f.parent, deletedAt: f.deleted ? 1 : null),
    ]);
    final found = runFake(
      async,
      FolderCycleDetector(sync: store.sync).findCycles(graph.keys),
    );
    sync = [for (final c in found) c.members];
    // The same rows as CORE entities: FolderTree takes the active folders.
    active = [
      for (final row in store.rows.values)
        if (row.entity case final Folder folder when !folder.isDeleted) folder,
    ];
  });
  final core = FolderTree(active).findCycles();
  int byKey(List<String> a, List<String> b) =>
      (List.of(a)..sort()).join(',').compareTo((List.of(b)..sort()).join(','));
  bool allActive(List<String> c) => c.every((id) => !graph[id]!.deleted);
  return (
    all: [...sync]..sort(byKey),
    sync: [...sync.where(allActive)]..sort(byKey),
    core: [...core]..sort(byKey),
  );
}

_Graph _graph(Map<String, String?> parents, {Set<String> deleted = const {}}) =>
    {
      for (final MapEntry(:key, :value) in parents.entries)
        key: (parent: value, deleted: deleted.contains(key)),
    };

void main() {
  test('fixed cases: no loop, two and three folders, a tail into a loop, two '
      'loops, a missing parent', () {
    final cases = <_Graph>[
      _graph({'f1': null, 'f2': 'f1', 'f3': 'f2'}),
      _graph({'f1': 'f2', 'f2': 'f1'}),
      _graph({'f1': 'f3', 'f2': 'f1', 'f3': 'f2'}),
      _graph({'f1': 'f2', 'f2': 'f3', 'f3': 'f2', 'f4': 'f1'}),
      _graph({'a': 'b', 'b': 'a', 'c': 'd', 'd': 'e', 'e': 'c'}),
      _graph({'f1': 'gone', 'f2': 'f1'}),
    ];
    for (final g in cases) {
      final r = _cycles(g);
      expect(r.sync, r.core, reason: '$g');
    }
    expect(_cycles(cases[2]).core, [
      ['f1', 'f3', 'f2'],
    ]);
  });

  test('a loop through a deleted folder: found by SYNC only (left out of the '
      'comparison)', () {
    final g = _graph({'f1': 'f2', 'f2': 'f1', 'f3': null}, deleted: {'f2'});
    final r = _cycles(g);
    expect(r.all, [
      ['f1', 'f2'],
    ]);
    expect(r.core, isEmpty);
    expect(r.sync, isEmpty);
  });

  test('seeded random parent graphs: the same loops', () {
    for (var seed = 1; seed <= 50; seed++) {
      final random = Random(seed);
      final n = 2 + random.nextInt(12);
      final ids = [
        for (var i = 0; i < n; i++) 'f${i.toString().padLeft(2, '0')}',
      ];
      final g = <String, ({String? parent, bool deleted})>{
        for (final id in ids)
          id: (
            parent: random.nextInt(4) == 0 ? null : ids[random.nextInt(n)],
            deleted: random.nextInt(8) == 0,
          ),
      };
      // A folder is never its own parent (CORE rejects it, SYNC writes never make it).
      for (final id in ids) {
        if (g[id]!.parent == id) {
          g[id] = (parent: null, deleted: g[id]!.deleted);
        }
      }
      final r = _cycles(g);
      expect(r.sync, r.core, reason: 'seed $seed: $g');
    }
  });
}
