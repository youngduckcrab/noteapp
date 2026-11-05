// Pure Dart: no package:fake_async / test / matcher (contract 7.2.20 v1.1). Virtual time is
// injected by the caller.
import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../auth/auth_service.dart';
import '../auth/auth_user.dart';
import '../codec/canonical_json.dart';
import '../common/server_cursor.dart';
import '../config.dart';
import '../engine/connectivity.dart';
import '../engine/engine_controller.dart';
import '../engine/sync_engine.dart';
import '../status/sync_status.dart';
import 'canonical_dump.dart';
import 'fake_auth_backend.dart';
import 'fake_network.dart';
import 'fake_sync_server.dart';
import 'test_device.dart';

final class SyncTestHarness {
  /// [clock] is the base virtual clock (server time, no device offset); [elapse] advances
  /// virtual time and runs due timers and microtasks; [flushMicrotasks] runs pending
  /// microtasks only. With package:fake_async (test/ only):
  ///   SyncTestHarness(clock: async.getClock(start), elapse: async.elapse,
  ///       flushMicrotasks: async.flushMicrotasks)
  SyncTestHarness({
    required Clock clock,
    required this._elapse,
    required void Function() flushMicrotasks,
    this._seed = 1,
  }) : server = FakeSyncServer(clock: clock),
       _clock = clock,
       _flush = flushMicrotasks;

  final FakeSyncServer server;
  final Clock _clock;
  final void Function(Duration duration) _elapse;
  final void Function() _flush;
  final int _seed;
  final Map<String, TestDevice> _devices = {};

  /// Most differing keys listed by [checkConverged].
  static const int _maxListedKeys = 20;

  /// Longest value text shown per participant by [checkConverged].
  static const int _maxValueChars = 600;

  /// The injected base clock. Every engine's stopwatch comes from it (6.2.4); device clocks
  /// are this plus TestDevice.clockOffset.
  Clock get serverClock => _clock;

  TestDevice device(
    String name, {
    String uid = 'user-1',
    Duration clockOffset = Duration.zero,
    bool signedIn = true,
    SyncConfig? config,
    Duration latency = const Duration(milliseconds: 50),
  }) {
    if (_devices.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'device already exists');
    }
    final index = _devices.length;
    final link = FakeNetworkLink(latency: latency);
    final connectivity = ManualConnectivitySignal();
    final user = AuthUser(uid: uid);
    final auth = FakeAuthBackend(user: signedIn ? user : null)
      ..nextSignInUser = user;
    final device = TestDevice.internal(
      name: name,
      uid: uid,
      nodeId: nodeIdOf(name),
      baseClock: _clock,
      clockOffset: clockOffset,
      link: link,
      connectivity: connectivity,
      auth: auth,
      engine: (d) => SyncEngine(
        local: d.store,
        auth: AuthService(auth),
        backendFactory: (u) async => server.connect(uid: u.uid, link: link),
        config: config ?? const SyncConfig(),
        connectivity: connectivity,
        clock: d.clock,
        random: Random(_seed * 1000 + index),
        stopwatch: _clock.stopwatch,
      ),
    );
    _devices[name] = device;
    // The engine follows the device's auth state from now on: signed in → attach, push and
    // receive as virtual time moves (settle / elapse / run).
    unawaited(device.startEngine());
    return device;
  }

  /// The HLC node of the device called [name]: 16 hex of sha-256('sync-test-device:name').
  @internal
  static String nodeIdOf(String name) => sha256
      .convert('sync-test-device:$name'.codeUnits)
      .toString()
      .substring(0, 16);

  /// Flushes microtasks, then calls elapse([step]) until [future] completes; returns its
  /// value or rethrows its error. StateError after [timeout] of virtual time.
  T run<T>(
    Future<T> future, {
    Duration timeout = const Duration(minutes: 10),
    Duration step = const Duration(milliseconds: 10),
  }) {
    if (step <= Duration.zero) {
      throw ArgumentError.value(step, 'step', 'must be positive');
    }
    var done = false;
    late T value;
    Object? error;
    StackTrace? stack;
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e, StackTrace s) {
        error = e;
        stack = s;
        done = true;
      },
    );
    _flush();
    var waited = Duration.zero;
    while (!done) {
      if (waited >= timeout) {
        throw StateError(
          'SyncTestHarness.run: future not done after $timeout of virtual time',
        );
      }
      _elapse(step);
      waited += step;
    }
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return value;
  }

  /// Calls the injected elapse, then flushMicrotasks.
  void elapse(Duration duration) {
    _elapse(duration);
    _flush();
  }

  /// Elapses (in 10 ms steps) until every engine is idle (no pending, not pushing, no
  /// queued work, live or offline) or [max] (then StateError naming the busy devices).
  void settle({Duration max = const Duration(minutes: 5)}) {
    const step = Duration(milliseconds: 10);
    _flush();
    var waited = Duration.zero;
    while (true) {
      final busy = <String>[
        for (final d in _devices.values)
          if (d.busyReason ?? _receiving(d) case final reason?)
            '${d.name}: $reason',
      ];
      if (busy.isEmpty) return;
      if (waited >= max) {
        throw StateError(
          'SyncTestHarness.settle: still busy after $max of virtual time — '
          '${busy.join(', ')}',
        );
      }
      elapse(step);
      waited += step;
    }
  }

  /// A live device whose cursor is behind the newest chunk the server shows its account:
  /// the live query has not delivered it yet.
  String? _receiving(TestDevice d) {
    final engine = EngineController.of(d.engine);
    final uid = engine.attachedUid;
    if (uid == null || engine.status.phase != SyncPhase.live) return null;
    final now = ServerCursor.fromDateTime(_clock.now());
    ServerCursor? newest;
    for (final stored in server.chunksOf(uid)) {
      if (stored.visibleAt > now) continue;
      final t = stored.chunk.serverTime;
      if (newest == null || t > newest) newest = t;
    }
    if (newest == null) return null;
    final cursor = engine.cursor;
    if (cursor != null && cursor >= newest) return null;
    return 'receiving (cursor $cursor < $newest)';
  }

  /// Convergence check without matcher: canonicalDump() equal on all devices (and equal to
  /// server.mergedState when [includeServer]); Note.updatedAt is left out on both sides
  /// (5.1.2 S-11). Throws StateError whose message lists every differing key (first 20)
  /// with each device's value; returns normally when converged.
  void checkConverged(
    Iterable<TestDevice> devices, {
    bool includeServer = true,
  }) {
    final list = devices.toList();
    if (list.isEmpty) {
      throw ArgumentError.value(devices, 'devices', 'is empty');
    }
    final participants = <(String, Map<String, Object?>)>[
      for (final d in list) (d.name, d.store.canonicalDump()),
      if (includeServer)
        for (final uid in {for (final d in list) d.uid})
          ('server($uid)', _serverDump(uid)),
    ];
    final keys = <String>{
      for (final (_, dump) in participants) ...dump.keys,
    }.toList()..sort();
    final differing = <String>[];
    for (final key in keys) {
      final texts = {for (final (_, dump) in participants) _text(dump, key)};
      if (texts.length > 1) differing.add(key);
    }
    if (differing.isEmpty) return;
    final names = [for (final (name, _) in participants) name];
    final out = StringBuffer(
      'checkConverged: ${differing.length} of ${keys.length} keys differ '
      'across ${names.join(', ')}',
    );
    for (final key in differing.take(_maxListedKeys)) {
      out.write('\n  $key');
      for (final (name, dump) in participants) {
        var text = _text(dump, key);
        if (text.length > _maxValueChars) {
          text = '${text.substring(0, _maxValueChars)}…';
        }
        out.write('\n    $name: $text');
      }
    }
    if (differing.length > _maxListedKeys) {
      out.write('\n  … and ${differing.length - _maxListedKeys} more');
    }
    throw StateError(out.toString());
  }

  static String _text(Map<String, Object?> dump, String key) =>
      dump.containsKey(key) ? canonicalJson(dump[key]) : '<missing>';

  /// server.mergedState(uid) in the canonicalDump form: each record decoded by CORE and
  /// re-encoded, so both sides use entity.toJson().
  Map<String, Object?> _serverDump(String uid) {
    final entries = <MapEntry<String, Object?>>[];
    for (final record in server.mergedState(uid).values) {
      final key = dumpKeyOf(record.doc.kind, record.doc.id);
      try {
        final entity = record.doc.toEntity();
        entries.add(MapEntry(key, dumpValueOf(entity, record.versions)));
      } on FormatException catch (e) {
        entries.add(MapEntry(key, {'undecodable': e.message}));
      }
    }
    entries.sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }
}
