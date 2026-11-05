// CORE T14 — the SYNC meta KV (6.10.4): 'sync.' keys, 256 KiB values, writeMeta in one
// transaction, applyRemote(metaUpdates:) stored with the data and not on a policy error.
@TestOn('vm')
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'support/sync_support.dart';

void main() {
  group('with a store', () {
    late DriftNoteStore store;
    late List<ChangeBatch> batches;
    late StreamSubscription<ChangeBatch> sub;

    setUp(() async {
      store = await openStore();
      batches = [];
      sub = store.changes.listen(batches.add);
    });
    tearDown(() async {
      await sub.cancel();
      await store.close();
    });

    test('round trip; unknown key → null; no outbox, no ChangeBatch', () async {
      await store.sync.writeMeta({'sync.cursor': '42', 'sync.held': '[]'});
      expect(await store.sync.readMeta('sync.cursor'), '42');
      expect(await store.sync.readMeta('sync.held'), '[]');
      expect(await store.sync.readMeta('sync.none'), isNull);
      await store.sync.writeMeta({'sync.cursor': '43'});
      expect(await store.sync.readMeta('sync.cursor'), '43');
      expect(await store.sync.pendingChanges(), isEmpty);
      await pumpEventQueue();
      expect(batches, isEmpty);
    });

    test("keys must start with 'sync.'", () async {
      for (final key in ['cursor', 'sync.', 'setting.x', 'hlc.last']) {
        await expectLater(
          store.sync.readMeta(key),
          throwsA(isA<ArgumentError>()),
          reason: key,
        );
        await expectLater(
          store.sync.writeMeta({key: 'v'}),
          throwsA(isA<ArgumentError>()),
          reason: key,
        );
      }
    });

    test('values up to 256 KiB of UTF-8; one bad entry stores none', () async {
      const limit = 256 * 1024;
      await store.sync.writeMeta({'sync.max': 'a' * limit});
      expect((await store.sync.readMeta('sync.max'))!.length, limit);
      await expectLater(
        store.sync.writeMeta({'sync.ok': '1', 'sync.big': 'a' * (limit + 1)}),
        throwsA(isA<ArgumentError>()),
      );
      // '가' is 3 bytes: fewer characters than the limit, more bytes.
      await expectLater(
        store.sync.writeMeta({'sync.ko': '가' * (limit ~/ 3 + 1)}),
        throwsA(isA<ArgumentError>()),
      );
      expect(await store.sync.readMeta('sync.ok'), isNull);
      expect(await store.sync.readMeta('sync.ko'), isNull);
    });

    test('applyRemote stores metaUpdates with the data', () async {
      await store.sync.applyRemote(
        [upsert(folder('f'), remoteAfter(store))],
        policy: (_, _, _) => const TakeRemote(),
        metaUpdates: const {'sync.cursor': 'c1'},
      );
      expect(await store.sync.readMeta('sync.cursor'), 'c1');
    });

    test('a policy exception: rethrown, data and metaUpdates not stored', () async {
      await store.sync.writeMeta({'sync.cursor': 'old'});
      final n = await store.library.createNote(title: 'local');
      final boom = Exception('policy failed');
      final policy = RecordingPolicy(
        (local, _, _) => local == null ? const TakeRemote() : throw boom,
      );
      Object? caught;
      try {
        await store.sync.applyRemote(
          [
            upsert(folder('new'), remoteAfter(store)),
            upsert(n.copyWith(title: 'remote'), remoteAfter(store)),
          ],
          policy: policy.call,
          metaUpdates: const {'sync.cursor': 'new'},
        );
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, same(boom));
      expect(policy.calls, hasLength(2));
      expect(await store.sync.readMeta('sync.cursor'), 'old');
      expect(await store.library.getFolder('new'), isNull);
      expect((await store.library.getNote(n.id))!.title, 'local');
      // Not retried: the store keeps working and no transaction is left behind.
      expect(store.persistenceStatus.consecutiveFailures, 0);
      await store.sync.writeMeta({'sync.cursor': 'after'});
      expect(await store.sync.readMeta('sync.cursor'), 'after');
    });
  });

  test('writeMeta is one transaction, pending while its commit is retried', () {
    fakeAsync((async) {
      late DriftNoteStore store;
      openStore().then((s) => store = s);
      async.flushMicrotasks();
      store.queue.failNextCommits(1);
      var done = false;
      store.sync
          .writeMeta({'sync.a': '1', 'sync.b': '2'})
          .then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isFalse);
      String? a = 'unread';
      store.sync.readMeta('sync.a').then((v) => a = v);
      async.flushMicrotasks();
      expect(a, isNull, reason: 'the failed transaction was rolled back');
      async.elapse(const Duration(milliseconds: 100));
      expect(done, isTrue);
      final values = <String?>[];
      store.sync.readMeta('sync.a').then(values.add);
      store.sync.readMeta('sync.b').then(values.add);
      async.flushMicrotasks();
      expect(values, ['1', '2']);
      store.close();
      async.flushMicrotasks();
    });
  });
}
