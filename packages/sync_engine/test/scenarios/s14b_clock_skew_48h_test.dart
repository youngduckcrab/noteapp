// S14b (9.1.2, 6.2.5 K1–K4, contract 7.2.10 v1.1). (a)(c) B starts 48 h ahead: K3 (no push,
// no apply), A untouched; once B's clock is fixed its future records wait for K4 and then
// reach A. (b) a chunk whose HLC is server time + 48 h is held on A (K1, the writer's
// nodeId) until its time comes. (d) the receiver is 2 h behind: a record at T + 23 h is
// within serverTime + 24 h but past min(T, wall) + 24 h → held, released an hour later, and
// A's later rename of the same title wins everywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

/// A delta chunk of [records] written by [node] in [scope].
ChunkWrite rawChunk(List<UpsertRecord> records, String node, String scope) {
  final payload = ChunkCodec.encode(records);
  return ChunkWrite(
    id: chunkIdOf(node, payload),
    scope: scope,
    authorNodeId: node,
    recordCount: records.length,
    format: ChunkCodec.formatVersion,
    kind: ChunkKind.delta,
    maxHlc: ChunkCodec.maxHlcOf(records).toString(),
    payload: payload,
  );
}

SyncIssue? issueOf(TestDevice d, SyncIssueCode code) {
  for (final i in d.engine.status.issues) {
    if (i.code == code) return i;
  }
  return null;
}

const String kWriter = 'c0c0c0c0c0c0c0c0';

void main() {
  syncScenario(
    'S14b (a)(c) B 48 h ahead: K3; fixed → K4 holds its records until '
    'their time, then A gets them',
    (h) {
      final a = h.device('A');
      a.createNote('on A');
      h.settle();
      final aDump = a.store.canonicalDump();
      final writes = h.server.writeCount('user-1');
      final b = h.device('B', clockOffset: const Duration(hours: 48));
      h.settle();
      final k3 = issueOf(b, SyncIssueCode.clockSkew)!;
      expect(b.engine.status.phase, SyncPhase.error);
      expect(k3.nodeId, b.store.sync.deviceNodeId);
      final note = b.createNote('on B');
      final strokes = [
        for (var i = 0; i < 10; i++)
          b.addStroke(b.pageIdsOf(note).single, seed: i),
      ];
      b.renameNote(note, 'renamed on B');
      h.elapse(const Duration(minutes: 3));
      h.settle();
      expect(h.server.writeCount('user-1'), writes, reason: 'no chunk from B');
      expect(a.store.canonicalDump(), aDump);
      expect(b.doc(EntityKind.note, note), isNotNull);

      // (c) The clock is fixed: the 5-minute recheck ends K3; the +48 h records stay (K4).
      b.clockOffset = Duration.zero;
      h.elapse(const Duration(minutes: 5));
      h.settle();
      expect(b.engine.status.phase, SyncPhase.live);
      expect(
        issueOf(b, SyncIssueCode.clockSkew)!.nodeId,
        b.store.sync.deviceNodeId,
      );
      expect(a.doc(EntityKind.note, note), isNull);
      h.elapse(const Duration(hours: 24));
      h.settle();
      expect(noteOn(a, note).title, 'renamed on B');
      expectNoLoss([a, b], strokes);
      expect(issueOf(b, SyncIssueCode.clockSkew), isNull);
      h.checkConverged([a, b]);
    },
  );

  syncScenario('S14b (b) a chunk 48 h ahead is held on A (K1) and applied when '
      'its time comes', (h) {
    final a = h.device('A');
    h.settle();
    final aDump = a.store.canonicalDump();
    final at = h.serverClock.now().add(const Duration(hours: 48));
    final hlc = Hlc(at.millisecondsSinceEpoch, 0, kWriter);
    final folder = EntityJson.decode(EntityKind.folder, {
      'id': 'folder-from-the-future',
      'ownerId': 'user-1',
      'parentId': null,
      'name': 'future',
      'sortKey': 'a0',
      'createdAt': at.millisecondsSinceEpoch,
      'updatedAt': at.millisecondsSinceEpoch,
      'deletedAt': null,
      'version': hlc.toString(),
    });
    h.server.commitRaw('user-1', [
      rawChunk(
        [UpsertRecord(SyncDoc.fromEntity(folder), EntityFieldVersions(hlc))],
        kWriter,
        'lib',
      ),
    ]);
    h.settle();
    final k1 = issueOf(a, SyncIssueCode.clockSkew)!;
    expect(k1.nodeId, kWriter);
    expect(k1.isBlocking, isTrue);
    expect(a.store.canonicalDump(), aDump);
    h.elapse(const Duration(hours: 24, minutes: 2));
    h.settle();
    expect(a.doc(EntityKind.folder, folder.id), isNotNull);
    expect(issueOf(a, SyncIssueCode.clockSkew), isNull);
  });

  syncScenario(
    'S14b (d) receiver 2 h behind: a T + 23 h record is held, released '
    "an hour later, and A's later rename wins",
    (h) {
      final a = h.device('A', clockOffset: const Duration(hours: -2));
      final b = h.device('B');
      final note = b.createNote('title');
      h.settle();
      expect(issueOf(a, SyncIssueCode.clockSkewWarning)!.isBlocking, isFalse);
      final aDump = a.store.canonicalDump();

      final t = h.serverClock.now().millisecondsSinceEpoch;
      final hlc = Hlc(t + const Duration(hours: 23).inMilliseconds, 0, kWriter);
      final row = b.store.rows[EntityRef(EntityKind.note, note)]!;
      final future = EntityJson.decode(EntityKind.note, {
        ...row.entity.toJson(),
        'title': 'from the future',
        'version': hlc.toString(),
      });
      final versions = EntityFieldVersions(row.versions.base, {
        ...row.versions.overrides,
        'title': hlc,
      });
      h.server.commitRaw('user-1', [
        rawChunk(
          [UpsertRecord(SyncDoc.fromEntity(future), versions)],
          kWriter,
          'lib',
        ),
      ]);
      h.settle();
      expect(
        noteOn(b, note).title,
        'from the future',
        reason: 'B: in its window',
      );
      final k1 = issueOf(a, SyncIssueCode.clockSkew)!;
      expect(k1.nodeId, kWriter);
      expect(a.store.canonicalDump(), aDump);

      h.elapse(const Duration(hours: 1, minutes: 2));
      h.settle();
      expect(noteOn(a, note).title, 'from the future');
      expect(issueOf(a, SyncIssueCode.clockSkew), isNull);
      a.renameNote(note, 'renamed on A');
      h.settle();
      for (final d in [a, b]) {
        expect(noteOn(d, note).title, 'renamed on A', reason: d.name);
      }
      h.checkConverged([a, b]);
    },
  );
}
