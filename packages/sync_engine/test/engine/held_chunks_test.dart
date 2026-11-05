// Held chunks (6.2.5 K1/K2, `sync.held` 6.6.6): DownloadPipeline holds records written by a
// clock more than 24 h ahead, releases them with g' = min(serverNow, wall), forgets chunks
// deleted by compaction and goes back with the cursor for the collapsed form.
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/engine/held_chunks.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/download_rig.dart';
import '../support/local_writes.dart';

const Duration day = Duration(hours: 24);

/// A store on node C whose clock runs [ahead] of the rig's base clock.
FakeLocalStore aheadStore(DownloadRig r, Duration ahead) => FakeLocalStore(
  nodeId: nodeC,
  clock: Clock(() => r.base.now().add(ahead)),
  ownerId: uid,
);

UpsertRecord noteOf(FakeLocalStore s, String id) =>
    DownloadRig.recordOf(s, EntityKind.note, id);

void main() {
  group('K1 hold', () {
    test('a record more than 24 h ahead of min(serverTime, wall) is held; '
        'the other record of the chunk is applied and the cursor moves', () {
      withDownloadRig((r) {
        final c = aheadStore(r, const Duration(hours: 48))
          ..localWrite([noteWrite('future')]);
        r.b.localWrite([noteWrite('now')]);
        final future = noteOf(c, 'future');
        final chunk = r.commit([noteOf(r.b, 'now'), future], author: nodeC);
        r.connect();
        final result = r.catchUp();
        expect(result.held, 1);
        expect(result.applied, 1);
        expect(r.hasRow(EntityKind.note, 'now'), isTrue);
        expect(r.hasRow(EntityKind.note, 'future'), isFalse);
        final releaseAt = future.versions.max.millis - day.inMilliseconds;
        expect(r.pipeline.held.entries, {chunk.id: releaseAt});
        expect(jsonDecode(r.a.meta['sync.held']!), {chunk.id: releaseAt});
        expect(
          r.sync.applyMetaUpdates.last['sync.held'],
          isNotNull,
          reason: 'same transaction as the applied record',
        );
        expect(r.pipeline.held.authorNodes, {nodeC}, reason: 'clockSkew');
        expect(r.pipeline.cursor, chunk.serverTime);

        // A restart reads it back.
        r.pipeline = r.newPipeline();
        r.run(r.pipeline.load());
        expect(r.pipeline.held.entries, {chunk.id: releaseAt});
      });
    });

    test('the reference is min(serverTime, wall): a receiver whose clock is '
        'late holds a record that is within serverTime + 24 h', () {
      void receive({required Duration receiverOffset, required bool held}) {
        withDownloadRig((r) {
          r.aOffset = receiverOffset;
          final c = aheadStore(r, const Duration(hours: 23))
            ..localWrite([noteWrite('ahead')]);
          r.commit([noteOf(c, 'ahead')], author: nodeC);
          r.connect();
          final result = r.catchUp();
          expect(result.held, held ? 1 : 0, reason: '$receiverOffset');
          expect(r.hasRow(EntityKind.note, 'ahead'), !held);
        });
      }

      receive(receiverOffset: Duration.zero, held: false);
      receive(receiverOffset: const Duration(hours: 2), held: false);
      receive(receiverOffset: const Duration(hours: -2), held: true);
    });

    test('limit boundary: max == g + 24 h is applied, + 1 ms is held', () {
      withDownloadRig((r) {
        r.connect();
        final serverMillis = r.base.now().millisecondsSinceEpoch;
        UpsertRecord at(String id, int millis) {
          final c = FakeLocalStore(
            nodeId: nodeC,
            clock: Clock.fixed(
              DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
            ),
            ownerId: uid,
          )..localWrite([noteWrite(id)]);
          return noteOf(c, id);
        }

        final edge = at('edge', serverMillis + day.inMilliseconds);
        final over = at('over', serverMillis + day.inMilliseconds + 1);
        r.commit([edge, over], author: nodeC);
        final result = r.catchUp();
        expect(result.applied, 1);
        expect(result.held, 1);
        expect(r.hasRow(EntityKind.note, 'edge'), isTrue);
        expect(r.hasRow(EntityKind.note, 'over'), isFalse);
      });
    });
  });

  group('K2 release', () {
    test('released when min(serverNow, wall) reaches releaseAt (− 1 ms '
        'stays); applied, sync.held emptied, issue gone', () {
      withDownloadRig((r) {
        final c = aheadStore(r, const Duration(hours: 48))
          ..localWrite([noteWrite('future')]);
        r.b.localWrite([noteWrite('now')]);
        final future = noteOf(c, 'future');
        final chunk = r.commit([noteOf(r.b, 'now'), future], author: nodeC);
        r.connect();
        r.catchUp();
        final releaseAt = future.versions.max.millis - day.inMilliseconds;

        r.noSample = true;
        r.async.elapse(day + const Duration(hours: 1));
        expect(r.release().chunks, 0, reason: 'no server-time sample');
        expect(r.link.callCount(FakeOp.byId), 0);

        r.noSample = false;
        r.serverNowOverride = releaseAt - 1;
        expect(r.release().chunks, 0);
        expect(r.pipeline.held.entries, {chunk.id: releaseAt});

        r.serverNowOverride = releaseAt;
        final released = r.release();
        expect(released.chunks, 1);
        expect(released.applied, 2);
        expect(r.groups.last, {
          noteOf(r.b, 'now').ref: MergeOutcomeKind.kept,
          future.ref: MergeOutcomeKind.created,
        });
        expect(r.hasRow(EntityKind.note, 'future'), isTrue);
        expect(r.pipeline.held.isEmpty, isTrue);
        expect(r.pipeline.held.authorNodes, isEmpty);
        expect(r.a.meta['sync.held'], '{}');
      });
    });

    test(
      'the wall clock bounds the release too: g\' = min(serverNow, wall)',
      () {
        withDownloadRig((r) {
          final c = aheadStore(r, const Duration(hours: 48))
            ..localWrite([noteWrite('future')]);
          final future = noteOf(c, 'future');
          r.commit([future], author: nodeC);
          r.connect();
          r.catchUp();
          final releaseAt = future.versions.max.millis - day.inMilliseconds;
          r.async.elapse(day + const Duration(hours: 1));
          r.serverNowOverride = releaseAt + 1000;
          r.aOffset = const Duration(hours: -2);
          expect(r.release().chunks, 0, reason: 'wall is behind releaseAt');
          r.aOffset = Duration.zero;
          expect(r.release().applied, 1);
        });
      },
    );
  });

  group('held chunk deleted by compaction (SYNC-2-4)', () {
    test('missing from getChunks → leaves sync.held; the snapshot that holds '
        'the record is judged by K1 again (still ahead → held under its id)', () {
      withDownloadRig((r) {
        final c = aheadStore(r, const Duration(hours: 48))
          ..localWrite([noteWrite('future')]);
        final future = noteOf(c, 'future');
        final original = r.commit([future], author: nodeC);
        r.connect();
        r.catchUp();
        final releaseAt = future.versions.max.millis - day.inMilliseconds;

        // Another device compacts: snapshot with the record, original deleted.
        r.async.elapse(const Duration(hours: 1));
        final snapshot = r.commit(
          [future],
          author: nodeB,
          kind: ChunkKind.snapshot,
        );
        r.run(r.backend.deleteChunks([original.id]));
        expect(r.catchUp().held, 1);
        expect(r.pipeline.held.entries, {
          original.id: releaseAt,
          snapshot.id: releaseAt,
        });

        r.async.elapse(day);
        final released = r.release();
        expect(released.chunks, 1, reason: 'only the snapshot came back');
        expect(released.applied, 1);
        expect(r.hasRow(EntityKind.note, 'future'), isTrue);
        expect(r.pipeline.held.isEmpty, isTrue);
        expect(r.a.meta['sync.held'], '{}');
      });
    });

    test('missing from getChunks → leaves sync.held (writeMeta) and the '
        'issue; a snapshot received later is applied when no longer ahead', () {
      withDownloadRig((r) {
        final c = aheadStore(r, const Duration(hours: 48))
          ..localWrite([noteWrite('future')]);
        final future = noteOf(c, 'future');
        final original = r.commit([future], author: nodeC);
        r.connect();
        r.catchUp();
        r.run(r.backend.deleteChunks([original.id]));

        r.async.elapse(day + const Duration(minutes: 1));
        final released = r.release();
        expect(released.chunks, 0);
        expect(r.pipeline.held.isEmpty, isTrue);
        expect(r.pipeline.held.authorNodes, isEmpty);
        expect(r.sync.writeMetaCalls.last, {'sync.held': '{}'});

        r.async.elapse(const Duration(hours: 1));
        r.commit([future], author: nodeB, kind: ChunkKind.snapshot);
        final result = r.catchUp();
        expect(result.held, 0);
        expect(result.applied, 1);
        expect(r.hasRow(EntityKind.note, 'future'), isTrue);
      });
    });
  });

  group('collapsed form', () {
    test('over maxHeldChunks the entries collapse to {"*": [serverTime, '
        'releaseAt]}; when due the cursor goes back and everything is '
        'received again', () {
      withDownloadRig((r) {
        final c = aheadStore(r, const Duration(hours: 48));
        final chunks = <RemoteChunk>[];
        for (var i = 0; i < 3; i++) {
          c.localWrite([noteWrite('f$i')]);
          chunks.add(r.commit([noteOf(c, 'f$i')], author: nodeC));
          r.async.elapse(const Duration(minutes: 10));
        }
        r.b.localWrite([noteWrite('normal')]);
        r.pushB();
        r.connect();
        final result = r.catchUp();
        expect(result.held, 3);
        final latest = noteOf(c, 'f2').versions.max.millis - day.inMilliseconds;
        final held = r.pipeline.held;
        expect(held.entries, isEmpty);
        expect(held.collapsed, (
          from: chunks.first.serverTime,
          releaseAtMillis: latest,
        ));
        expect(jsonDecode(r.a.meta['sync.held']!), {
          '*': [chunks.first.serverTime.micros, latest],
        });
        final cursor = r.pipeline.cursor!;
        expect(cursor, r.serverChunks().last.serverTime);

        // Read back after a restart.
        r.pipeline = r.newPipeline();
        r.run(r.pipeline.load());
        expect(r.pipeline.held.collapsed, held.collapsed);

        // Now base + 30 min; the latest releaseAt is base + 24 h 20 min.
        r.async.elapse(day - const Duration(minutes: 20));
        expect(r.release().rewound, isFalse, reason: 'not due yet');
        r.async.elapse(const Duration(hours: 1));
        final released = r.release();
        expect(released.rewound, isTrue);
        expect(released.applied, 4, reason: 'f0..f2 + normal again (kept)');
        for (var i = 0; i < 3; i++) {
          expect(r.hasRow(EntityKind.note, 'f$i'), isTrue);
        }
        expect(r.pipeline.held.isEmpty, isTrue);
        expect(r.pipeline.cursor, cursor);
        expect(
          r.sync.writeMetaCalls.first['sync.cursor'],
          '${chunks.first.serverTime.minus(const Duration(minutes: 5))}',
        );
      }, config: const SyncConfig(maxHeldChunks: 2));
    });
  });

  group('HeldChunks value', () {
    test('encode / decode round trip, author nodes, due ids', () {
      final held = HeldChunks(maxEntries: 3)
        ..hold('$nodeB-aaa', const ServerCursor(5), 100)
        ..hold('$nodeC-bbb', const ServerCursor(6), 200);
      expect(held.authorNodes, {nodeB, nodeC});
      expect(held.dueIds(100), ['$nodeB-aaa']);
      expect(held.dueIds(99), isEmpty);
      final back = HeldChunks.decode(held.encode(), maxEntries: 3);
      expect(back.entries, held.entries);
      expect(back.release('$nodeB-aaa'), isTrue);
      expect(back.release('$nodeB-aaa'), isFalse);
      expect(HeldChunks.decode('not json').isEmpty, isTrue);
      expect(HeldChunks.decode('').isEmpty, isTrue);
    });

    test('a chunk read back from meta has no serverTime: collapsing starts '
        'at zero', () {
      final held = HeldChunks.decode(
        jsonEncode({'$nodeB-aaa': 100}),
        maxEntries: 1,
      )..hold('$nodeB-bbb', const ServerCursor(50), 300);
      expect(held.collapsed, (from: ServerCursor.zero, releaseAtMillis: 300));
      held.hold('$nodeB-ccc', const ServerCursor(10), 400);
      expect(held.collapsed?.releaseAtMillis, 400);
      expect(held.isCollapsedDue(399), isFalse);
      expect(held.isCollapsedDue(400), isTrue);
    });
  });
}
