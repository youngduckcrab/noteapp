// SyncTestHarness built with fakeAsync (T6): run / elapse / settle on injected virtual time,
// device clocks, checkConverged without matcher. Engine-driven settling (busy engines and
// the settle limit) is covered with the engine (T10).
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
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
      final a = h.device('A');
      a.createNote('pending but not started');
      h.settle(max: const Duration(seconds: 1));
      expect(async.elapsed, Duration.zero);
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
        final a = h.device('A');
        final b = h.device('B');
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
}
