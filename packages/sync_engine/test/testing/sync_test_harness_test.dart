// SyncTestHarness built with fakeAsync (T6): run / elapse / settle on injected virtual time,
// device clocks, checkConverged without matcher. Devices start their engines (T10); tests that
// build server state by hand use signed-out devices so no engine touches it. (2nd round,
// S2-4b — 07-sync 4.3, 6.3.8) device(knownKinds:) = an older app, restart(name) = app restart
// / update on the same store, checkConverged(kinds:) filters every participant's dump.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/engine/engine_controller.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../scenarios/support/sync_scenario.dart';

final DateTime start = DateTime.utc(2026, 11, 1);

void withHarness(void Function(SyncTestHarness h, FakeAsync async) body) {
  fakeAsync((async) {
    body(
      SyncTestHarness(
        clock: async.getClock(start),
        elapse: async.elapse,
        flushMicrotasks: async.flushMicrotasks,
      ),
      async,
    );
  }, initialTime: start);
}

/// One chunk holding every row of [device] (as its engine would upload them).
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
  group('run', () {
    test('returns the value and advances virtual time in steps', () {
      withHarness((h, async) {
        final value = h.run(
          Future<int>.delayed(const Duration(seconds: 1), () => 7),
        );
        expect(value, 7);
        expect(async.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
        expect(async.elapsed, lessThan(const Duration(milliseconds: 1010)));
        expect(h.serverClock.now(), start.add(async.elapsed));
      });
    });

    test('completes a microtask-only future without elapsing', () {
      withHarness((h, async) {
        expect(h.run(Future.value('x')), 'x');
        expect(async.elapsed, Duration.zero);
      });
    });

    test('rethrows the error of the future', () {
      withHarness((h, async) {
        expect(
          () => h.run(
            Future<void>.delayed(
              const Duration(milliseconds: 30),
              () => throw const FormatException('boom'),
            ),
          ),
          throwsFormatException,
        );
      });
    });

    test('throws StateError after the timeout of virtual time', () {
      withHarness((h, async) {
        expect(
          () => h.run(
            Completer<void>().future,
            timeout: const Duration(minutes: 1),
            step: const Duration(seconds: 1),
          ),
          throwsStateError,
        );
        expect(async.elapsed, const Duration(minutes: 1));
      });
    });
  });

  test('elapse moves virtual time and runs due timers', () {
    withHarness((h, async) {
      var fired = false;
      Timer(const Duration(seconds: 5), () => fired = true);
      h.elapse(const Duration(seconds: 4));
      expect(fired, isFalse);
      h.elapse(const Duration(seconds: 1));
      expect(fired, isTrue);
      expect(async.elapsed, const Duration(seconds: 5));
    });
  });

  test('settle returns at once when no engine has work', () {
    withHarness((h, async) {
      final a = h.device('A', signedIn: false);
      a.createNote('pending while signed out');
      h.settle(max: const Duration(seconds: 1));
      expect(async.elapsed, Duration.zero);
    });
  });

  test('settle waits until the engines have connected and exchanged their '
      'changes', () {
    withHarness((h, async) {
      final a = h.device('A');
      final b = h.device('B');
      final n = a.createNote('N');
      h.settle();
      expect(async.elapsed, greaterThan(Duration.zero));
      expect(a.engine.status.phase, SyncPhase.live);
      expect(b.engine.status.phase, SyncPhase.live);
      expect(b.doc(EntityKind.note, n), isNotNull);
      h.checkConverged([a, b]);
    });
  });

  test('settle limit: StateError naming each busy device and why', () {
    withHarness((h, async) {
      final a = h.device('A');
      final b = h.device('B');
      h.settle();
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.aborted),
        op: FakeOp.commit,
        times: 1000,
      );
      a.createNote('never acknowledged');
      final before = async.elapsed;
      expect(
        () => h.settle(max: const Duration(minutes: 1)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('still busy after 0:01:00'),
              contains('A: '),
              isNot(contains('B: ')),
            ),
          ),
        ),
      );
      expect(async.elapsed - before, const Duration(minutes: 1));
      expect(b.engine.status.phase, SyncPhase.live);
    });
  });

  group('device', () {
    test('device clock = base clock + clockOffset; the base clock does not '
        'move with it', () {
      withHarness((h, async) {
        final a = h.device('A');
        final b = h.device('B', clockOffset: const Duration(hours: 1));
        expect(a.clockOffset, Duration.zero);
        expect(b.clockOffset, const Duration(hours: 1));
        final n = b.createNote('N');
        final created = b.store.rows[EntityRef(EntityKind.note, n)]!;
        final expected = start.add(const Duration(hours: 1));
        expect(created.entity.version!.millis, expected.millisecondsSinceEpoch);
        expect(
          (created.entity as Note).createdAt,
          expected.millisecondsSinceEpoch,
        );
        b.clockOffset = const Duration(hours: -2);
        h.elapse(const Duration(hours: 3));
        final m = b.createNote('M');
        expect(
          (b.store.rows[EntityRef(EntityKind.note, m)]!.entity as Note)
              .createdAt,
          start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        );
        expect(h.serverClock.now(), start.add(const Duration(hours: 3)));
        final an = a.createNote('A');
        expect(
          (a.store.rows[EntityRef(EntityKind.note, an)]!.entity as Note)
              .createdAt,
          start.add(const Duration(hours: 3)).millisecondsSinceEpoch,
        );
      });
    });

    test('names are unique; node ids are 16 hex, distinct and stable', () {
      withHarness((h, async) {
        final a = h.device('A');
        final b = h.device('B', uid: 'user-2', signedIn: false);
        expect(() => h.device('A'), throwsArgumentError);
        expect(a.store.sync.deviceNodeId, matches(RegExp(r'^[0-9a-f]{16}$')));
        expect(a.store.sync.deviceNodeId, isNot(b.store.sync.deviceNodeId));
        expect(a.store.sync.deviceNodeId, SyncTestHarness.nodeIdOf('A'));
        expect(a.name, 'A');
        expect(b.auth.nextSignInUser, const AuthUser(uid: 'user-2'));
        expect(a.link.latency, const Duration(milliseconds: 50));
        expect(
          h
              .device('C', latency: const Duration(milliseconds: 150))
              .link
              .latency,
          const Duration(milliseconds: 150),
        );
      });
    });
  });

  group('checkConverged', () {
    test('passes for equal devices, reports differing keys with every '
        "device's value", () {
      withHarness((h, async) {
        final a = h.device('A');
        final b = h.device('B');
        a.seedDefaultPresets();
        b.seedDefaultPresets();
        h.checkConverged([a, b], includeServer: false);
        a.renamePreset('preset-default-pencil', '샤프');
        Object? error;
        try {
          h.checkConverged([a, b], includeServer: false);
        } catch (e) {
          error = e;
        }
        expect(error, isA<StateError>());
        final message = (error! as StateError).message;
        expect(message, contains('1 of 5 keys differ across A, B'));
        expect(message, contains('penPreset/preset-default-pencil'));
        expect(message, contains('A: {'));
        expect(message, contains('B: {'));
        expect(message, contains('샤프'));
        expect(message, isNot(contains('preset-default-marker')));
      });
    });

    test('lists at most 20 keys and shows missing rows', () {
      withHarness((h, async) {
        final a = h.device('A');
        final b = h.device('B');
        for (var i = 0; i < 25; i++) {
          a.createFolder('f$i');
        }
        final message = (() {
          try {
            h.checkConverged([a, b], includeServer: false);
          } on StateError catch (e) {
            return e.message;
          }
          return '';
        })();
        expect(message, contains('25 of 25 keys differ'));
        expect(message, contains('B: <missing>'));
        expect(message, contains('… and 5 more'));
        expect('\n  folder/'.allMatches(message), hasLength(20));
      });
    });

    test("compares with the server's merged state when includeServer", () {
      withHarness((h, async) {
        final a = h.device('A', signedIn: false);
        final b = h.device('B', signedIn: false);
        for (final d in [a, b]) {
          d.seedDefaultPresets();
          h.run(d.store.sync.reassignOwner(from: kLocalOwnerId, to: 'user-1'));
        }
        expect(
          () => h.checkConverged([a, b]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('server(user-1): <missing>'), contains('5 of 5')),
            ),
          ),
        );
        h.server.commitRaw('user-1', [chunkOf(a)]);
        h.checkConverged([a, b]);
        h.checkConverged([a]);
      });
    });

    test('ignores Note.updatedAt on every side', () {
      withHarness((h, async) {
        final a = h.device('A');
        final b = h.device('B');
        final n = a.createNote('N');
        final noteRow = a.store.rows[EntityRef(EntityKind.note, n)]!;
        final pageRow =
            a.store.rows[EntityRef(EntityKind.page, a.pageIdsOf(n).single)]!;
        final later = (noteRow.entity as Note).updatedAt + 3600000;
        h.run(
          b.store.sync.applyRemote([
            RemoteUpsert(
              EntityJson.decode(EntityKind.note, {
                ...noteRow.entity.toJson(),
                'updatedAt': later,
              }),
              noteRow.versions,
            ),
            RemoteUpsert(pageRow.entity, pageRow.versions),
          ], policy: (l, r, p) => const TakeRemote()),
        );
        expect(
          (b.store.rows[EntityRef(EntityKind.note, n)]!.entity as Note)
              .updatedAt,
          later,
        );
        h.checkConverged([a, b], includeServer: false);
      });
    });

    test('needs at least one device', () {
      withHarness((h, async) {
        expect(() => h.checkConverged(const []), throwsArgumentError);
      });
    });
  });

  syncScenario('syncScenario builds the harness on virtual time from '
      'kScenarioStart', (h) {
    expect(h.serverClock.now(), kScenarioStart);
    h.elapse(const Duration(days: 30));
    expect(h.serverClock.now(), kScenarioStart.add(const Duration(days: 30)));
    final a = h.device('A');
    expect(a.store.clock.now(), h.serverClock.now());
  });

  group('2nd round: knownKinds, restart, checkConverged(kinds:)', () {
    final noHandwriting = EntityKind.values.toSet()
      ..remove(EntityKind.handwriting);

    test('knownKinds: an old-app device applies the known records of a mixed '
        'chunk, holds the handwriting (debug.heldRecords, sync.heldRecords) and '
        'reports needsAppUpdate; restart with every kind → re-applied → '
        'converged', () {
      withHarness((h, async) {
        final a = h.device('A');
        final old = h.device('B', knownKinds: noHandwriting);
        expect(EngineController.of(a.engine).debugKnownKinds, isNull);
        expect(EngineController.of(old.engine).debugKnownKinds, noHandwriting);
        final n = a.createNote('N');
        final p = a.pageIdsOf(n).single;
        final s = a.addStroke(p);
        a.putHandwriting(p, ['hello']);
        h.settle();
        // One push: the stroke and the handwriting result travel in one chunk.
        final chunks = [
          for (final c in h.server.chunksOf('user-1'))
            if (c.chunk.scope == n) c,
        ];
        expect(chunks, hasLength(1));
        expect(old.doc(EntityKind.stroke, s), isNotNull);
        expect(old.handwritingOf(p), isNull);
        expect(
          old.doc(EntityKind.handwriting, HandwritingText.idFor(p)),
          isNull,
        );
        final issue = old.engine.status.issues.singleWhere(
          (i) => i.code == SyncIssueCode.needsAppUpdate,
        );
        expect(
          issue.message,
          '1 record(s) of kind handwriting held until the '
          'app is updated',
        );
        expect(
          a.engine.status.issues.where(
            (i) => i.code == SyncIssueCode.needsAppUpdate,
          ),
          isEmpty,
        );
        // (S2-7a) Held, not dropped: the record waits in sync.heldRecords.
        expect(old.engine.debug.heldRecords, 1);
        expect(old.engine.debug.heldRecordsMarked, isFalse);
        expect(a.engine.debug.heldRecords, 0);
        expect(old.store.meta['sync.heldRecords'], isNotEmpty);
        expect(old.store.meta['sync.heldRecords.1'], contains('"handwriting"'));
        expect(a.store.meta['sync.heldRecords'] ?? '', isEmpty);
        h.checkConverged([a, old], kinds: noHandwriting);
        expect(
          () => h.checkConverged([a, old]),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('handwriting/${HandwritingText.idFor(p)}'),
                contains('B: <missing>'),
              ),
            ),
          ),
        );
        h.checkConverged([a]);
        // (S2-7b) The app update: restart with every kind → re-applied → converged.
        h.restart('B');
        h.settle();
        expect(old.handwritingOf(p), isNotNull);
        expect(old.engine.debug.reappliedRecords, 1);
        expect(old.engine.debug.heldRecords, 0);
        expect(old.store.meta['sync.heldRecords'], '');
        h.checkConverged([a, old]);
      });
    });

    test('restart: the same TestDevice and store with a new engine; rows, '
        'outbox and meta stay; the new engine attaches and pushes', () {
      withHarness((h, async) {
        final a = h.device('A');
        final b = h.device('B');
        a.createNote('N');
        h.settle();
        expect(a.store.meta[MetaKeys.cursor], isNotNull);
        a.goOffline();
        final m = a.createNote('M');
        final first = a.engine;
        final store = a.store;
        final outbox = a.store.outbox;
        final meta = Map.of(a.store.meta);
        final dump = a.store.canonicalDump();
        expect(outbox, isNotEmpty);
        final again = h.restart('A');
        expect(again, same(a));
        expect(a.engine, isNot(same(first)));
        expect(a.store, same(store));
        expect(a.store.outbox, outbox);
        expect(a.store.meta, meta);
        expect(a.store.canonicalDump(), dump);
        expect(EngineController.of(a.engine).isStarted, isTrue);
        expect(EngineController.of(a.engine).debugKnownKinds, isNull);
        a.goOnline();
        h.settle();
        expect(a.engine.status.phase, SyncPhase.live);
        expect(a.store.outbox, isEmpty);
        expect(b.doc(EntityKind.note, m), isNotNull);
        h.checkConverged([a, b]);
        // An edit after the restart goes through the new engine only.
        final before = h.server.chunksOf('user-1').length;
        a.renameNote(m, 'M2');
        h.settle();
        expect(h.server.chunksOf('user-1').length, before + 1);
        expect(b.doc(EntityKind.note, m)!.json['title'], 'M2');
      });
    });

    test('restart(knownKinds:) sets the codec kinds of the new engine; '
        'unknown names are refused', () {
      withHarness((h, async) {
        final b = h.device('B');
        h.settle();
        h.restart('B', knownKinds: noHandwriting);
        expect(EngineController.of(b.engine).debugKnownKinds, noHandwriting);
        h.settle();
        expect(b.engine.status.phase, SyncPhase.live);
        h.restart('B');
        expect(EngineController.of(b.engine).debugKnownKinds, isNull);
        expect(() => h.restart('Z'), throwsArgumentError);
        expect(
          () => EngineController.of(b.engine).debugKnownKinds = noHandwriting,
          throwsStateError,
          reason: 'only before start()',
        );
      });
    });

    test('checkConverged(kinds:) ignores differences in the other kinds and '
        'reports those in the given kinds, on every participant', () {
      withHarness((h, async) {
        final a = h.device('A', signedIn: false);
        final b = h.device('B', signedIn: false);
        a.seedDefaultPresets();
        b.seedDefaultPresets();
        final n = a.createNote('N');
        expect(
          () => h.checkConverged([a, b], includeServer: false),
          throwsStateError,
        );
        h.checkConverged(
          [a, b],
          includeServer: false,
          kinds: {EntityKind.penPreset},
        );
        expect(
          () => h.checkConverged(
            [a, b],
            includeServer: false,
            kinds: {EntityKind.penPreset, EntityKind.note},
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('1 of 6 keys differ across A, B'),
                contains('note/$n'),
                isNot(contains('page/')),
              ),
            ),
          ),
        );
        a.renamePreset('preset-default-pencil', '샤프');
        expect(
          () => h.checkConverged(
            [a, b],
            includeServer: false,
            kinds: {EntityKind.penPreset},
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('penPreset/preset-default-pencil'),
            ),
          ),
        );
        // The server's merged state is filtered too (it is empty here).
        h.checkConverged([a], kinds: {EntityKind.setting});
        expect(
          () => h.checkConverged([a], kinds: {EntityKind.note}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('server(user-1): <missing>'), contains('1 of 1')),
            ),
          ),
        );
        expect(
          () => h.checkConverged([a, b], kinds: const {}),
          throwsArgumentError,
        );
      });
    });
  });
}
