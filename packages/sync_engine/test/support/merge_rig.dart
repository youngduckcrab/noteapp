// Two fake local stores on fakeAsync time for the T11 checks: rows move between them as
// applyRemote with the SYNC policy, recorded by a MergeRecorder like an apply group.
import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'fake_time.dart';

const String kNodeA = 'aaaaaaaaaaaaaaaa';
const String kNodeB = 'bbbbbbbbbbbbbbbb';
const String kNodeC = 'cccccccccccccccc';

final DateTime kMergeStart = DateTime.utc(2026, 11, 1);

EntityRef folderRef(String id) => EntityRef(EntityKind.folder, id);
EntityRef noteRef(String id) => EntityRef(EntityKind.note, id);
EntityRef pageRef(String id) => EntityRef(EntityKind.page, id);
EntityRef strokeRef(String id) => EntityRef(EntityKind.stroke, id);

FakeLocalWrite folderWrite(
  String id, {
  String? parentId,
  Object? deletedAt,
  Set<String> fields = const {kAllFields},
}) => FakeLocalWrite(EntityKind.folder, {
  'id': id,
  'ownerId': 'user-1',
  'parentId': parentId,
  'name': id,
  'color': null,
  'icon': null,
  'sortKey': 'a0',
  'createdAt': 1,
  'deletedAt': deletedAt,
  'trashRootId': deletedAt == null ? null : id,
}, changedFields: fields);

final class MergeRig {
  MergeRig(this.async) {
    final clock = async.getClock(kMergeStart);
    a = FakeLocalStore(nodeId: kNodeA, clock: clock, ownerId: 'user-1');
    b = FakeLocalStore(nodeId: kNodeB, clock: clock, ownerId: 'user-1');
    c = FakeLocalStore(nodeId: kNodeC, clock: clock, ownerId: 'user-1');
  }

  final FakeAsync async;
  late final FakeLocalStore a, b, c;

  T run<T>(Future<T> future) => runFake(async, future);

  /// A local write on [store], 1 ms after the previous one (distinct HLC millis).
  void write(FakeLocalStore store, List<FakeLocalWrite> writes) {
    async.elapse(const Duration(milliseconds: 1));
    store.localWrite(writes);
  }

  /// Applies [refs] of [from] (their current rows) to [to] in one applyRemote call; returns
  /// the outcomes as MergeRecorder records them.
  Map<EntityRef, MergeOutcomeKind> transfer(
    FakeLocalStore from,
    FakeLocalStore to,
    List<EntityRef> refs, {
    Map<EntityRef, VersionedEntity>? rows,
  }) {
    final recorder = MergeRecorder()..beginCall();
    run(
      to.sync.applyRemote([
        for (final ref in refs)
          UpsertRecord.fromVersioned((rows ?? from.rows)[ref]!)
              .toRemoteChange(),
      ], policy: recorder.wrap(SyncMergePolicy.decide)),
    );
    recorder.commitCall();
    return recorder.outcomes;
  }

  /// Acknowledges the whole outbox of [store] (as if it had been sent).
  void ackAll(FakeLocalStore store) =>
      run(store.sync.acknowledge([for (final e in store.outbox) e.ack]));
}

void withMergeRig(void Function(MergeRig r) body) =>
    fakeAsync((async) => body(MergeRig(async)), initialTime: kMergeStart);
