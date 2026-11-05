// T17: FirebaseSyncBackend on fake_cloud_firestore (6.4.6): commit (one su per batch),
// (su, id) order and pages, since (inclusive), watch (initial, added, modified; removed not
// reported), count, fetchScope, delete, the same id committed again, upsertDevice returning
// the server time, upsertProfile, getChunks, pending / malformed documents left out, close;
// then S01 once with two engines on it. Virtual time: the fake Firestore's serverTimestamp is
// the fakeAsync clock.
import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:fake_async/fake_async.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/firebase.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/fake_time.dart';
import '../support/local_writes.dart';

final DateTime _start = DateTime.utc(2026, 11, 1, 12);
const _uid = 'user-1';

ChunkWrite _chunk(String id, {String scope = 'lib', int size = 4}) =>
    ChunkWrite(
      id: id,
      scope: scope,
      authorNodeId: '0123456789abcdef',
      recordCount: 1,
      format: 1,
      kind: ChunkKind.delta,
      maxHlc: 'h-$id',
      payload: Uint8List.fromList(List.filled(size, id.codeUnitAt(0))),
    );

final class _Rig {
  _Rig(this.async) {
    clock = async.getClock(_start);
    db = FakeFirebaseFirestore(clock: clock);
    backend = FirebaseSyncBackend(
      firestore: db,
      blobs: FakeSyncServer(clock: clock).blobsOf(_uid),
      uid: _uid,
    );
  }

  final FakeAsync async;
  late final Clock clock;
  late final FakeFirebaseFirestore db;
  late final FirebaseSyncBackend backend;

  T run<T>(Future<T> f) => runFake(async, f);

  int get nowMicros => clock.now().microsecondsSinceEpoch;

  CollectionReference<Map<String, dynamic>> get changes =>
      db.collection('users').doc(_uid).collection('changes');

  List<String> ids(ChunkPage page) => [for (final c in page.chunks) c.id];
}

void _fake(void Function(_Rig rig) body) =>
    fakeAsync((async) => body(_Rig(async)), initialTime: _start);

void main() {
  test('commit: one su per batch (the server clock, µs); fetch in (su, id) '
      'order, page by page, since inclusive', () {
    _fake((rig) {
      final b = rig.backend;
      rig.run(b.commitChunks([_chunk('c2'), _chunk('c1')]));
      final first = ServerCursor(rig.nowMicros);
      rig.async.elapse(const Duration(seconds: 1));
      rig.run(b.commitChunks([_chunk('a9')]));
      final second = ServerCursor(rig.nowMicros);

      final all = rig.run(b.fetchChunks());
      expect(rig.ids(all), ['c1', 'c2', 'a9']);
      expect(all.chunks[0].serverTime, first);
      expect(all.chunks[1].serverTime, first);
      expect(all.chunks[2].serverTime, second);
      expect(all.nextPageToken, isNull);
      expect(all.chunks.first.payload, _chunk('c1').payload);

      final p1 = rig.run(b.fetchChunks(limit: 2));
      expect(rig.ids(p1), ['c1', 'c2']);
      expect(p1.nextPageToken, isNotNull);
      final p2 = rig.run(b.fetchChunks(limit: 2, pageToken: p1.nextPageToken));
      expect(rig.ids(p2), ['a9']);
      expect(p2.nextPageToken, isNull);
      // A full last page: one more (empty) page.
      final q1 = rig.run(b.fetchChunks(limit: 3));
      expect(q1.nextPageToken, isNotNull);
      final q2 = rig.run(b.fetchChunks(limit: 3, pageToken: q1.nextPageToken));
      expect(q2.chunks, isEmpty);
      expect(q2.nextPageToken, isNull);

      expect(rig.ids(rig.run(b.fetchChunks(since: second))), ['a9']);
      expect(rig.ids(rig.run(b.fetchChunks(since: first))), ['c1', 'c2', 'a9']);
      expect(rig.run(b.countChunks()), 3);
      expect(rig.run(b.countChunks(since: second)), 1);
    });
  });

  test('the same id again (lost ack): one document, a later su', () {
    _fake((rig) {
      final b = rig.backend;
      rig.run(b.commitChunks([_chunk('c1')]));
      rig.async.elapse(const Duration(seconds: 2));
      rig.run(b.commitChunks([_chunk('c1')]));
      final page = rig.run(b.fetchChunks());
      expect(rig.ids(page), ['c1']);
      expect(page.chunks.single.serverTime, ServerCursor(rig.nowMicros));
    });
  });

  test('fetchScope: one scope, (su, id) order, pages', () {
    _fake((rig) {
      final b = rig.backend;
      rig.run(
        b.commitChunks([
          _chunk('n2', scope: 'note'),
          _chunk('l1'),
          _chunk('n1', scope: 'note'),
        ]),
      );
      rig.async.elapse(const Duration(seconds: 1));
      rig.run(b.commitChunks([_chunk('n0', scope: 'note')]));
      expect(rig.ids(rig.run(b.fetchScope('note'))), ['n1', 'n2', 'n0']);
      final p1 = rig.run(b.fetchScope('note', limit: 2));
      expect(rig.ids(p1), ['n1', 'n2']);
      final p2 = rig.run(
        b.fetchScope('note', limit: 2, pageToken: p1.nextPageToken),
      );
      expect(rig.ids(p2), ['n0']);
      expect(rig.ids(rig.run(b.fetchScope('lib'))), ['l1']);
    });
  });

  test('watch: the initial result (also empty), added and modified chunks; '
      'removed ones are not reported', () {
    _fake((rig) {
      final b = rig.backend;
      final batches = <List<String>>[];
      final sub = b.watchChunks().listen(
        (batch) => batches.add([for (final c in batch) c.id]),
      );
      rig.async.flushMicrotasks();
      expect(batches, [<String>[]]);
      // (fake_cloud_firestore reports a batch's documents one snapshot each.)
      List<String> since(int from) => [
        for (final batch in batches.skip(from)) ...batch,
      ];
      var mark = batches.length;
      rig.run(b.commitChunks([_chunk('c1'), _chunk('c2')]));
      rig.async.flushMicrotasks();
      expect(since(mark), ['c1', 'c2']);
      rig.async.elapse(const Duration(seconds: 1));
      mark = batches.length;
      rig.run(b.commitChunks([_chunk('c1')]));
      rig.async.flushMicrotasks();
      expect(since(mark), ['c1']);
      final count = batches.length;
      rig.run(b.deleteChunks(['c2']));
      rig.async.flushMicrotasks();
      expect(batches, hasLength(count));
      unawaited(sub.cancel());

      // Started from a cursor: the initial result is what is after it.
      final later = <List<String>>[];
      final sub2 = b
          .watchChunks(since: ServerCursor(rig.nowMicros))
          .listen((batch) => later.add([for (final c in batch) c.id]));
      rig.async.flushMicrotasks();
      expect(later, [
        ['c1'],
      ]);
      unawaited(sub2.cancel());
    });
  });

  test('deleteChunks: in batches of 400; missing ids are fine', () {
    _fake((rig) {
      final b = rig.backend;
      final ids = [
        for (var i = 0; i < 401; i++) 'c${i.toString().padLeft(3, '0')}',
      ];
      for (var i = 0; i < ids.length; i += 100) {
        rig.run(
          b.commitChunks([
            for (final id in ids.sublist(i, i + 100 > 401 ? 401 : i + 100))
              _chunk(id),
          ]),
        );
      }
      expect(rig.run(b.countChunks()), 401);
      rig.run(b.deleteChunks([...ids.sublist(1), 'nope']));
      expect(rig.ids(rig.run(b.fetchChunks())), ['c000']);
    });
  });

  test('getChunks: by id, missing ids left out, more than 10 at once', () {
    _fake((rig) {
      final b = rig.backend;
      final ids = [for (var i = 0; i < 12; i++) 'g$i'];
      rig.run(b.commitChunks([for (final id in ids) _chunk(id)]));
      final got = rig.run(b.getChunks(['g11', 'missing', ...ids.take(10)]));
      expect([for (final c in got) c.id], ['g11', ...ids.take(10)]);
    });
  });

  test('pending (su null) and malformed documents are left out everywhere', () {
    _fake((rig) {
      final b = rig.backend;
      rig.run(b.commitChunks([_chunk('ok')]));
      rig.run(
        rig.changes.doc('bad').set({
          ...FirestoreChunkMapper.toFirestore(_chunk('bad')),
          'kind': 'merge',
        }),
      );
      expect(rig.ids(rig.run(b.fetchChunks())), ['ok']);
      expect(rig.ids(rig.run(b.fetchScope('lib'))), ['ok']);
      expect(
        [
          for (final c in rig.run(b.getChunks(['bad', 'ok']))) c.id,
        ],
        ['ok'],
      );
    });
  });

  test('upsertDevice returns the server time it wrote; firstSeenAt stays; '
      'upsertProfile keeps createdAt', () {
    _fake((rig) {
      final b = rig.backend;
      const device = DeviceInfo(
        nodeId: '0123456789abcdef',
        platform: DevicePlatform.web,
        appVersion: '1.0.0',
      );
      final t1 = rig.run(b.upsertDevice(device));
      expect(t1, ServerCursor(rig.nowMicros));
      rig.async.elapse(const Duration(minutes: 5));
      final t2 = rig.run(
        b.upsertDevice(
          const DeviceInfo(
            nodeId: '0123456789abcdef',
            platform: DevicePlatform.web,
            appVersion: '1.0.1',
            cursor: ServerCursor(42),
          ),
        ),
      );
      expect(t2, ServerCursor(rig.nowMicros));
      final doc = rig
          .run(
            rig.db
                .collection('users')
                .doc(_uid)
                .collection('devices')
                .doc('0123456789abcdef')
                .get(),
          )
          .data()!;
      expect(doc['platform'], 'web');
      expect(doc['appVersion'], '1.0.1');
      expect(doc['cursorMicros'], 42);
      expect(
        (doc['firstSeenAt']! as Timestamp).microsecondsSinceEpoch,
        t1.micros,
      );
      expect(
        (doc['lastSeenAt']! as Timestamp).microsecondsSinceEpoch,
        t2.micros,
      );

      rig.run(b.upsertProfile(const UserProfile(uid: _uid, email: 'a@b.c')));
      final created = rig.clock.now();
      rig.async.elapse(const Duration(days: 1));
      rig.run(b.upsertProfile(const UserProfile(uid: _uid, displayName: 'A')));
      final profile = rig
          .run(rig.db.collection('users').doc(_uid).get())
          .data()!;
      expect(
        (profile['createdAt']! as Timestamp).microsecondsSinceEpoch,
        created.microsecondsSinceEpoch,
      );
      expect(
        (profile['lastSeenAt']! as Timestamp).microsecondsSinceEpoch,
        rig.nowMicros,
      );
      expect(profile['displayName'], 'A');
      expect(profile['schema'], 1);
    });
  });

  test('close: later calls fail with cancelled', () {
    _fake((rig) {
      final b = rig.backend;
      rig.run(b.close());
      final error = runFakeError(rig.async, b.fetchChunks());
      expect(
        error,
        isA<SyncBackendException>().having(
          (e) => e.code,
          'code',
          SyncErrorCode.cancelled,
        ),
      );
    });
  });

  test('S01 once on FirebaseSyncBackend: A writes a note, B receives it', () {
    _fake((rig) {
      final server = FakeSyncServer(clock: rig.clock);
      FakeLocalStore store(String node) =>
          FakeLocalStore(nodeId: node * 8, clock: rig.clock);
      SyncEngine engineOf(FakeLocalStore local) => SyncEngine(
        local: local,
        auth: AuthService(FakeAuthBackend(user: const AuthUser(uid: _uid))),
        backendFactory: (u) async => FirebaseSyncBackend(
          firestore: rig.db,
          blobs: server.blobsOf(u.uid),
          uid: u.uid,
        ),
        clock: rig.clock,
        stopwatch: rig.clock.stopwatch,
      );
      final a = store('a1'), b = store('b2');
      final engineA = engineOf(a), engineB = engineOf(b);
      unawaited(engineA.start());
      unawaited(engineB.start());
      rig.async.elapse(const Duration(seconds: 10));
      expect(engineA.status.phase, SyncPhase.live);
      expect(engineB.status.phase, SyncPhase.live);

      a.localWrite([noteWrite('n1', title: 'on Firestore')]);
      rig.async.elapse(const Duration(seconds: 5));
      final row = b.rows[const EntityRef(EntityKind.note, 'n1')];
      expect((row?.entity as Note?)?.title, 'on Firestore');
      expect(engineA.status.pendingUploads, 0);
      expect(b.canonicalDump(), a.canonicalDump());
      unawaited(engineA.dispose());
      unawaited(engineB.dispose());
      rig.async.flushMicrotasks();
    });
  });
}
