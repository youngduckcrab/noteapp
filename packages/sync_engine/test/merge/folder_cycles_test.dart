// T11: folder cycles (6.7.2) — detection from one apply group's outcomes, the loser (latest
// {parentId, sortKey} move, ties → larger id), the repair write, and in the engine: the
// device that made the losing move repairs at once, the other one only if the loop is still
// there after cycleRepairGrace (10 s); concurrent repairs converge.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/folder_cycles.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';
import '../support/merge_rig.dart';

/// F1 and F2 on both stores; A moves F1 under F2, then B moves F2 under F1 (later); each
/// side receives the other's move.
({Map<EntityRef, MergeOutcomeKind> atA, Map<EntityRef, MergeOutcomeKind> atB})
crossingMoves(MergeRig r) {
  r.write(r.a, [folderWrite('f1'), folderWrite('f2')]);
  r.transfer(r.a, r.b, [folderRef('f1'), folderRef('f2')]);
  r.write(r.a, [folderWrite('f1', parentId: 'f2', fields: kFolderMoveUnit)]);
  r.write(r.b, [folderWrite('f2', parentId: 'f1', fields: kFolderMoveUnit)]);
  final atA = r.transfer(r.b, r.a, [folderRef('f2')]);
  final atB = r.transfer(r.a, r.b, [folderRef('f1')]);
  return (atA: atA, atB: atB);
}

void main() {
  group('FolderCycleDetector', () {
    test('two-folder loop: found on both sides; the later move loses — own on '
        'its device, not on the other', () {
      withMergeRig((r) {
        final (:atA, :atB) = crossingMoves(r);
        expect(atA, {folderRef('f2'): MergeOutcomeKind.taken});
        final onA = r.run(FolderCycleDetector(sync: r.a.sync).check(atA));
        final onB = r.run(FolderCycleDetector(sync: r.b.sync).check(atB));
        for (final repairs in [onA, onB]) {
          final repair = repairs.single;
          expect(repair.cycle.members, ['f1', 'f2']);
          expect(repair.folderId, 'f2');
          final folder = repair.write.entity as Folder;
          expect(folder.id, 'f2');
          expect(folder.parentId, isNull);
          expect(folder.name, 'f2');
          expect(repair.write.fields, {'parentId', 'sortKey'});
        }
        expect(onA.single.ownMove, isFalse);
        expect(onB.single.ownMove, isTrue);
      });
    });

    test('three-folder loop, members from the smallest id in parent order', () {
      withMergeRig((r) {
        r.write(r.a, [folderWrite('f1'), folderWrite('f2'), folderWrite('f3')]);
        r.write(r.a, [
          folderWrite('f2', parentId: 'f3', fields: kFolderMoveUnit),
        ]);
        r.write(r.a, [
          folderWrite('f3', parentId: 'f1', fields: kFolderMoveUnit),
        ]);
        r.write(r.a, [
          folderWrite('f1', parentId: 'f2', fields: kFolderMoveUnit),
        ]);
        final detector = FolderCycleDetector(sync: r.a.sync);
        final cycles = r.run(detector.findCycles(['f3']));
        expect(cycles.single.members, ['f1', 'f2', 'f3']);
        final repair = r.run(detector.repairsOf(cycles)).single;
        expect(repair.folderId, 'f1', reason: 'the last move');
        expect(repair.ownMove, isTrue);
      });
    });

    test('a deleted folder in the loop is followed too', () {
      withMergeRig((r) {
        r.write(r.a, [folderWrite('f1'), folderWrite('f2')]);
        r.write(r.a, [
          folderWrite(
            'f2',
            parentId: 'f1',
            deletedAt: 5,
            fields: const {'parentId', 'sortKey', 'deletedAt', 'trashRootId'},
          ),
        ]);
        r.write(r.a, [
          folderWrite('f1', parentId: 'f2', fields: kFolderMoveUnit),
        ]);
        final cycles = r.run(
          FolderCycleDetector(sync: r.a.sync).findCycles(['f1']),
        );
        expect(cycles.single.members, ['f1', 'f2']);
      });
    });

    test('equal move versions (one commit): the larger id loses', () {
      withMergeRig((r) {
        r.write(r.a, [folderWrite('f1'), folderWrite('f2')]);
        r.write(r.a, [
          folderWrite('f1', parentId: 'f2', fields: kFolderMoveUnit),
          folderWrite('f2', parentId: 'f1', fields: kFolderMoveUnit),
        ]);
        final repairs = r.run(
          FolderCycleDetector(sync: r.a.sync)
              .check({folderRef('f1'): MergeOutcomeKind.merged}),
        );
        expect(repairs.single.folderId, 'f2');
      });
    });

    test('a folder leading into a loop finds the loop only; found from several '
        'members it is reported once', () {
      withMergeRig((r) {
        r.write(r.a, [folderWrite('f1'), folderWrite('f2'), folderWrite('x')]);
        r.write(r.a, [
          folderWrite('x', parentId: 'f1', fields: kFolderMoveUnit),
          folderWrite('f1', parentId: 'f2', fields: kFolderMoveUnit),
          folderWrite('f2', parentId: 'f1', fields: kFolderMoveUnit),
        ]);
        final cycles = r.run(
          FolderCycleDetector(sync: r.a.sync).findCycles(['x', 'f2', 'f1']),
        );
        expect(cycles, hasLength(1));
        expect(cycles.single.members, ['f1', 'f2']);
      });
    });

    test(
      'no loop: chains end at the top level or at an unknown parent; kept and '
      'non-folder outcomes are not candidates',
      () {
        withMergeRig((r) {
          r.write(r.a, [
            folderWrite('f1'),
            folderWrite('f2', parentId: 'f1'),
            folderWrite('f3', parentId: 'f2'),
            folderWrite('g', parentId: 'missing'),
          ]);
          final detector = FolderCycleDetector(sync: r.a.sync);
          expect(r.run(detector.findCycles(['f3', 'g'])), isEmpty);
          expect(
            FolderCycleDetector.candidatesOf({
              folderRef('f2'): MergeOutcomeKind.kept,
              folderRef('f3'): MergeOutcomeKind.created,
              folderRef('f1'): MergeOutcomeKind.taken,
              noteRef('n'): MergeOutcomeKind.taken,
            }),
            ['f1', 'f3'],
          );
          expect(
            r.run(detector.check({folderRef('f2'): MergeOutcomeKind.kept})),
            isEmpty,
          );
        });
      },
    );

    test('maxSteps bounds the walk', () {
      withMergeRig((r) {
        r.write(r.a, [
          for (var i = 0; i < 30; i++)
            folderWrite('f$i', parentId: i == 0 ? null : 'f${i - 1}'),
        ]);
        r.write(r.a, [
          folderWrite('f0', parentId: 'f29', fields: kFolderMoveUnit),
        ]);
        expect(
          r.run(
            FolderCycleDetector(
              sync: r.a.sync,
              maxSteps: 10,
            ).findCycles(['f5']),
          ),
          isEmpty,
        );
        expect(
          r
              .run(FolderCycleDetector(sync: r.a.sync).findCycles(['f5']))
              .single
              .members,
          hasLength(30),
        );
      });
    });
  });

  group('in the engine', () {
    /// A and B live with F1 and F2 synced (top level).
    (TestDevice, TestDevice, String, String) twoFolders(SyncTestHarness h) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      final f1 = a.createFolder('F1');
      final f2 = a.createFolder('F2');
      h.settle();
      expect(b.doc(EntityKind.folder, f2), isNotNull);
      return (a, b, f1, f2);
    }

    String? parentOf(TestDevice d, String id) =>
        d.doc(EntityKind.folder, id)!.json['parentId'] as String?;

    harnessTest('the device of the losing move repairs at once; the other one '
        'finds no loop after the 10 s grace', (h, async) {
      final (a, b, f1, f2) = twoFolders(h);
      final logA = EngineLog(a.engine), logB = EngineLog(b.engine);
      b.goOffline();
      h.settle();
      b.moveFolder(f2, f1); // earlier
      h.elapse(const Duration(seconds: 1));
      a.moveFolder(f1, f2); // later: the loser
      h.settle();
      b.goOnline();
      h.settle();
      h.elapse(const Duration(seconds: 11));
      h.settle();
      expect(a.engine.debug.repairsWritten, 1);
      expect(b.engine.debug.repairsWritten, 0);
      final resolved = logA.notices.whereType<FolderCycleResolved>().single;
      expect(resolved.folderId, f1);
      expect({...resolved.cycle}, {f1, f2});
      expect(logB.notices.whereType<FolderCycleResolved>(), isEmpty);
      for (final d in [a, b]) {
        expect(parentOf(d, f1), isNull);
        expect(parentOf(d, f2), f1);
      }
      h.checkConverged([a, b]);
    });

    harnessTest('the loser device away: the other one repairs after the grace; '
        'both repairs converge', (h, async) {
      final (a, b, f1, f2) = twoFolders(h);
      b.goOffline();
      h.settle();
      b.moveFolder(f2, f1);
      h.elapse(const Duration(seconds: 1));
      a.moveFolder(f1, f2); // the loser, sent
      h.settle();
      b.goOnline();
      // A repairs as soon as it applies B's move, then goes offline before its push.
      for (var i = 0; i < 300 && a.engine.debug.repairsWritten == 0; i++) {
        h.elapse(const Duration(milliseconds: 10));
      }
      expect(a.engine.debug.repairsWritten, 1);
      a.goOffline();
      h.elapse(const Duration(seconds: 11));
      h.settle();
      expect(b.engine.debug.repairsWritten, 1, reason: 'still a loop at B');
      expect(parentOf(b, f1), isNull);
      a.goOnline();
      h.settle();
      for (final d in [a, b]) {
        expect(parentOf(d, f1), isNull);
        expect(parentOf(d, f2), f1);
      }
      h.checkConverged([a, b]);
    });
  });
}
