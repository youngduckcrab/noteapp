// Engine tests on the SyncTestHarness without the 'scenario' tag (T10): test() + fakeAsync,
// and a log of what an engine published.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

/// Virtual start of every engine test: 2026-11-01T00:00:00Z.
final DateTime kEngineStart = DateTime.utc(2026, 11, 1);

/// test() with a SyncTestHarness on fakeAsync virtual time.
void harnessTest(
  String description,
  void Function(SyncTestHarness h, FakeAsync async) body, {
  int seed = 1,
}) {
  test(description, () {
    fakeAsync((async) {
      body(
        SyncTestHarness(
          clock: async.getClock(kEngineStart),
          elapse: async.elapse,
          flushMicrotasks: async.flushMicrotasks,
          seed: seed,
        ),
        async,
      );
    }, initialTime: kEngineStart);
  });
}

/// Everything [engine] publishes from now on: statuses, distinct phases, notices.
final class EngineLog {
  EngineLog(SyncEngine engine) {
    _subs
      ..add(
        engine.statusStream.listen((s) {
          statuses.add(s);
          if (phases.isEmpty || phases.last != s.phase) phases.add(s.phase);
        }),
      )
      ..add(engine.notices.listen(notices.add));
  }

  final List<SyncStatus> statuses = [];
  final List<SyncPhase> phases = [];
  final List<SyncNotice> notices = [];
  final List<StreamSubscription<Object?>> _subs = [];

  /// Phases seen since the last call (the current one stays as the first of the next).
  List<SyncPhase> takePhases() {
    final out = List.of(phases);
    phases
      ..clear()
      ..add(out.last);
    return out;
  }

  void cancel() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
  }
}

/// The engine's active issue with [code], or null.
SyncIssue? issueOf(TestDevice device, SyncIssueCode code) {
  for (final i in device.engine.status.issues) {
    if (i.code == code) return i;
  }
  return null;
}

int nowMillis(SyncTestHarness h) => h.serverClock.now().millisecondsSinceEpoch;

/// Now on [d]'s wall clock (base + clockOffset), ms.
int deviceMillis(SyncTestHarness h, TestDevice d) =>
    nowMillis(h) + d.clockOffset.inMilliseconds;

/// Elapses past the engine's nextRetryAt (device clock, ms; jittered delays end inside that
/// ms).
void untilRetry(SyncTestHarness h, TestDevice d) {
  final at = d.engine.status.nextRetryAt!;
  h.elapse(Duration(milliseconds: at - deviceMillis(h, d) + 1));
}

/// A device that is live after settle, with one note synced (so it has a cursor).
TestDevice liveDevice(
  SyncTestHarness h,
  String name, {
  SyncConfig? config,
  Duration clockOffset = Duration.zero,
}) {
  final d = h.device(name, config: config, clockOffset: clockOffset);
  d.createNote('$name seed');
  h.settle();
  expect(d.engine.status.phase, SyncPhase.live, reason: '$name live');
  expect(d.engine.debug.cursor, isNotNull);
  return d;
}

/// The server's merged state of 'user-1' has the note.
bool onServer(SyncTestHarness h, String noteId, {String uid = 'user-1'}) =>
    h.server.mergedState(uid).containsKey(EntityRef(EntityKind.note, noteId));
