import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/entity_fixtures.dart';
import '../support/fake_time.dart';

final DateTime start = DateTime.utc(2026, 11, 1);
final int startMicros = start.microsecondsSinceEpoch;
const Duration latency = Duration(milliseconds: 50);

/// A rule-conforming chunk write with [fill] bytes of [size].
ChunkWrite chunk(
  int fill, {
  int size = 16,
  String node = kNodeA,
  String scope = 'lib',
  int records = 1,
  int format = 1,
  ChunkKind kind = ChunkKind.delta,
  String? id,
}) {
  final payload = Uint8List(size)..fillRange(0, size, fill & 0xff);
  if (size > 0) payload[0] = fill ~/ 256;
  return ChunkWrite(
    id: id ?? chunkIdOf(node, payload),
    scope: scope,
    authorNodeId: node,
    recordCount: records,
    format: format,
    kind: kind,
    maxHlc: hlcText(kT0, node: node),
    payload: payload,
  );
}

/// Server, one uid, two devices (A and B) on their own links.
final class Rig {
  Rig(this.async) {
    server = FakeSyncServer(clock: async.getClock(start));
    a = server.connect(uid: 'user-1', link: linkA);
    b = server.connect(uid: 'user-1', link: linkB);
  }

  final FakeAsync async;
  late final FakeSyncServer server;
  final FakeNetworkLink linkA = FakeNetworkLink();
  final FakeNetworkLink linkB = FakeNetworkLink();
  late final FakeSyncBackend a, b;

  T run<T>(Future<T> future) => runFake(async, future);
  Object error(Future<Object?> future) => runFakeError(async, future);

  int get nowMicros => start.add(async.elapsed).microsecondsSinceEpoch;

  List<String> ids(Iterable<RemoteChunk> chunks) => [
    for (final c in chunks) c.id,
  ];
}

void main() {
  group('commit', () {
    test('is atomic: every chunk of a commit has the same serverTime', () {
      fakeAsync((async) {
        final r = Rig(async);
        final writes = [chunk(1), chunk(2), chunk(3, scope: 'note-1')];
        r.run(r.a.commitChunks(writes));
        // Request and response latency.
        expect(async.elapsed, latency * 2);
        final stored = r.server.chunksOf('user-1');
        expect(stored, hasLength(3));
        final su = stored.first.chunk.serverTime;
        expect(su, ServerCursor(startMicros + latency.inMicroseconds));
        for (final s in stored) {
          expect(s.chunk.serverTime, su);
          expect(s.visibleAt, su);
        }
        final byId = {for (final s in stored) s.chunk.id: s.chunk};
        for (final w in writes) {
          final c = byId[w.id]!;
          expect(c.scope, w.scope);
          expect(c.authorNodeId, w.authorNodeId);
          expect(c.recordCount, w.recordCount);
          expect(c.format, w.format);
          expect(c.kind, w.kind);
          expect(c.maxHlc, w.maxHlc);
          expect(c.payload, w.payload);
        }
        expect(r.server.writeCount('user-1'), 3);
      });
    });

    test('stores nothing when one chunk breaks a rule', () {
      fakeAsync((async) {
        final r = Rig(async);
        final e = r.error(
          r.a.commitChunks([chunk(1), chunk(2, records: 0), chunk(3)]),
        );
        expect(
          e,
          isA<SyncBackendException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.permissionDenied,
          ),
        );
        expect(r.server.chunksOf('user-1'), isEmpty);
        expect(r.server.writeCount('user-1'), 0);
      });
    });

    test('commits at the same instant get increasing server times', () {
      fakeAsync((async) {
        final r = Rig(async);
        final first = r.a.commitChunks([chunk(1)]);
        final second = r.b.commitChunks([chunk(2, node: kNodeB)]);
        r.run(Future.wait([first, second]));
        final su = [
          for (final s in r.server.chunksOf('user-1'))
            s.chunk.serverTime.micros,
        ];
        final at = startMicros + latency.inMicroseconds;
        expect(su, [at, at + 1]);
      });
    });

    test('a full commit of 500 writes passes, 501 is invalidArgument', () {
      fakeAsync((async) {
        final r = Rig(async);
        final e = r.error(
          r.a.commitChunks([for (var i = 0; i < 501; i++) chunk(i)]),
        );
        expect((e as SyncBackendException).code, SyncErrorCode.invalidArgument);
        r.run(r.a.commitChunks([for (var i = 0; i < 500; i++) chunk(i)]));
        expect(r.server.chunksOf('user-1'), hasLength(500));
      });
    });
  });

  group('fetch', () {
    test('orders by (serverTime, id) and pages with a token', () {
      fakeAsync((async) {
        final r = Rig(async);
        final c1 = [chunk(10), chunk(11), chunk(12)];
        r.run(r.a.commitChunks(c1));
        async.elapse(const Duration(seconds: 1));
        final c2 = [chunk(20), chunk(21)];
        r.run(r.a.commitChunks(c2));
        final expected = [
          ...r.ids(c1.map(toRemote))..sort(),
          ...r.ids(c2.map(toRemote))..sort(),
        ];

        final all = r.run(r.b.fetchChunks());
        expect(r.ids(all.chunks), expected);
        expect(all.nextPageToken, isNull);

        final pages = <String>[];
        Object? token;
        var calls = 0;
        do {
          final page = r.run(r.b.fetchChunks(pageToken: token, limit: 2));
          calls++;
          expect(page.chunks.length, lessThanOrEqualTo(2));
          pages.addAll(r.ids(page.chunks));
          token = page.nextPageToken;
        } while (token != null);
        expect(pages, expected);
        expect(calls, 3); // 2 + 2 + 1
      });
    });

    test('a full last page has a token and the next page is empty', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.run(r.a.commitChunks([chunk(1), chunk(2)]));
        final page = r.run(r.b.fetchChunks(limit: 2));
        expect(page.chunks, hasLength(2));
        expect(page.nextPageToken, isNotNull);
        final next = r.run(
          r.b.fetchChunks(pageToken: page.nextPageToken, limit: 2),
        );
        expect(next.chunks, isEmpty);
        expect(next.nextPageToken, isNull);
      });
    });

    test('since keeps serverTime >= since', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.run(r.a.commitChunks([chunk(1)]));
        final su2 = r.nowMicros;
        r.run(r.a.commitChunks([chunk(2)]));
        r.run(r.a.commitChunks([chunk(3)]));
        final stored = r.server.chunksOf('user-1');
        final since = stored[1].chunk.serverTime;
        expect(since.micros, greaterThan(su2));
        final page = r.run(r.b.fetchChunks(since: since));
        expect(r.ids(page.chunks), [stored[1].chunk.id, stored[2].chunk.id]);
      });
    });

    test('bad limit or foreign page token is invalidArgument', () {
      fakeAsync((async) {
        final r = Rig(async);
        for (final f in [
          () => r.b.fetchChunks(limit: 0),
          () => r.b.fetchChunks(pageToken: 'x'),
          () => r.b.fetchScope('lib', limit: 0),
        ]) {
          expect(
            (r.error(f()) as SyncBackendException).code,
            SyncErrorCode.invalidArgument,
          );
        }
      });
    });

    test('fetchScope, countChunks and deleteChunks', () {
      fakeAsync((async) {
        final r = Rig(async);
        final lib = chunk(1);
        final n1 = [chunk(2, scope: 'note-1'), chunk(3, scope: 'note-1')];
        r.run(r.a.commitChunks([lib, ...n1]));
        final later = chunk(4, scope: 'note-1');
        async.elapse(const Duration(seconds: 1));
        r.run(r.a.commitChunks([later]));

        final scope = r.run(r.b.fetchScope('note-1'));
        expect(r.ids(scope.chunks), [
          ...r.ids(n1.map(toRemote))..sort(),
          later.id,
        ]);
        expect(r.run(r.b.fetchScope('note-2')).chunks, isEmpty);
        final page = r.run(r.b.fetchScope('note-1', limit: 2));
        expect(page.chunks, hasLength(2));
        final rest = r.run(
          r.b.fetchScope('note-1', pageToken: page.nextPageToken, limit: 2),
        );
        expect(r.ids(rest.chunks), [later.id]);

        expect(r.run(r.b.countChunks()), 4);
        final laterSu = r.server.chunksOf('user-1').last.chunk.serverTime;
        expect(r.run(r.b.countChunks(since: laterSu)), 1);

        r.run(r.b.deleteChunks([lib.id, n1.first.id, 'missing']));
        expect(r.ids(r.server.chunksOf('user-1').map((s) => s.chunk)), [
          n1.last.id,
          later.id,
        ]);
        expect(r.server.deleteCount('user-1'), 3);
        expect(r.run(r.b.countChunks()), 2);
      });
    });
  });

  group('watch', () {
    test('sends the initial result, then added and modified chunks', () {
      fakeAsync((async) {
        final r = Rig(async);
        final first = chunk(1);
        r.run(r.a.commitChunks([first]));

        final batches = <List<RemoteChunk>>[];
        final arrivals = <Duration>[];
        final sub = r.b.watchChunks().listen((batch) {
          batches.add(batch);
          arrivals.add(async.elapsed);
        });
        final listenAt = async.elapsed;
        async.elapse(latency * 2);
        expect(batches, hasLength(1));
        expect(r.ids(batches[0]), [first.id]);
        expect(arrivals[0], listenAt + latency * 2);

        // Added: arrives one latency after the server stored it.
        final second = chunk(2);
        final commitAt = async.elapsed;
        r.run(r.a.commitChunks([second]));
        async.elapse(latency);
        expect(batches, hasLength(2));
        expect(r.ids(batches[1]), [second.id]);
        expect(arrivals[1], commitAt + latency * 2);

        // Modified: the same id committed again (lost-ack retry) gets a new
        // serverTime and is sent again; still one document on the server.
        async.elapse(const Duration(seconds: 5));
        r.run(r.a.commitChunks([second]));
        async.elapse(latency);
        expect(batches, hasLength(3));
        expect(r.ids(batches[2]), [second.id]);
        expect(
          batches[2].single.serverTime,
          greaterThan(batches[1].single.serverTime),
        );
        expect(r.server.chunksOf('user-1'), hasLength(2));
        sub.cancel();
      });
    });

    test('the initial result is sent when empty and honours since', () {
      fakeAsync((async) {
        final r = Rig(async);
        final batches = <List<RemoteChunk>>[];
        final sub = r.b.watchChunks().listen(batches.add);
        async.elapse(latency * 2);
        expect(batches, [isEmpty]);
        sub.cancel();

        r.run(r.a.commitChunks([chunk(1)]));
        async.elapse(const Duration(seconds: 1));
        r.run(r.a.commitChunks([chunk(2)]));
        final since = r.server.chunksOf('user-1').last.chunk.serverTime;
        final later = <List<RemoteChunk>>[];
        final sub2 = r.b.watchChunks(since: since).listen(later.add);
        async.elapse(latency * 2);
        expect(r.ids(later.single), [chunk(2).id]);
        sub2.cancel();
      });
    });

    test('a cancelled watch gets nothing more and counts no more reads', () {
      fakeAsync((async) {
        final r = Rig(async);
        final batches = <List<RemoteChunk>>[];
        final sub = r.b.watchChunks().listen(batches.add);
        async.elapse(latency * 2);
        sub.cancel();
        r.run(r.a.commitChunks([chunk(1)]));
        async.elapse(const Duration(seconds: 1));
        expect(batches, [isEmpty]);
        expect(r.server.readCount('user-1'), 0);
      });
    });

    test('deleted chunks are not reported', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.run(r.a.commitChunks([chunk(1)]));
        final batches = <List<RemoteChunk>>[];
        final sub = r.b.watchChunks().listen(batches.add);
        async.elapse(latency * 2);
        r.run(r.a.deleteChunks([chunk(1).id]));
        async.elapse(const Duration(seconds: 1));
        expect(batches, hasLength(1));
        sub.cancel();
      });
    });
  });

  group('late visibility', () {
    test('queries miss the chunk until visibleAt; watches get it then', () {
      fakeAsync((async) {
        final r = Rig(async);
        final batches = <List<RemoteChunk>>[];
        final sub = r.b.watchChunks().listen(batches.add);
        async.elapse(latency * 2);

        r.server.delayVisibilityOfNextCommit(const Duration(seconds: 3));
        final late = chunk(1);
        r.run(r.a.commitChunks([late]));
        final stored = r.server.chunksOf('user-1').single;
        expect(
          stored.visibleAt,
          ServerCursor(stored.chunk.serverTime.micros + 3000000),
        );
        // Server time is fixed at commit; the chunk is invisible to queries.
        expect(r.run(r.b.fetchChunks()).chunks, isEmpty);
        expect(r.run(r.b.countChunks()), 0);
        expect(r.run(r.b.fetchScope('lib')).chunks, isEmpty);
        // Reads by id are not affected.
        expect(r.ids(r.run(r.b.getChunks([late.id]))), [late.id]);

        // The next commit is visible at once although it is newer.
        final normal = chunk(2);
        r.run(r.a.commitChunks([normal]));
        async.elapse(latency);
        expect(r.ids(batches.last), [normal.id]);
        expect(r.ids(r.run(r.b.fetchChunks()).chunks), [normal.id]);

        final visibleIn = stored.visibleAt.toDateTime().difference(
          start.add(async.elapsed),
        );
        async.elapse(visibleIn + latency);
        expect(r.ids(batches.last), [late.id]);
        expect(r.ids(r.run(r.b.fetchChunks()).chunks), [late.id, normal.id]);
        sub.cancel();
      });
    });
  });

  group('offline', () {
    test('ends open watch streams with a network error', () {
      fakeAsync((async) {
        final r = Rig(async);
        final events = <Object>[];
        var done = false;
        r.b.watchChunks().listen(
          events.add,
          onError: events.add,
          onDone: () => done = true,
        );
        async.elapse(latency * 2);
        r.linkB.setOnline(false);
        async.flushMicrotasks();
        expect(events, hasLength(2));
        expect(
          events[1],
          isA<SyncBackendException>().having(
            (e) => e.code,
            'code',
            SyncErrorCode.network,
          ),
        );
        expect(done, isTrue);
        // A watch opened while offline fails at once.
        final again = <Object>[];
        r.b.watchChunks().listen(again.add, onError: again.add);
        async.flushMicrotasks();
        expect(
          (again.single as SyncBackendException).code,
          SyncErrorCode.network,
        );
      });
    });

    test('calls fail with network; after going online they work', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkA.setOnline(false);
        expect(r.linkA.online, isFalse);
        final e = r.error(r.a.commitChunks([chunk(1)]));
        expect((e as SyncBackendException).code, SyncErrorCode.network);
        expect(async.elapsed, Duration.zero);
        expect(r.server.chunksOf('user-1'), isEmpty);
        r.linkA.setOnline(true);
        r.run(r.a.commitChunks([chunk(1)]));
        expect(r.server.chunksOf('user-1'), hasLength(1));
      });
    });

    test('going offline after the server applied loses the response', () {
      fakeAsync((async) {
        final r = Rig(async);
        final commit = r.a.commitChunks([chunk(1)]);
        async.elapse(latency + const Duration(milliseconds: 1));
        r.linkA.setOnline(false);
        final e = r.error(commit);
        expect((e as SyncBackendException).code, SyncErrorCode.network);
        expect(r.server.chunksOf('user-1'), hasLength(1));
      });
    });
  });

  group('faults', () {
    test('FakeNetworkError: nothing applied', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkA.failNext(const FakeNetworkError(), op: FakeOp.commit);
        final e = r.error(r.a.commitChunks([chunk(1)]));
        expect((e as SyncBackendException).code, SyncErrorCode.network);
        expect(r.server.chunksOf('user-1'), isEmpty);
        r.run(r.a.commitChunks([chunk(1)]));
        expect(r.server.chunksOf('user-1'), hasLength(1));
      });
    });

    test('FakeAckLost: applied, the client sees a network error; the retry '
        'rewrites the same document', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkA.failNext(const FakeAckLost());
        final e = r.error(r.a.commitChunks([chunk(1)]));
        expect((e as SyncBackendException).code, SyncErrorCode.network);
        final first = r.server.chunksOf('user-1').single.chunk.serverTime;
        async.elapse(const Duration(seconds: 1));
        r.run(r.a.commitChunks([chunk(1)]));
        final stored = r.server.chunksOf('user-1');
        expect(stored, hasLength(1));
        expect(stored.single.chunk.serverTime, greaterThan(first));
        expect(r.server.writeCount('user-1'), 2);
      });
    });

    test('FakeErrorCode: the server answers with the code', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkA.failNext(
          const FakeErrorCode(SyncErrorCode.resourceExhausted),
          op: FakeOp.device,
          times: 2,
        );
        for (var i = 0; i < 2; i++) {
          final e = r.error(
            r.a.upsertDevice(
              const DeviceInfo(
                nodeId: kNodeA,
                platform: DevicePlatform.web,
                appVersion: '1',
              ),
            ),
          );
          expect(
            (e as SyncBackendException).code,
            SyncErrorCode.resourceExhausted,
          );
        }
        expect(r.server.devices, isEmpty);
        r.run(
          r.a.upsertDevice(
            const DeviceInfo(
              nodeId: kNodeA,
              platform: DevicePlatform.web,
              appVersion: '1',
            ),
          ),
        );
        expect(r.server.devices.keys, ['user-1/$kNodeA']);
      });
    });

    test('FakeInterrupt on a non-transfer call acts like a network error', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkA.failNext(const FakeInterrupt(0.5));
        final e = r.error(r.a.commitChunks([chunk(1)]));
        expect((e as SyncBackendException).code, SyncErrorCode.network);
        expect(r.server.chunksOf('user-1'), isEmpty);
      });
    });

    test('rejectCommitsWhere fails matching commits every time', () {
      fakeAsync((async) {
        final r = Rig(async);
        final bad = chunk(7);
        r.linkA.rejectCommitsWhere(
          (c) => c.id == bad.id,
          SyncErrorCode.invalidArgument,
        );
        for (var i = 0; i < 2; i++) {
          final e = r.error(r.a.commitChunks([chunk(1), bad]));
          expect(
            (e as SyncBackendException).code,
            SyncErrorCode.invalidArgument,
          );
        }
        expect(r.server.chunksOf('user-1'), isEmpty);
        r.run(r.a.commitChunks([chunk(1)]));
        // Another link has no such rule.
        r.run(r.b.commitChunks([bad]));
        expect(r.server.chunksOf('user-1'), hasLength(2));
      });
    });

    test('faults are taken in order by the first matching op', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkA
          ..failNext(
            const FakeErrorCode(SyncErrorCode.aborted),
            op: FakeOp.commit,
          )
          ..failNext(const FakeErrorCode(SyncErrorCode.internal));
        // The fetch takes the second (any) fault; the commit the first.
        expect(
          (r.error(r.a.fetchChunks()) as SyncBackendException).code,
          SyncErrorCode.internal,
        );
        expect(
          (r.error(r.a.commitChunks([chunk(1)])) as SyncBackendException).code,
          SyncErrorCode.aborted,
        );
        r.run(r.a.commitChunks([chunk(1)]));
        expect(
          () => r.linkA.failNext(const FakeNetworkError(), times: 0),
          throwsArgumentError,
        );
      });
    });

    test('watch faults end the stream', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.linkB.failNext(
          const FakeErrorCode(SyncErrorCode.unavailable),
          op: FakeOp.watch,
        );
        final events = <Object>[];
        var done = false;
        r.b.watchChunks().listen(
          events.add,
          onError: events.add,
          onDone: () => done = true,
        );
        async.elapse(latency * 2);
        expect(
          (events.single as SyncBackendException).code,
          SyncErrorCode.unavailable,
        );
        expect(done, isTrue);
      });
    });
  });

  group('rules', () {
    test(
      'uid: each uid has its own data; profile of another uid is denied',
      () {
        fakeAsync((async) {
          final r = Rig(async);
          final other = r.server.connect(
            uid: 'user-2',
            link: FakeNetworkLink(),
          );
          expect(other.uid, 'user-2');
          r.run(r.a.commitChunks([chunk(1)]));
          expect(r.run(other.fetchChunks()).chunks, isEmpty);
          expect(r.server.chunksOf('user-2'), isEmpty);
          final e = r.error(
            other.upsertProfile(const UserProfile(uid: 'user-1')),
          );
          expect(
            (e as SyncBackendException).code,
            SyncErrorCode.permissionDenied,
          );
          expect(r.server.profiles, isEmpty);
          expect(
            () => r.server.connect(uid: '', link: FakeNetworkLink()),
            throwsArgumentError,
          );
        });
      },
    );

    test('size: data over 1,000,000 B denied, document over 1 MiB invalid', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.run(r.a.commitChunks([chunk(1, size: 1000000)]));
        final denied = r.error(r.a.commitChunks([chunk(2, size: 1000001)]));
        expect(
          (denied as SyncBackendException).code,
          SyncErrorCode.permissionDenied,
        );
        final invalid = r.error(r.a.commitChunks([chunk(3, size: 1048576)]));
        expect(
          (invalid as SyncBackendException).code,
          SyncErrorCode.invalidArgument,
        );
        expect(r.server.chunksOf('user-1'), hasLength(1));
      });
    });

    test('fields and chunk id', () {
      fakeAsync((async) {
        final r = Rig(async);
        final good = chunk(1);
        final cases = <String, ChunkWrite>{
          'fmt 0': chunk(1, format: 0),
          'fmt 17': chunk(1, format: 17),
          'records 5001': chunk(1, records: 5001),
          'empty scope': chunk(1, scope: ''),
          'scope 65': chunk(1, scope: 'x' * 65),
          'id of another node': chunk(1, id: chunkIdOf(kNodeB, good.payload)),
          'id format': chunk(1, id: 'not-a-chunk-id'),
          'by not hex': ChunkWrite(
            id: good.id,
            scope: 'lib',
            authorNodeId: 'XYZ',
            recordCount: 1,
            format: 1,
            kind: ChunkKind.delta,
            maxHlc: good.maxHlc,
            payload: good.payload,
          ),
          'maxHlc length': ChunkWrite(
            id: good.id,
            scope: 'lib',
            authorNodeId: kNodeA,
            recordCount: 1,
            format: 1,
            kind: ChunkKind.delta,
            maxHlc: 'x',
            payload: good.payload,
          ),
        };
        for (final MapEntry(:key, :value) in cases.entries) {
          final e = r.error(r.a.commitChunks([value]));
          expect(
            (e as SyncBackendException).code,
            SyncErrorCode.permissionDenied,
            reason: key,
          );
        }
        expect(r.server.chunksOf('user-1'), isEmpty);
        r.run(
          r.a.commitChunks([
            chunk(1, format: 16, records: 5000, scope: 'x' * 64),
          ]),
        );
        expect(r.server.chunksOf('user-1'), hasLength(1));
      });
    });

    test('same id: identical content allowed (su only), different denied', () {
      fakeAsync((async) {
        final r = Rig(async);
        final c = chunk(1);
        r.run(r.a.commitChunks([c]));
        final changed = ChunkWrite(
          id: c.id,
          scope: c.scope,
          authorNodeId: c.authorNodeId,
          recordCount: 2,
          format: c.format,
          kind: c.kind,
          maxHlc: c.maxHlc,
          payload: c.payload,
        );
        final e = r.error(r.a.commitChunks([changed]));
        expect(
          (e as SyncBackendException).code,
          SyncErrorCode.permissionDenied,
        );
        // Within one commit as well.
        final c2 = chunk(2);
        final e2 = r.error(
          r.a.commitChunks([
            c2,
            ChunkWrite(
              id: c2.id,
              scope: 'other',
              authorNodeId: c2.authorNodeId,
              recordCount: 1,
              format: 1,
              kind: c2.kind,
              maxHlc: c2.maxHlc,
              payload: c2.payload,
            ),
          ]),
        );
        expect(
          (e2 as SyncBackendException).code,
          SyncErrorCode.permissionDenied,
        );
        r.run(r.a.commitChunks([c, c]));
        expect(r.server.chunksOf('user-1'), hasLength(1));
        expect(r.server.chunksOf('user-1').single.chunk.recordCount, 1);
      });
    });

    test('device id must be 16 hex', () {
      fakeAsync((async) {
        final r = Rig(async);
        final e = r.error(
          r.a.upsertDevice(
            const DeviceInfo(
              nodeId: 'phone',
              platform: DevicePlatform.ios,
              appVersion: '1',
            ),
          ),
        );
        expect(
          (e as SyncBackendException).code,
          SyncErrorCode.permissionDenied,
        );
      });
    });
  });

  group('counters', () {
    test('writes, reads, deletes per uid and calls per op', () {
      fakeAsync((async) {
        final r = Rig(async);
        final watchErrors = <Object>[];
        final sub = r.b.watchChunks().listen((_) {}, onError: watchErrors.add);
        async.elapse(latency * 2);
        r.run(r.a.commitChunks([chunk(1), chunk(2)]));
        async.elapse(latency);
        expect(r.server.writeCount('user-1'), 2);
        expect(r.server.readCount('user-1'), 2); // the watch batch
        r.run(r.b.fetchChunks());
        expect(r.server.readCount('user-1'), 4);
        r.run(r.b.getChunks([chunk(1).id, 'missing']));
        expect(r.server.readCount('user-1'), 5);
        r.run(r.b.countChunks());
        expect(r.server.readCount('user-1'), 5);
        r.run(r.a.deleteChunks([chunk(1).id]));
        expect(r.server.deleteCount('user-1'), 1);
        r.run(r.a.upsertProfile(const UserProfile(uid: 'user-1')));
        expect(r.server.writeCount('user-1'), 2);
        expect(r.server.writeCount('user-9'), 0);
        expect(r.server.readCount('user-9'), 0);
        expect(r.server.deleteCount('user-9'), 0);

        expect(r.linkA.callCount(FakeOp.commit), 1);
        expect(r.linkA.callCount(FakeOp.delete), 1);
        expect(r.linkA.callCount(FakeOp.profile), 1);
        expect(r.linkA.callCount(FakeOp.any), 3);
        expect(r.linkB.callCount(FakeOp.watch), 1);
        expect(r.linkB.callCount(FakeOp.fetch), 1);
        expect(r.linkB.callCount(FakeOp.byId), 1);
        expect(r.linkB.callCount(FakeOp.count), 1);
        expect(r.linkB.callCount(FakeOp.any), 4);
        // Failed calls count too.
        r.linkB.setOnline(false);
        r.error(r.b.fetchScope('lib'));
        expect(r.linkB.callCount(FakeOp.fetch), 2);
        sub.cancel();
      });
    });
  });

  group('profile and device documents', () {
    test('upsertDevice returns the server time it wrote', () {
      fakeAsync((async) {
        final r = Rig(async);
        async.elapse(const Duration(minutes: 3));
        final t = r.run(
          r.a.upsertDevice(
            const DeviceInfo(
              nodeId: kNodeA,
              platform: DevicePlatform.web,
              appVersion: '1.0.0',
              cursor: ServerCursor(42),
            ),
          ),
        );
        final expected = ServerCursor(
          start
              .add(const Duration(minutes: 3) + latency)
              .microsecondsSinceEpoch,
        );
        expect(t, expected);
        expect(r.server.devices['user-1/$kNodeA'], {
          'platform': 'web',
          'appVersion': '1.0.0',
          'firstSeenAt': expected,
          'lastSeenAt': expected,
          'cursorMicros': 42,
        });
        async.elapse(const Duration(hours: 1));
        final t2 = r.run(
          r.a.upsertDevice(
            const DeviceInfo(
              nodeId: kNodeA,
              platform: DevicePlatform.web,
              appVersion: '1.0.1',
            ),
          ),
        );
        expect(
          t2.micros - t.micros,
          (const Duration(hours: 1) + latency * 2).inMicroseconds,
        );
        final doc = r.server.devices['user-1/$kNodeA']!;
        expect(doc['firstSeenAt'], expected);
        expect(doc['lastSeenAt'], t2);
        expect(doc['appVersion'], '1.0.1');
        expect(doc['cursorMicros'], isNull);
      });
    });

    test('upsertProfile keeps createdAt', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.run(
          r.a.upsertProfile(
            const UserProfile(uid: 'user-1', email: 'a@b.c', displayName: 'A'),
          ),
        );
        final created = r.server.profiles['user-1']!['createdAt'];
        async.elapse(const Duration(days: 1));
        r.run(r.a.upsertProfile(const UserProfile(uid: 'user-1')));
        final p = r.server.profiles['user-1']!;
        expect(p['createdAt'], created);
        expect(p['lastSeenAt'], isNot(created));
        expect(p['email'], isNull);
        expect(p['schema'], 1);
      });
    });
  });

  group('getChunks and commitRaw', () {
    test(
      'getChunks returns stored chunks in request order, missing omitted',
      () {
        fakeAsync((async) {
          final r = Rig(async);
          final c = [chunk(1), chunk(2), chunk(3)];
          r.run(r.a.commitChunks(c));
          final got = r.run(r.b.getChunks([c[2].id, 'gone', c[0].id, c[2].id]));
          expect(r.ids(got), [c[2].id, c[0].id]);
          expect(r.run(r.b.getChunks(const [])), isEmpty);
        });
      },
    );

    test('commitRaw stores without rules or network and reaches watches', () {
      fakeAsync((async) {
        final r = Rig(async);
        final batches = <List<RemoteChunk>>[];
        final sub = r.b.watchChunks().listen(batches.add);
        async.elapse(latency * 2);
        final raw = [
          chunk(1, format: 2),
          ChunkWrite(
            id: 'raw-id',
            scope: 'lib',
            authorNodeId: kNodeB,
            recordCount: 1,
            format: 1,
            kind: ChunkKind.snapshot,
            maxHlc: hlcText(kT0 + 48 * 3600 * 1000, node: kNodeB),
            payload: Uint8List.fromList([1, 2, 3]),
          ),
        ];
        final at = async.elapsed;
        r.server.commitRaw('user-1', raw);
        expect(async.elapsed, at);
        final stored = r.server.chunksOf('user-1');
        expect(stored, hasLength(2));
        expect(stored[0].chunk.serverTime, stored[1].chunk.serverTime);
        expect(r.linkA.callCount(FakeOp.any), 0);
        async.elapse(latency);
        expect(r.ids(batches.last)..sort(), ['raw-id', raw[0].id]..sort());
        expect(batches.last.firstWhere((c) => c.id == raw[0].id).format, 2);
        sub.cancel();
      });
    });
  });

  group('close', () {
    test('ends watch streams without error and rejects new calls', () {
      fakeAsync((async) {
        final r = Rig(async);
        var done = false;
        final errors = <Object>[];
        r.b.watchChunks().listen(
          (_) {},
          onError: errors.add,
          onDone: () => done = true,
        );
        async.elapse(latency * 2);
        r.run(r.b.close());
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(errors, isEmpty);
        expect(r.error(r.b.fetchChunks()), isA<StateError>());
        expect(() => r.b.watchChunks(), throwsStateError);
        // Other backends of the uid keep working.
        r.run(r.a.commitChunks([chunk(1)]));
      });
    });
  });
}

RemoteChunk toRemote(ChunkWrite w) => RemoteChunk(
  id: w.id,
  scope: w.scope,
  authorNodeId: w.authorNodeId,
  recordCount: w.recordCount,
  format: w.format,
  kind: w.kind,
  maxHlc: w.maxHlc,
  payload: w.payload,
  serverTime: ServerCursor.zero,
);
