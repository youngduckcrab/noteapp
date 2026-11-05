// T12: SyncRemoteAssetFetcher (6.9.3, contract 7.2.20) over a hand-driven SyncAssetService:
// the nine-state table, ensureLocal passed on with visible priority, watch closing after
// local and dropping equal neighbours, and assignability to core.RemoteAssetFetcher.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:sync_engine/sync_engine.dart';

const String kId =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// A SyncAssetService whose watch stream and ensureLocal answers the test drives.
final class ScriptedAssetService implements SyncAssetService {
  final StreamController<AssetAvailability> watchSource = StreamController();
  final List<(core.AssetId, AssetPriority)> ensureCalls = [];
  final List<core.AssetId> watchCalls = [];
  bool ensureAnswer = true;
  bool watchCancelled = false;

  @override
  Future<AssetAvailability> availability(core.AssetId id) =>
      throw UnimplementedError();

  @override
  Stream<AssetAvailability> watch(core.AssetId id) {
    watchCalls.add(id);
    watchSource.onCancel = () => watchCancelled = true;
    return watchSource.stream;
  }

  @override
  Future<bool> ensureLocal(
    core.AssetId id, {
    AssetPriority priority = AssetPriority.visible,
  }) async {
    ensureCalls.add((id, priority));
    return ensureAnswer;
  }

  @override
  void cancel(core.AssetId id) {}

  @override
  Stream<AssetTransferSummary> get summary => const Stream.empty();

  Future<void> close() => watchSource.close();
}

AssetAvailability availability(
  AssetAvailabilityState state, {
  int? received,
  int? total,
}) => AssetAvailability(
  id: kId,
  state: state,
  receivedBytes: received,
  totalBytes: total,
);

/// (state, received, total) of a progress value.
(core.RemoteAssetState, int?, int?) fieldsOf(core.RemoteAssetProgress p) =>
    (p.state, p.received, p.total);

/// Feeds [inputs] to the watch stream and returns what the fetcher emitted and whether
/// its stream was done.
({List<(core.RemoteAssetState, int?, int?)> out, bool done}) run(
  List<AssetAvailability> inputs, {
  bool closeSource = false,
}) {
  late ({List<(core.RemoteAssetState, int?, int?)> out, bool done}) result;
  fakeAsync((async) {
    final service = ScriptedAssetService();
    final fetcher = SyncRemoteAssetFetcher(service);
    final out = <(core.RemoteAssetState, int?, int?)>[];
    var done = false;
    final sub = fetcher
        .watch(kId)
        .listen((p) => out.add(fieldsOf(p)), onDone: () => done = true);
    async.flushMicrotasks();
    expect(service.watchCalls, [kId]);
    for (final a in inputs) {
      service.watchSource.add(a);
      async.flushMicrotasks();
    }
    if (closeSource) unawaited(service.watchSource.close());
    async.flushMicrotasks();
    result = (out: out, done: done);
    unawaited(sub.cancel());
    async.flushMicrotasks();
  });
  return result;
}

void main() {
  test('is a core.RemoteAssetFetcher', () {
    final core.RemoteAssetFetcher fetcher = SyncRemoteAssetFetcher(
      ScriptedAssetService(),
    );
    expect(fetcher, isA<SyncRemoteAssetFetcher>());
  });

  test('ensureLocal asks the service with visible priority and passes its '
      'answer on', () async {
    final service = ScriptedAssetService();
    final fetcher = SyncRemoteAssetFetcher(service);
    expect(await fetcher.ensureLocal(kId), isTrue);
    service.ensureAnswer = false;
    expect(await fetcher.ensureLocal(kId), isFalse);
    expect(service.ensureCalls, [
      (kId, AssetPriority.visible),
      (kId, AssetPriority.visible),
    ]);
  });

  group('the 6.9.3 table', () {
    final table = <AssetAvailability, (core.RemoteAssetState, int?, int?)>{
      availability(AssetAvailabilityState.downloading, received: 3, total: 9): (
        core.RemoteAssetState.downloading,
        3,
        9,
      ),
      availability(AssetAvailabilityState.queued, total: 9): (
        core.RemoteAssetState.downloading,
        0,
        9,
      ),
      availability(AssetAvailabilityState.remoteReady, total: 9): (
        core.RemoteAssetState.waiting,
        null,
        null,
      ),
      availability(AssetAvailabilityState.waitingForUpload, total: 9): (
        core.RemoteAssetState.waiting,
        null,
        null,
      ),
      availability(AssetAvailabilityState.unknown): (
        core.RemoteAssetState.waiting,
        null,
        null,
      ),
      availability(AssetAvailabilityState.offline, total: 9): (
        core.RemoteAssetState.offline,
        null,
        null,
      ),
      availability(AssetAvailabilityState.failed): (
        core.RemoteAssetState.failed,
        null,
        null,
      ),
      availability(AssetAvailabilityState.syncDisabled): (
        core.RemoteAssetState.unavailable,
        null,
        null,
      ),
      availability(AssetAvailabilityState.local): (
        core.RemoteAssetState.local,
        null,
        null,
      ),
    };

    test('covers all nine states', () {
      expect(
        {for (final a in table.keys) a.state},
        {...AssetAvailabilityState.values},
      );
    });

    for (final MapEntry(key: input, value: expected) in table.entries) {
      test('${input.state.name} → ${expected.$1.name}', () {
        expect(run([input]).out, [expected]);
      });
    }
  });

  test('consecutive equal values are dropped (remoteReady / waitingForUpload / '
      'unknown are all waiting; queued 0 of n = downloading 0 of n)', () {
    final r = run([
      availability(AssetAvailabilityState.unknown),
      availability(AssetAvailabilityState.waitingForUpload, total: 9),
      availability(AssetAvailabilityState.remoteReady, total: 9),
      availability(AssetAvailabilityState.queued, total: 9),
      availability(AssetAvailabilityState.downloading, received: 0, total: 9),
      availability(AssetAvailabilityState.downloading, received: 4, total: 9),
      availability(AssetAvailabilityState.offline, total: 9),
      availability(AssetAvailabilityState.offline, total: 9),
      availability(AssetAvailabilityState.queued, total: 9),
    ]);
    expect(r.out, [
      (core.RemoteAssetState.waiting, null, null),
      (core.RemoteAssetState.downloading, 0, 9),
      (core.RemoteAssetState.downloading, 4, 9),
      (core.RemoteAssetState.offline, null, null),
      (core.RemoteAssetState.downloading, 0, 9),
    ]);
    expect(r.done, isFalse);
  });

  test('closes after local (and stops listening to the service)', () {
    late bool cancelled;
    final out = <core.RemoteAssetState>[];
    var done = false;
    fakeAsync((async) {
      final service = ScriptedAssetService();
      SyncRemoteAssetFetcher(service)
          .watch(kId)
          .listen((p) => out.add(p.state), onDone: () => done = true);
      async.flushMicrotasks();
      service.watchSource
        ..add(availability(AssetAvailabilityState.downloading, total: 9))
        ..add(availability(AssetAvailabilityState.local))
        ..add(availability(AssetAvailabilityState.failed));
      async.flushMicrotasks();
      cancelled = service.watchCancelled;
    });
    expect(out, [
      core.RemoteAssetState.downloading,
      core.RemoteAssetState.local,
    ]);
    expect(done, isTrue);
    expect(cancelled, isTrue);
  });

  test('a service stream that ends closes the fetcher stream', () {
    final r = run([
      availability(AssetAvailabilityState.remoteReady),
    ], closeSource: true);
    expect(r.out, [(core.RemoteAssetState.waiting, null, null)]);
    expect(r.done, isTrue);
  });
}
