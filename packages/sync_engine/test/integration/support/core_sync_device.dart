// T16-v2 (integration stage 3 — 07-sync 6.7.2): the devices of the 2nd-round real-CORE
// scenarios. Like 1st-round core_scenarios_test: no harness, real time — each device is a
// real CORE store on its own SQLite file (CoreTestStore: openTestNoteStore(filePath:)) through
// CoreSyncLocalStore with its own SyncEngine, all on one FakeSyncServer with a real-time
// clock. Tests wait for states (50 ms polls, one 3 min budget per test — real_time.dart) and
// never assert durations. Convergence = the canonical dump (4.11) of every entity the
// scenario touched (notes, pages, active strokes and objects, the pages' handwriting results,
// active recordings, plus the refs a test names), read with SyncStore.readVersioned on every
// device.
//
// A device can start like an older app (knownKinds → EngineController.debugKnownKinds, 6.3.8)
// and restart on the same file — the engine disposed, the store closed and opened again, a
// new engine (the app update of K2).
//
// Before the CORE milestones of 6.7.2's table these tests fail with CORE's own
// UnimplementedError('CORE T…: …'): a local write throws it at once, and one that only the
// engine sees (applyRemote of a new kind on receive) is caught from the engine's log and
// rethrown by the next wait — so a run before the milestone fails at once with the task
// number instead of spending the wait budget.
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/src/codec/chunk_id.dart';
import 'package:sync_engine/src/engine/engine_controller.dart';
import 'package:sync_engine/src/testing/canonical_dump.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'core_store_driver.dart';
import 'real_time.dart';

const String kT16Uid = 'user-1';
const AuthUser _user = AuthUser(uid: kT16Uid);

/// Every kind but handwriting: the app before M7 (K2).
final Set<EntityKind> kKindsWithoutHandwriting = EntityKind.values.toSet()
  ..remove(EntityKind.handwriting);

/// Registers a T16-v2 test: a fresh [CoreScenario] per test, closed afterwards.
void coreScenario(
  String description,
  Future<void> Function(CoreScenario s) body,
) {
  test(description, () async {
    final s = CoreScenario();
    try {
      await body(s);
    } finally {
      await s.close();
    }
  }, timeout: kIntegrationTimeout);
}

/// One test's server, devices and waits.
final class CoreScenario {
  final FakeSyncServer server = FakeSyncServer(clock: const Clock());
  final RealTimeWaits _waits = RealTimeWaits();
  final List<CoreSyncDevice> _devices = [];

  /// CORE work an engine met that the store does not have yet (UnimplementedError).
  final List<UnimplementedError> coreGaps = [];

  Future<CoreSyncDevice> device(
    String name, {
    Set<EntityKind>? knownKinds,
  }) async {
    final d = await CoreSyncDevice._open(name, this, knownKinds: knownKinds);
    _devices.add(d);
    return d;
  }

  /// Polls [done] within the test's budget; rethrows the first CORE gap an engine logged.
  Future<void> until(String what, FutureOr<bool> Function() done) =>
      _waits.until(what, () {
        if (coreGaps.isNotEmpty) throw coreGaps.first;
        return done();
      });

  /// Every device in [devices] idle, then the dumps of every entity any of them knows of
  /// [notes] (plus [extra]) equal on all of them.
  Future<void> converge(
    List<CoreSyncDevice> devices,
    Iterable<NoteId> notes, {
    Iterable<EntityRef> extra = const [],
  }) async {
    late List<Map<String, Object?>> dumps;
    await until(
      '${devices.map((d) => d.name).join(', ')} to converge',
      () async {
        if (!devices.every((d) => d.idle)) return false;
        final refs = <EntityRef>{
          for (final d in devices) ...await d.refsOf(notes, extra: extra),
        };
        dumps = [for (final d in devices) await d.dumpOf(refs)];
        return dumps.every(
          (dump) => const DeepCollectionEquality().equals(dump, dumps.first),
        );
      },
    );
    for (final (i, dump) in dumps.indexed.skip(1)) {
      expect(dump, dumps.first, reason: devices[i].name);
    }
  }

  /// Every device idle.
  Future<void> settle(List<CoreSyncDevice> devices) => until(
    '${devices.map((d) => d.name).join(', ')} idle',
    () => devices.every((d) => d.idle),
  );

  Future<void> close() async {
    for (final d in _devices) {
      await d._close();
    }
    _devices.clear();
  }
}

/// A device: real CORE + CoreSyncLocalStore + SyncEngine, signed in as [kT16Uid].
final class CoreSyncDevice {
  CoreSyncDevice._(this.name, this._scenario, this.core);

  static Future<CoreSyncDevice> _open(
    String name,
    CoreScenario scenario, {
    Set<EntityKind>? knownKinds,
  }) async {
    final nodeId = sha256
        .convert('core-v2-scenario:$name'.codeUnits)
        .toString()
        .substring(0, 16);
    final d = CoreSyncDevice._(
      name,
      scenario,
      await CoreTestStore.open(deviceNodeId: nodeId),
    );
    await d._startEngine(knownKinds);
    return d;
  }

  final String name;
  final CoreScenario _scenario;

  /// The CORE store; a new one (same file) after [restart].
  CoreTestStore core;
  final FakeNetworkLink link = FakeNetworkLink(
    latency: const Duration(milliseconds: 20),
  );
  final ManualConnectivitySignal connectivity = ManualConnectivitySignal();
  final FakeAuthBackend auth = FakeAuthBackend(user: _user);
  late AuthService _authService;
  late SyncEngine engine;

  NoteStore get store => core.store;

  /// CORE's SyncStore itself (reads; the engine has it through CoreSyncLocalStore).
  SyncStore get sync => core.local.sync;

  EpochMillis get now => store.clock.now().millisecondsSinceEpoch;

  String newId() => store.ids.newId();

  /// The ids of [noteId]'s active pages, in page order.
  Future<List<PageId>> pageIdsOf(NoteId noteId) async => [
    for (final p in await store.content.pagesOf(noteId)) p.id,
  ];

  Future<void> _startEngine(Set<EntityKind>? knownKinds) async {
    _authService = AuthService(auth);
    engine = SyncEngine(
      local: core.local,
      auth: _authService,
      backendFactory: (u) async =>
          _scenario.server.connect(uid: u.uid, link: link),
      connectivity: connectivity,
      clock: store.clock,
      random: Random(name.length * 7919 + name.codeUnitAt(0)),
      log: _log,
    );
    if (knownKinds != null) {
      EngineController.of(engine).debugKnownKinds = knownKinds;
    }
    await engine.start();
  }

  void _log(SyncLogLevel level, String message, {Object? error}) {
    if (error is UnimplementedError) _scenario.coreGaps.add(error);
  }

  Future<void> _stopEngine() async {
    core.healCommits();
    await engine.dispose();
    await _authService.dispose();
  }

  /// The app restarts (an app update when [knownKinds] grows): the engine is disposed, the
  /// store closed and opened again on the same file, [whileStopped] runs on the reopened
  /// store before a new engine (knowing [knownKinds], null = every kind) starts.
  Future<void> restart({
    Set<EntityKind>? knownKinds,
    Future<void> Function()? whileStopped,
  }) async {
    await _stopEngine();
    core = await core.reopen();
    if (whileStopped != null) await whileStopped();
    await _startEngine(knownKinds);
  }

  Future<void> _close() async {
    await _stopEngine();
    await core.close();
  }

  void goOffline() {
    link.setOnline(false);
    connectivity.set(false);
  }

  void goOnline() {
    link.setOnline(true);
    connectivity.set(true);
  }

  bool get idle {
    final s = engine.status;
    return s.phase == SyncPhase.live && s.pendingUploads == 0 && !s.isPushing;
  }

  /// The engine's current issue with [code], or null.
  SyncIssue? issue(SyncIssueCode code) {
    for (final i in engine.status.issues) {
      if (i.code == code) return i;
    }
    return null;
  }

  Future<VersionedEntity?> read(EntityKind kind, String id) async =>
      (await sync.readVersioned([EntityRef(kind, id)])).single;

  /// The entity JSON of [kind] / [id] (deleted rows too), or null.
  Future<Map<String, Object?>?> jsonOf(EntityKind kind, String id) async =>
      (await read(kind, id))?.entity.toJson();

  /// Every entity under [notes] — the note, its active pages with their strokes, objects and
  /// handwriting result ids, its active recordings — plus [extra].
  Future<Set<EntityRef>> refsOf(
    Iterable<NoteId> notes, {
    Iterable<EntityRef> extra = const [],
  }) async {
    final refs = <EntityRef>{...extra};
    for (final n in notes) {
      refs.add(EntityRef(EntityKind.note, n));
      for (final page in await store.content.pagesOf(n)) {
        refs
          ..add(EntityRef(EntityKind.page, page.id))
          ..add(
            EntityRef(EntityKind.handwriting, HandwritingText.idFor(page.id)),
          );
        final content = await store.content.loadPage(page.id);
        for (final s in content.strokes) {
          refs.add(EntityRef(EntityKind.stroke, s.id));
        }
        for (final o in content.objects) {
          refs.add(EntityRef(EntityKind.pageObject, o.id));
        }
      }
      for (final r in await store.recordings.recordingsOf(n)) {
        refs.add(EntityRef(EntityKind.recording, r.id));
      }
    }
    return refs;
  }

  Future<Map<String, Object?>> dumpOf(Iterable<EntityRef> refs) async =>
      canonicalDumpOf(
        (await sync.readVersioned(refs.toList())).whereType<VersionedEntity>(),
      );

  /// The ids of [pageId]'s active objects.
  Future<List<ElementId>> objectIdsOf(PageId pageId) async => [
    for (final o in await core.objectsOf(pageId)) o.id,
  ];
}

/// A few real milliseconds, so that the next local edit's HLC is later than every edit made
/// so far on any device (all devices read the same wall clock). Orders edits; asserts nothing.
Future<void> nextMillisecond() =>
    Future<void>.delayed(const Duration(milliseconds: 5));

/// The notices of type [T] every device in [devices] raises from now on.
({List<T> seen, Future<void> Function() cancel})
listenNotices<T extends SyncNotice>(List<CoreSyncDevice> devices) {
  final seen = <T>[];
  final subs = [
    for (final d in devices)
      d.engine.notices.listen((n) {
        if (n is T) seen.add(n);
      }),
  ];
  return (
    seen: seen,
    cancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
}

// ---- records a newer app writes (K1, U1) ---------------------------------------------------

/// The node of the "newer app" whose records the tests commit with FakeSyncServer.commitRaw.
const String kNewerAppNode = 'c5c5c5c5c5c5c5c5';

/// The newer app's local store: its writes give the versioned rows a newer app would upload.
FakeLocalStore newerAppStore() => FakeLocalStore(
  nodeId: kNewerAppNode,
  clock: const Clock(),
  ownerId: kT16Uid,
);

/// A delta chunk of encoded [records] by [kNewerAppNode] in [scope].
ChunkWrite newerAppChunk(
  List<Uint8List> records, {
  required String scope,
  required Hlc maxHlc,
}) {
  final payload = ChunkCodec.assemble(records);
  return ChunkWrite(
    id: chunkIdOf(kNewerAppNode, payload),
    scope: scope,
    authorNodeId: kNewerAppNode,
    recordCount: records.length,
    format: ChunkCodec.formatVersion,
    kind: ChunkKind.delta,
    maxHlc: maxHlc.toString(),
    payload: payload,
  );
}

/// The upsert record of [ref] as [store] holds it.
UpsertRecord upsertOf(FakeLocalStore store, EntityRef ref) =>
    UpsertRecord.fromVersioned(store.rows[ref]!);
