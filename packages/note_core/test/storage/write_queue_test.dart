// CORE T7 — WriteQueue (6.9): group commit, caps, retry schedule, Future rules (4.5 head).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/kv_keys.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:note_core/src/storage/write_queue.dart';
import 'package:test/test.dart';

import 'storage_support.dart';

Future<int> _folderCount(DriftNoteStore s) async =>
    (await s.db.select(s.db.folders).get()).length;

/// Opens a store inside [body]'s fake zone and runs it; the store is closed after.
void _fake(Future<void> Function(FakeAsync async, DriftNoteStore store) body) {
  fakeAsync((async) {
    late DriftNoteStore store;
    var opened = false;
    openStore(clock: async.getClock(DateTime.utc(2026, 11, 5))).then((s) {
      store = s;
      opened = true;
    });
    async.flushMicrotasks();
    expect(opened, isTrue, reason: 'opening needs no timers');
    var done = false;
    Object? error;
    body(async, store).then(
      (_) => done = true,
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    async.flushMicrotasks();
    for (var i = 0; i < 100000 && !done; i++) {
      async.elapse(const Duration(milliseconds: 10));
    }
    if (error != null) Error.throwWithStackTrace(error!, StackTrace.current);
    expect(done, isTrue);
    store.close();
    async.flushMicrotasks();
  });
}

void main() {
  test('an empty queue commits right after enqueue (microtask, no timer)', () {
    fakeAsync((async) {
      late DriftNoteStore store;
      openStore().then((s) => store = s);
      async.flushMicrotasks();
      var done = false;
      store.queue
          .run((tx) => tx.putLocal(folder('f1'), const {kAllFields}))
          .then((_) => done = true);
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(async.pendingTimers, isEmpty);
      expect(store.queue.debugTransactionCount, 1);
      store.close();
      async.flushMicrotasks();
    });
  });

  test(
    '50 jobs queued during a transaction share at most 3 transactions',
    () async {
      final store = await openStore();
      addTearDown(store.close);
      final gate = Completer<void>();
      final first = store.queue.run((tx) async {
        await tx.putLocal(folder('f0'), const {kAllFields});
        await gate.future;
      });
      await pumpEventQueue(times: 5);
      final rest = [
        for (var i = 1; i <= 50; i++)
          store.queue.run(
            (tx) => tx.putLocal(folder('f$i'), const {kAllFields}),
          ),
      ];
      gate.complete();
      await Future.wait([first, ...rest]);
      expect(store.queue.debugTransactionCount, lessThanOrEqualTo(3));
      expect(await _folderCount(store), 51);
    },
  );

  test('at most 256 jobs or 4 MiB of point data per transaction', () async {
    final store = await openStore();
    addTearDown(store.close);
    final gate = Completer<void>();
    final first = store.queue.run((tx) => gate.future);
    await pumpEventQueue(times: 5);
    final jobs = [
      for (var i = 0; i < 600; i++)
        store.queue.run((tx) => tx.putLocal(folder('f$i'), const {kAllFields})),
    ];
    gate.complete();
    await Future.wait([first, ...jobs]);
    // 1 (gate) + 256 + 256 + 88
    expect(store.queue.debugTransactionCount, 4);

    final before = store.queue.debugTransactionCount;
    final big = [
      for (var i = 0; i < 3; i++)
        store.queue.run((tx) async {}, bytes: 3 * 1024 * 1024),
    ];
    await Future.wait(big);
    expect(store.queue.debugTransactionCount - before, 3);
  });

  test(
    'a failed commit is retried after 100 ms, 400 ms, 1.6 s, then every 5 s',
    () {
      _fake((async, store) async {
        store.queue.failNextCommits(5);
        var done = false;
        final write = store.queue
            .run((tx) => tx.putLocal(folder('f1'), const {kAllFields}))
            .then((_) => done = true);
        async.flushMicrotasks();
        expect(store.persistenceStatus.consecutiveFailures, 1);
        expect(store.persistenceStatus.pendingOps, 1);

        void expectFailuresAfter(Duration wait, int failures) {
          async.elapse(wait - const Duration(milliseconds: 1));
          expect(store.persistenceStatus.consecutiveFailures, failures - 1);
          async.elapse(const Duration(milliseconds: 1));
          expect(store.persistenceStatus.consecutiveFailures, failures);
          expect(done, isFalse);
        }

        expectFailuresAfter(const Duration(milliseconds: 100), 2);
        expectFailuresAfter(const Duration(milliseconds: 400), 3);
        expect(
          storageWarningOf(store.storageInfo, store.persistenceStatus),
          StorageWarning.writeFailing,
        );
        expectFailuresAfter(const Duration(milliseconds: 1600), 4);
        expectFailuresAfter(const Duration(seconds: 5), 5);
        expect(await _peekFolders(async, store), 0);

        async.elapse(const Duration(milliseconds: 4999));
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(done, isTrue);
        await write;
        final s = store.persistenceStatus;
        expect(s.consecutiveFailures, 0);
        expect(s.pendingOps, 0);
        expect(s.lastError, isA<FormatException>());
        expect(s.lastCommittedAt, isNotNull);
      });
    },
  );

  test(
    'while retrying, write and flush Futures stay pending; both complete after',
    () {
      _fake((async, store) async {
        store.queue.failNextCommits(3);
        var wrote = false, flushed = false;
        unawaited(
          store.queue
              .run((tx) => tx.putLocal(folder('f1'), const {kAllFields}))
              .then((_) => wrote = true),
        );
        unawaited(store.flush().then((_) => flushed = true));
        async.elapse(const Duration(milliseconds: 2099));
        expect(wrote, isFalse);
        expect(flushed, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(wrote, isTrue);
        expect(flushed, isTrue);
      });
    },
  );

  test(
    'a domain error completes its job without retry and changes nothing',
    () async {
      final store = await openStore();
      addTearDown(store.close);
      final gate = Completer<void>();
      final a = store.queue.run((tx) async {
        await tx.putLocal(folder('a'), const {kAllFields});
        await gate.future;
      });
      await pumpEventQueue(times: 5);
      final b = store.queue.run((tx) async {
        await tx.putLocal(folder('b'), const {kAllFields});
        throw const EntityNotFoundException('note x');
      });
      final c = store.queue.run(
        (tx) => tx.putLocal(folder('c'), const {kAllFields}),
      );
      gate.complete();
      await a;
      await expectLater(b, throwsA(isA<EntityNotFoundException>()));
      await c;
      final ids = {
        for (final r in await store.db.select(store.db.folders).get()) r.id,
      };
      expect(ids, {'a', 'c'});
      expect(store.persistenceStatus.consecutiveFailures, 0);
      // b's outbox record was rolled back with it.
      final outbox = await store.db.select(store.db.outbox).get();
      expect({for (final r in outbox) r.entityId}, {'a', 'c'});
    },
  );

  test('a state error behind a retried commit completes after that commit', () {
    _fake((async, store) async {
      store.queue.failNextCommits(2);
      var aDone = false;
      Object? bError;
      unawaited(
        store.queue
            .run((tx) => tx.putLocal(folder('a'), const {kAllFields}))
            .then((_) => aDone = true),
      );
      unawaited(
        store.queue
            .run<void>((tx) async => throw StateError('no such item'))
            .catchError((Object e) => bError = e),
      );
      async.elapse(const Duration(milliseconds: 499));
      expect(aDone, isFalse);
      expect(bError, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(aDone, isTrue);
      expect(bError, isA<StateError>());
    });
  });

  test(
    'PersistenceStatus: pendingOps, isWriting, latency; stream on changes',
    () async {
      final store = await openStore();
      addTearDown(store.close);
      final seen = <PersistenceStatus>[];
      final sub = store.persistenceStatusStream.listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.single.pendingOps, 0);
      await store.queue.run(
        (tx) => tx.putLocal(folder('f'), const {kAllFields}),
      );
      await pumpEventQueue();
      expect(seen.any((s) => s.pendingOps == 1), isTrue);
      expect(seen.any((s) => s.isWriting), isTrue);
      expect(seen.last.pendingOps, 0);
      expect(seen.last.isWriting, isFalse);
      expect(seen.last.lastCommitLatency, isNotNull);
    },
  );

  test(
    'every write transaction persists hlc.last; it survives reopen',
    () async {
      final dir = await _tempDir();
      final path = '$dir/h.db';
      final a = await openStore(filePath: path);
      await a.queue.run((tx) => tx.putLocal(folder('f'), const {kAllFields}));
      final last = a.hlc.last;
      final kv = await (a.db.select(
        a.db.kv,
      )..where((t) => t.key.equals(KvKeys.hlcLast))).getSingle();
      expect(kv.value, last.toString());
      await a.close();

      final b = await openStore(filePath: path);
      addTearDown(b.close);
      expect(b.hlc.last, last);
      await b.queue.run((tx) => tx.putLocal(folder('g'), const {kAllFields}));
      final g = await readVersionedRow(
        b.db,
        const EntityRef(EntityKind.folder, 'g'),
      );
      expect(g!.versions.max > last, isTrue);
    },
  );

  test(
    'close waits for queued writes; later writes fail with StateError',
    () async {
      final store = await openStore();
      final w = store.queue.run(
        (tx) => tx.putLocal(folder('f'), const {kAllFields}),
      );
      await store.close();
      await w;
      expect(() => store.queue.run((tx) async {}), throwsStateError);
    },
  );

  test('isDomainError', () {
    expect(isDomainError(ArgumentError('x')), isTrue);
    expect(isDomainError(StateError('x')), isTrue);
    expect(isDomainError(const FolderCycleException('x')), isTrue);
    expect(isDomainError(const FormatException('io')), isFalse);
    expect(isDomainError(Exception('io')), isFalse);
  });
}

Future<int> _peekFolders(FakeAsync async, DriftNoteStore store) {
  final f = _folderCount(store);
  async.flushMicrotasks();
  return f;
}

Future<String> _tempDir() async {
  final d = await Directory.systemTemp.createTemp('note_core_wq_');
  addTearDown(() => d.delete(recursive: true));
  return d.path;
}
