// LiveListener (6.6.1 last steps, 6.6.4): live batches, rollover after N chunks or 15 min
// (new query at cursor − 60 s before the old one closes), stream error → onError (the
// engine goes back to catchingUp). Fake server, virtual time.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/engine/live_listener.dart';
import 'package:sync_engine/src/engine/serial_executor.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/download_rig.dart';
import '../support/local_writes.dart';

/// Forwards to [inner] and records the `since` of every watchChunks call.
final class WatchSpy implements SyncBackend {
  WatchSpy(this.inner);
  final SyncBackend inner;
  final List<ServerCursor?> watchSince = [];

  @override
  String get uid => inner.uid;
  @override
  Future<void> commitChunks(List<ChunkWrite> chunks) =>
      inner.commitChunks(chunks);
  @override
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  }) => inner.fetchChunks(since: since, pageToken: pageToken, limit: limit);
  @override
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since}) {
    watchSince.add(since);
    return inner.watchChunks(since: since);
  }

  @override
  Future<int?> countChunks({ServerCursor? since}) =>
      inner.countChunks(since: since);
  @override
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  }) => inner.fetchScope(scope, pageToken: pageToken, limit: limit);
  @override
  Future<void> deleteChunks(List<String> ids) => inner.deleteChunks(ids);
  @override
  Future<void> upsertProfile(UserProfile profile) =>
      inner.upsertProfile(profile);
  @override
  Future<ServerCursor> upsertDevice(DeviceInfo device) =>
      inner.upsertDevice(device);
  @override
  Future<List<RemoteChunk>> getChunks(List<String> ids) => inner.getChunks(ids);
  @override
  RemoteBlobStore get blobs => inner.blobs;
  @override
  Future<void> close() => inner.close();
}

final class LiveRig {
  LiveRig(this.r) {
    spy = WatchSpy(r.backend);
    listener = LiveListener(
      backend: spy,
      config: r.config,
      cursor: () => cursorOverride ?? r.pipeline.cursor,
      onBatch: (batch) {
        batches.add(batch);
        unawaited(executor.run(() => r.pipeline.applyChunks(batch)));
      },
      onError: errors.add,
    );
  }

  final DownloadRig r;
  late final WatchSpy spy;
  late final LiveListener listener;
  final SerialExecutor executor = SerialExecutor();
  final List<List<RemoteChunk>> batches = [];
  final List<Object> errors = [];
  ServerCursor? cursorOverride;

  /// B writes one note and pushes it (one chunk); returns the chunk id.
  String pushNote(String id) {
    r.b.localWrite([noteWrite(id)]);
    r.pushB();
    r.async.elapse(const Duration(milliseconds: 200));
    return r.serverChunks().last.id;
  }

  List<String> delivered() => [
    for (final b in batches)
      for (final c in b) c.id,
  ];
}

void main() {
  test('starts at cursor − 5 min; the initial result and later chunks are '
      'applied (the re-read part is skipped by the LRU)', () {
    withDownloadRig((r) {
      final live = LiveRig(r);
      final first = live.pushNote('n1');
      r.connect();
      r.catchUp();
      live.listener.start();
      r.async.elapse(const Duration(seconds: 1));
      expect(live.spy.watchSince, [
        r.pipeline.cursor!.minus(const Duration(minutes: 5)),
      ]);
      expect(live.delivered(), [first]);
      expect(r.sync.applyRefs, hasLength(1), reason: 'n1 was applied once');

      final second = live.pushNote('n2');
      expect(live.delivered(), [first, second]);
      r.expectSameRow(EntityKind.note, 'n2');
      expect(r.pipeline.cursor, r.serverChunks().last.serverTime);
      expect(live.listener.isRunning, isTrue);
      r.run(live.listener.stop());
      expect(live.listener.isRunning, isFalse);
    });
  });

  test('rollover after listenerRolloverChunks chunks: a new query at '
      'cursor − 60 s opens, then the old one closes', () {
    withDownloadRig((r) {
      final live = LiveRig(r);
      r.connect();
      live.listener.start();
      r.async.elapse(const Duration(seconds: 1));
      expect(live.r.link.callCount(FakeOp.watch), 1);
      final ids = [for (var i = 0; i < 3; i++) live.pushNote('n$i')];
      expect(live.listener.rollovers, 1);
      expect(r.link.callCount(FakeOp.watch), 2);
      // The third batch triggered it before it was applied: cursor = second chunk.
      expect(
        live.spy.watchSince.last,
        r.serverChunks()[1].serverTime.minus(const Duration(seconds: 60)),
      );
      // The new query's initial result re-reads the last minute (LRU drops it).
      final afterRollover = live.pushNote('late');
      expect(
        live.delivered().where((id) => id == afterRollover),
        hasLength(1),
        reason: 'the old query is closed',
      );
      for (final id in ids) {
        expect(live.delivered(), contains(id));
      }
      r.expectSameRow(EntityKind.note, 'late');
      expect(r.sync.applyRefs, hasLength(4), reason: 'each chunk once');
      r.run(live.listener.stop());
    }, config: const SyncConfig(listenerRolloverChunks: 3));
  });

  test('rollover after listenerRolloverInterval (15 min)', () {
    withDownloadRig((r) {
      final live = LiveRig(r);
      live.cursorOverride = const ServerCursor(1000000000);
      r.connect();
      live.listener.start();
      r.async.elapse(const Duration(minutes: 14, seconds: 59));
      expect(live.listener.rollovers, 0);
      r.async.elapse(const Duration(seconds: 1));
      expect(live.listener.rollovers, 1);
      expect(live.spy.watchSince, [
        const ServerCursor(1000000000).minus(const Duration(minutes: 5)),
        const ServerCursor(1000000000).minus(const Duration(seconds: 60)),
      ]);
      r.async.elapse(const Duration(minutes: 15));
      expect(live.listener.rollovers, 2);
      r.run(live.listener.stop());
      r.async.elapse(const Duration(hours: 1));
      expect(live.listener.rollovers, 2, reason: 'no timer after stop');
    });
  });

  test('a stream error stops the listener and reports once; catching up '
      'receives what was missed', () {
    withDownloadRig((r) {
      final live = LiveRig(r);
      r.connect();
      live.listener.start();
      r.async.elapse(const Duration(seconds: 1));
      r.link.setOnline(false);
      r.async.elapse(const Duration(seconds: 1));
      expect(live.errors, hasLength(1));
      expect(live.listener.isRunning, isFalse);

      live.pushNote('missed');
      expect(r.hasRow(EntityKind.note, 'missed'), isFalse);
      r.async.elapse(const Duration(minutes: 20));
      expect(live.errors, hasLength(1), reason: 'no rollover timer left');

      r.link.setOnline(true);
      r.catchUp();
      r.expectSameRow(EntityKind.note, 'missed');
      live.listener.start();
      r.async.elapse(const Duration(seconds: 1));
      expect(live.listener.isRunning, isTrue);
      r.run(live.listener.stop());
    });
  });
}
