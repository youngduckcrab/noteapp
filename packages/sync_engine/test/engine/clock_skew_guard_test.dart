// T10: the clock guard in the engine (6.2.4, 6.2.5): K3 — this device's clock off by more
// than 24 h stops uploads and remote apply (contract 7.2.10 v1.1) while local writes go on,
// re-measured every 5 min, on foreground and on a connectivity change; K4 — records ahead of
// the server time stay in the outbox; K1 — another device's future records are held with a
// clockSkew issue naming it; the 2 min … 24 h warning changes nothing else.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';

const Duration _ahead = Duration(hours: 48);

/// clockSkewRecheck (5 min) and a little more: the monotonic recheck timer has fired.
const Duration _recheck = Duration(minutes: 5, seconds: 1);

/// One chunk with every row of [device] (signed out: no engine of its own).
ChunkWrite chunkOf(TestDevice device) {
  final records = [
    for (final row in device.store.rows.values) UpsertRecord.fromVersioned(row),
  ];
  final payload = ChunkCodec.encode(records);
  final node = device.store.sync.deviceNodeId;
  var max = records.first.versions.max;
  for (final r in records) {
    if (r.versions.max > max) max = r.versions.max;
  }
  return ChunkWrite(
    id: chunkIdOf(node, payload),
    scope: 'lib',
    authorNodeId: node,
    recordCount: records.length,
    format: ChunkCodec.formatVersion,
    kind: ChunkKind.delta,
    maxHlc: max.toString(),
    payload: payload,
  );
}

void main() {
  group('K3: this device off by more than 24 h', () {
    harnessTest('fast clock: error (clockSkew, own node), nothing sent or '
        'received, local writes go on; fixed → live, own future records held '
        '(K4) until the server time catches up', (h, async) {
      final b = liveDevice(h, 'B');
      final theirs = b.createNote('from B');
      h.settle();
      final a = h.device('A', clockOffset: _ahead);
      final log = EngineLog(a.engine);
      final mine = a.createNote('written with the clock 48 h ahead');
      h.settle();
      expect(log.takePhases(), [
        SyncPhase.signedOut,
        SyncPhase.connecting,
        SyncPhase.error,
      ]);
      var status = a.engine.status;
      expect(status.display, SyncDisplayState.error);
      expect(status.clockSkew, isNotNull);
      expect(status.clockSkew! < -const Duration(hours: 47), isTrue);
      final k3 = issueOf(a, SyncIssueCode.clockSkew)!;
      expect(k3.isBlocking, isTrue);
      expect(k3.nodeId, a.store.sync.deviceNodeId);
      expect(
        status.nextRetryAt,
        inInclusiveRange(
          deviceMillis(h, a) + 299990,
          deviceMillis(h, a) + 300000,
        ),
      );
      expect(a.link.callCount(FakeOp.commit), 0);
      expect(a.link.callCount(FakeOp.fetch), 0);
      expect(a.link.callCount(FakeOp.watch), 0);
      expect(a.doc(EntityKind.note, theirs), isNull);
      expect(onServer(h, mine), isFalse);

      // Local writes go on (CORE keeps them in the outbox).
      final pending = status.pendingUploads;
      a.createNote('another one');
      h.elapse(const Duration(seconds: 1));
      expect(a.engine.status.pendingUploads, pending + 2);

      // Re-measured every 5 minutes; still off → still error.
      final probes = a.link.callCount(FakeOp.device);
      untilRetry(h, a);
      h.settle();
      expect(a.link.callCount(FakeOp.device), probes + 1);
      expect(a.engine.status.phase, SyncPhase.error);
      expect(a.link.callCount(FakeOp.commit), 0);

      // The user fixes the clock: the next measurement resumes (catchingUp → live).
      a.clockOffset = Duration.zero;
      h.elapse(_recheck); // nextRetryAt was set on the old device clock
      h.settle();
      expect(log.takePhases(), [
        SyncPhase.error,
        SyncPhase.initialSync,
        SyncPhase.live,
      ]);
      expect(a.doc(EntityKind.note, theirs), isNotNull);
      status = a.engine.status;
      expect(status.clockSkew!.abs() < const Duration(seconds: 1), isTrue);
      // The edits stamped 48 h ahead stay local (K4): clockSkew on the own node, still
      // live, display error.
      final k4 = issueOf(a, SyncIssueCode.clockSkew)!;
      expect(k4.nodeId, a.store.sync.deviceNodeId);
      expect(k4.message, contains('ahead of the server time'));
      expect(status.phase, SyncPhase.live);
      expect(status.display, SyncDisplayState.error);
      expect(status.pendingUploads, greaterThan(0));
      expect(onServer(h, mine), isFalse);

      // 24 h later (minus the 1 min margin) the server time has caught up.
      h.elapse(const Duration(hours: 24, minutes: 1));
      h.settle();
      expect(onServer(h, mine), isTrue);
      expect(issueOf(a, SyncIssueCode.clockSkew), isNull);
      expect(a.engine.status.pendingUploads, 0);
      h.checkConverged([a, b]);
    });

    harnessTest('slow clock: receiving is paused too; fixed → the other '
        "device's records are applied and the local edits go up", (h, async) {
      final b = liveDevice(h, 'B');
      final theirs = b.createNote('from B');
      h.settle();
      final a = h.device('A', clockOffset: -_ahead);
      final mine = a.createNote('written with the clock 48 h behind');
      h.settle();
      expect(a.engine.status.phase, SyncPhase.error);
      expect(a.engine.status.clockSkew! > const Duration(hours: 47), isTrue);
      expect(
        issueOf(a, SyncIssueCode.clockSkew)!.nodeId,
        a.store.sync.deviceNodeId,
      );
      expect(a.doc(EntityKind.note, theirs), isNull);
      expect(a.link.callCount(FakeOp.fetch), 0);
      a.clockOffset = Duration.zero;
      h.elapse(_recheck);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(a.engine.status.issues, isEmpty);
      expect(a.doc(EntityKind.note, theirs), isNotNull);
      expect(onServer(h, mine), isTrue);
      h.checkConverged([a, b]);
    });

    harnessTest('a connectivity change re-measures at once', (h, async) {
      final a = h.device('A', clockOffset: _ahead);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.error);
      a.clockOffset = Duration.zero;
      a.connectivity
        ..set(false)
        ..set(true);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(
        nowMillis(h) - kEngineStart.millisecondsSinceEpoch,
        lessThan(60000),
      );
    });

    harnessTest('coming back to the foreground re-measures at once', (
      h,
      async,
    ) {
      final a = h.device('A', clockOffset: -_ahead);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.error);
      a.clockOffset = Duration.zero;
      a.engine
        ..setLifecycle(SyncLifecycle.background)
        ..setLifecycle(SyncLifecycle.foreground);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(
        nowMillis(h) - kEngineStart.millisecondsSinceEpoch,
        lessThan(60000),
      );
    });
  });

  harnessTest('2 min < skew ≤ 24 h: clockSkewWarning only — not blocking, sync '
      'goes on (S14)', (h, async) {
    final b = liveDevice(h, 'B');
    final a = h.device('A', clockOffset: const Duration(hours: 1));
    final mine = a.createNote('an hour ahead');
    h.settle();
    final status = a.engine.status;
    expect(status.phase, SyncPhase.live);
    expect(status.display, SyncDisplayState.done);
    final warning = issueOf(a, SyncIssueCode.clockSkewWarning)!;
    expect(warning.isBlocking, isFalse);
    expect(status.clockSkew! < -const Duration(minutes: 59), isTrue);
    expect(b.doc(EntityKind.note, mine), isNotNull);
    h.checkConverged([a, b]);
  });

  harnessTest("K1: another device's records more than 24 h ahead are held with "
      'a clockSkew issue naming it; released when their time comes', (
    h,
    async,
  ) {
    final a = liveDevice(h, 'A');
    final c = h.device('C', signedIn: false, clockOffset: _ahead);
    final f = c.createFolder('from the future');
    h.run(c.store.sync.reassignOwner(from: kLocalOwnerId, to: 'user-1'));
    h.server.commitRaw('user-1', [chunkOf(c)]);
    h.settle();
    var status = a.engine.status;
    expect(status.phase, SyncPhase.live);
    expect(status.display, SyncDisplayState.error);
    final k1 = issueOf(a, SyncIssueCode.clockSkew)!;
    expect(k1.nodeId, c.store.sync.deviceNodeId);
    expect(a.doc(EntityKind.folder, f), isNull);
    expect(a.engine.debug.heldChunks, 1);

    h.elapse(const Duration(hours: 24, minutes: 2));
    h.settle();
    status = a.engine.status;
    expect(a.doc(EntityKind.folder, f), isNotNull);
    expect(issueOf(a, SyncIssueCode.clockSkew), isNull);
    expect(status.display, SyncDisplayState.done);
    expect(a.engine.debug.heldChunks, 0);
  });
}
