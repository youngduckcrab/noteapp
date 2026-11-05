// T16 (integration stage, contract 7.7 step 5 v1.2 — C12-05 "실제 CORE 2개로 S01·S02·S05·
// S15"): the scenarios of 9.1.2 with two real CORE stores (openTestNoteStore through
// CoreSyncLocalStore), each with its own SyncEngine, on one FakeSyncServer. Real CORE runs
// on the real event loop, so these tests wait for states (polling, one real-time budget
// per test — support/real_time.dart) and never assert durations. Edits go through CORE the
// way the app makes them (library, sessions, pen presets). Convergence = the canonical dump
// (4.11) of every entity the scenario touched, read with SyncStore.readVersioned on both
// stores; S15 leaves the meta keys of the seeded presets out (each device seeds its own
// createdAt / updatedAt — 6.3.1). Plus S-20 (5.1.2) on the engine: B's CORE cannot commit
// for a while (CoreTestStore.failCommits) — B's engine waits on the pending CORE writes
// without a store issue and nothing is lost. Each engine's SyncStore is wrapped by
// DelegatingSyncStore (forwarding only) so a test can see which applyRemote calls are open.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:sync_engine/src/testing/canonical_dump.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/delegating_sync_store.dart';
import 'support/core_store_driver.dart';
import 'support/real_time.dart';

const AuthUser _user = AuthUser(uid: 'user-1');

/// CORE's SyncLocalStore with its SyncStore wrapped by DelegatingSyncStore (forwarding only),
/// recording which applyRemote calls have returned.
final class _TrackedLocal implements SyncLocalStore {
  _TrackedLocal(this._inner) : sync = DelegatingSyncStore(_inner.sync) {
    sync.afterApply = returned.add;
  }

  final SyncLocalStore _inner;

  @override
  final DelegatingSyncStore sync;

  /// 1-based numbers (over [DelegatingSyncStore.applyRefs]) of the returned calls.
  final Set<int> returned = {};

  @override
  AssetStore get assets => _inner.assets;

  @override
  Stream<void> get localChanges => _inner.localChanges;

  /// The number of the first applyRemote call holding [ref], or null.
  int? firstCallWith(EntityRef ref) {
    for (final (i, refs) in sync.applyRefs.indexed) {
      if (refs.contains(ref)) return i + 1;
    }
    return null;
  }
}

final class _Device {
  _Device._(
    this.name,
    this.core,
    this.local,
    this.auth,
    this.authService,
    this.link,
    this.connectivity,
    this.engine,
  );

  static Future<_Device> open(
    String name,
    FakeSyncServer server, {
    bool signedIn = true,
  }) async {
    final nodeId = sha256
        .convert('core-scenario:$name'.codeUnits)
        .toString()
        .substring(0, 16);
    final core = await CoreTestStore.open(deviceNodeId: nodeId);
    final local = _TrackedLocal(core.local);
    final link = FakeNetworkLink(latency: const Duration(milliseconds: 20));
    final connectivity = ManualConnectivitySignal();
    final auth = FakeAuthBackend(user: signedIn ? _user : null)
      ..nextSignInUser = _user;
    final authService = AuthService(auth);
    final engine = SyncEngine(
      local: local,
      auth: authService,
      backendFactory: (u) async => server.connect(uid: u.uid, link: link),
      connectivity: connectivity,
      clock: core.store.clock,
      random: Random(name.length * 7919 + name.codeUnitAt(0)),
    );
    final device = _Device._(
      name,
      core,
      local,
      auth,
      authService,
      link,
      connectivity,
      engine,
    );
    await engine.start();
    return device;
  }

  final String name;
  final CoreTestStore core;
  final _TrackedLocal local;
  final FakeAuthBackend auth;
  final AuthService authService;
  final FakeNetworkLink link;
  final ManualConnectivitySignal connectivity;
  final SyncEngine engine;

  NoteStore get store => core.store;

  /// CORE's SyncStore itself (reads only; the engine goes through [local]).
  SyncStore get sync => core.local.sync;

  StorageWarning? get storageWarning =>
      storageWarningOf(store.storageInfo, store.persistenceStatus);

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

  Future<VersionedEntity?> read(EntityKind kind, String id) async =>
      (await sync.readVersioned([EntityRef(kind, id)])).single;

  /// Every entity under [notes] (pages, active strokes), plus [extra].
  Future<Set<EntityRef>> refsOf(
    Iterable<NoteId> notes, {
    Iterable<EntityRef> extra = const [],
  }) async {
    final refs = <EntityRef>{...extra};
    for (final n in notes) {
      refs.add(EntityRef(EntityKind.note, n));
      for (final page in await store.content.pagesOf(n)) {
        refs.add(EntityRef(EntityKind.page, page.id));
        final content = await store.content.loadPage(page.id);
        for (final s in content.strokes) {
          refs.add(EntityRef(EntityKind.stroke, s.id));
        }
      }
    }
    return refs;
  }

  Future<Map<String, Object?>> dumpOf(
    Iterable<EntityRef> refs, {
    bool withoutMetaKeys = false,
  }) async {
    final rows = await sync.readVersioned(refs.toList());
    final dump = canonicalDumpOf(rows.whereType<VersionedEntity>());
    if (!withoutMetaKeys) return dump;
    return {
      for (final MapEntry(:key, :value) in dump.entries)
        key: {
          ...(value! as Map<String, Object?>),
          'entity': {
            for (final e
                in ((value as Map<String, Object?>)['entity']!
                        as Map<String, Object?>)
                    .entries)
              if (!FieldUnits.metaKeys.contains(e.key)) e.key: e.value,
          },
        },
    };
  }

  /// Heals CORE commits first: the engine's dispose waits for its open CORE writes.
  Future<void> close() async {
    core.healCommits();
    await engine.dispose();
    await authService.dispose();
    await core.close();
  }
}

/// The waits of the running test (one real-time budget per test, set in setUp).
late RealTimeWaits _waits;

/// Polls [done] (real time) until it holds, within the test's budget.
Future<void> _until(String what, FutureOr<bool> Function() done) =>
    _waits.until(what, done);

/// Both engines idle and the dumps of every entity either side knows of [notes] equal.
Future<void> _converge(
  _Device a,
  _Device b,
  Iterable<NoteId> notes, {
  Iterable<EntityRef> extra = const [],
}) async {
  late Map<String, Object?> dumpA;
  late Map<String, Object?> dumpB;
  await _until('${a.name} and ${b.name} to converge', () async {
    if (!a.idle || !b.idle) return false;
    final refs = {
      ...await a.refsOf(notes, extra: extra),
      ...await b.refsOf(notes, extra: extra),
    };
    dumpA = await a.dumpOf(refs);
    dumpB = await b.dumpOf(refs);
    return const DeepCollectionEquality().equals(dumpA, dumpB);
  });
  expect(dumpA, dumpB);
}

Future<int> _activeStrokes(_Device d, PageId page) async =>
    (await d.store.content.loadPage(page)).strokes.length;

void main() {
  late FakeSyncServer server;
  final devices = <_Device>[];

  setUp(() {
    server = FakeSyncServer(clock: const Clock());
    devices.clear();
    _waits = RealTimeWaits();
  });
  tearDown(() async {
    for (final d in devices) {
      await d.close();
    }
  });

  Future<_Device> device(String name, {bool signedIn = true}) async {
    final d = await _Device.open(name, server, signedIn: signedIn);
    devices.add(d);
    return d;
  }

  test('S01 a stroke from A reaches B: one chunk write', () async {
    final a = await device('A');
    final b = await device('B');
    final note = (await a.store.library.createNote(title: 'S01')).id;
    await _converge(a, b, [note]);
    final page = (await b.store.content.pagesOf(note)).single.id;
    final writes = server.writeCount('user-1');

    final stroke = await a.core.addStroke(page, seed: 1);
    await _until('the stroke on B', () async {
      final row = await b.read(EntityKind.stroke, stroke.id);
      return row != null && !row.entity.isDeleted;
    });
    await _converge(a, b, [note]);
    expect(server.writeCount('user-1') - writes, 1);
    expect(await _activeStrokes(b, page), 1);
  }, timeout: kIntegrationTimeout);

  for (final order in ['A then B', 'B then A', 'both at once']) {
    test('S02 both offline (A: 100 strokes + rename, B: 80 strokes + folder '
        'move), connect $order: 180 strokes, title A, folder B', () async {
      final a = await device('A');
      final b = await device('B');
      final note = (await a.store.library.createNote(title: 'S02')).id;
      final folder = (await a.store.library.createFolder(name: 'F')).id;
      await _converge(
        a,
        b,
        [note],
        extra: [EntityRef(EntityKind.folder, folder)],
      );
      final page = (await a.store.content.pagesOf(note)).single.id;

      a.goOffline();
      b.goOffline();
      await a.core.edit(
        note,
        AddStrokes(
          pageId: page,
          strokes: StrokeFixtures.manySynthetic(
            pageId: page,
            ids: a.store.ids,
            count: 100,
          ),
        ),
      );
      await a.store.library.renameNote(note, 'title from A');
      await b.core.edit(
        note,
        AddStrokes(
          pageId: page,
          strokes: StrokeFixtures.manySynthetic(
            pageId: page,
            ids: b.store.ids,
            count: 80,
            seed: 1000,
          ),
        ),
      );
      await b.store.library.moveItems([NoteRef(note)], targetFolderId: folder);

      switch (order) {
        case 'A then B':
          a.goOnline();
          await _until('A idle', () => a.idle);
          b.goOnline();
        case 'B then A':
          b.goOnline();
          await _until('B idle', () => b.idle);
          a.goOnline();
        default:
          a.goOnline();
          b.goOnline();
      }
      await _converge(
        a,
        b,
        [note],
        extra: [EntityRef(EntityKind.folder, folder)],
      );
      for (final d in [a, b]) {
        expect(await _activeStrokes(d, page), 180, reason: d.name);
        final n = (await d.store.library.getNote(note))!;
        expect(n.title, 'title from A', reason: d.name);
        expect(n.folderId, folder, reason: d.name);
      }
    }, timeout: kIntegrationTimeout);
  }

  test('S05 A deletes a stroke while B (offline) recolors it: deleted on '
      'both, style from B', () async {
    final a = await device('A');
    final b = await device('B');
    final note = (await a.store.library.createNote(title: 'S05')).id;
    final page = (await a.store.content.pagesOf(note)).single.id;
    final stroke = await a.core.addStroke(page, seed: 5);
    await _converge(a, b, [note]);

    b.goOffline();
    await a.core.edit(
      note,
      RemoveStrokes(pageId: page, strokeIds: [stroke.id]),
    );
    await _until('A idle', () => a.idle);
    const green = 0xFF00AA00;
    await b.core.edit(
      note,
      RestyleStrokes(
        pageId: page,
        strokeIds: [stroke.id],
        patch: const StrokeStylePatch(colorArgb: green),
      ),
    );
    b.goOnline();

    final ref = EntityRef(EntityKind.stroke, stroke.id);
    await _converge(a, b, [note], extra: [ref]);
    for (final d in [a, b]) {
      final row = (await d.read(EntityKind.stroke, stroke.id))!;
      expect(row.entity.isDeleted, isTrue, reason: d.name);
      expect((row.entity as Stroke).style.colorArgb, green, reason: d.name);
      expect(await _activeStrokes(d, page), 0, reason: d.name);
    }
  }, timeout: kIntegrationTimeout);

  test('S15 first sign-in on two devices with local data: owners reassigned, '
      '5 notes, the default presets once, A\'s renamed preset kept', () async {
    final a = await device('A', signedIn: false);
    final b = await device('B', signedIn: false);
    final notes = [
      for (var i = 0; i < 3; i++)
        (await a.store.library.createNote(title: 'A$i')).id,
      for (var i = 0; i < 2; i++)
        (await b.store.library.createNote(title: 'B$i')).id,
    ];
    final defaults = await a.store.penPresets.getPresets();
    expect(
      {for (final p in await b.store.penPresets.getPresets()) p.id},
      {for (final p in defaults) p.id},
      reason: 'default preset ids are the same on every device',
    );
    final renamed = defaults.first;
    await a.store.penPresets.updatePreset(renamed.copyWith(name: 'my pen'));
    expect(a.sync.ownerId, kLocalOwnerId);

    a.auth.setUser(_user);
    await _until('A idle', () => a.idle);
    b.auth.setUser(_user);

    final presetRefs = [
      for (final p in defaults) EntityRef(EntityKind.penPreset, p.id),
    ];
    await _converge(a, b, notes);
    await _until('the presets to converge', () async {
      final dumpA = await a.dumpOf(presetRefs, withoutMetaKeys: true);
      final dumpB = await b.dumpOf(presetRefs, withoutMetaKeys: true);
      return const DeepCollectionEquality().equals(dumpA, dumpB);
    });
    for (final d in [a, b]) {
      expect(d.sync.ownerId, 'user-1', reason: d.name);
      for (final n in notes) {
        final note = (await d.store.library.getNote(n))!;
        expect(note.ownerId, 'user-1', reason: '${d.name} $n');
      }
      final presets = await d.store.penPresets.getPresets();
      expect(presets, hasLength(defaults.length), reason: d.name);
      expect(presets, hasLength(5), reason: d.name);
      expect(
        presets.singleWhere((p) => p.id == renamed.id).name,
        'my pen',
        reason: d.name,
      );
    }
    expect((await b.store.library.getNote(notes.first))!.title, 'A0');
  }, timeout: kIntegrationTimeout);

  test('S-20 B cannot commit while A\'s stroke arrives and B renames the note: '
      'B\'s engine waits on the pending CORE writes without a store issue; once '
      'CORE commits, nothing is lost and both converge', () async {
    final a = await device('A');
    final b = await device('B');
    final note = (await a.store.library.createNote(title: 'S-20')).id;
    final page = (await a.store.content.pagesOf(note)).single.id;
    await _converge(a, b, [note]);

    final storeTrouble = <SyncStatus>[];
    final statuses = b.engine.statusStream.listen((s) {
      if (s.phase == SyncPhase.error ||
          s.issues.any((i) => i.code == SyncIssueCode.localStoreFailure)) {
        storeTrouble.add(s);
      }
    });
    addTearDown(statuses.cancel);

    b.core.failCommits();
    var renamed = false;
    final rename = b.store.library
        .renameNote(note, 'title from B')
        .then((_) => renamed = true);
    final stroke = await a.core.addStroke(page, seed: 20);
    final strokeRef = EntityRef(EntityKind.stroke, stroke.id);
    await _until('A idle', () => a.idle);
    await _until(
      'B to call applyRemote with the stroke',
      () => b.local.firstCallWith(strokeRef) != null,
    );
    final call = b.local.firstCallWith(strokeRef)!;
    // A store that keeps committing ends this wait too (and fails below).
    await _until(
      'B\'s CORE to report writeFailing',
      () => b.storageWarning == StorageWarning.writeFailing || renamed,
    );

    // CORE retries: its write Futures neither complete nor fail (S-20), so B's engine
    // waits in that applyRemote; reads see the last commit.
    expect(
      renamed,
      isFalse,
      reason: 'the rename committed: the fault injection did not take effect',
    );
    expect(b.local.returned, isNot(contains(call)));
    expect(await b.read(EntityKind.stroke, stroke.id), isNull);
    expect((await b.store.library.getNote(note))!.title, 'S-20');
    expect(b.engine.status.phase, isNot(SyncPhase.error));
    expect(storeTrouble, isEmpty);
    expect((await a.store.library.getNote(note))!.title, 'S-20');

    b.core.healCommits();
    await rename;
    await _converge(a, b, [note]);
    expect(b.local.returned, contains(call));
    expect(storeTrouble, isEmpty);
    expect(b.storageWarning, isNull);
    for (final d in [a, b]) {
      expect(await _activeStrokes(d, page), 1, reason: d.name);
      expect(
        (await d.store.library.getNote(note))!.title,
        'title from B',
        reason: d.name,
      );
    }
  }, timeout: kIntegrationTimeout);
}
