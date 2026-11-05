// T12: asset bytes (6.9) through the engine on the fake server — AssetUploader (stat
// dedupe, size limit, interrupted upload, per-asset backoff and assetUploadFailed),
// AssetDownloader / SyncAssetService (waitingForUpload → remoteReady, shared download,
// hash mismatch → assetCorrupt, offline and resume, priority, cancel), progress streams,
// SyncStatus.assets and usage().
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';

const int kMiB = 1024 * 1024;

/// Deterministic bytes of [length] (different [seed] → different content and id).
Uint8List bytesOf(int length, {int seed = 1}) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (i * 31 + seed * 7 + i ~/ 251) % 256;
  }
  return out;
}

String idOf(Uint8List bytes) => sha256.convert(bytes).toString();

Asset? assetOn(TestDevice d, AssetId id) =>
    d.store.rows[EntityRef(EntityKind.asset, id)]?.entity as Asset?;

AssetAvailability availabilityOn(SyncTestHarness h, TestDevice d, AssetId id) =>
    h.run(d.engine.assets.availability(id));

/// Two live devices; A put [bytes] and everything settled (uploaded, B has the record).
({TestDevice a, TestDevice b, AssetId id, String path}) uploadedByA(
  SyncTestHarness h,
  Uint8List bytes, {
  SyncConfig? configB,
}) {
  final a = liveDevice(h, 'A');
  final b = liveDevice(h, 'B', config: configB);
  final id = h.run(a.putAsset(bytes));
  h.settle();
  final path = h.server.blobsOf('user-1').pathFor(id);
  expect(assetOn(a, id)!.storagePath, path);
  expect(assetOn(b, id)!.storagePath, path);
  return (a: a, b: b, id: id, path: path);
}

/// Collects every value of [stream] until it is done.
final class Collected<T> {
  Collected(Stream<T> stream) {
    _sub = stream.listen(values.add, onDone: () => done = true);
  }
  final List<T> values = [];
  bool done = false;
  late final StreamSubscription<T> _sub;
  void cancel() => unawaited(_sub.cancel());
}

void main() {
  group('upload (6.9.1)', () {
    harnessTest('an asset put on a live device is uploaded with the rules\' '
        'metadata and marked uploaded; the other device sees it remoteReady', (
      h,
      async,
    ) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      final bytes = bytesOf(3 * kMiB);
      final id = h.run(a.putAsset(bytes));
      h.settle();
      final blobs = h.server.blobsOf('user-1');
      final path = blobs.pathFor(id);
      expect(blobs.uploadCount, 1);
      expect(blobs.objects[path], bytes);
      final info = h.run(blobs.stat(path))!;
      expect(info.sha256, id);
      expect(info.contentType, 'application/pdf');
      expect(info.size, bytes.length);
      expect(assetOn(a, id)!.storagePath, path);
      expect(assetOn(b, id)!.storagePath, path);
      expect(assetOn(b, id)!.hasLocalBytes, isFalse);
      expect(
        availabilityOn(h, a, id),
        AssetAvailability(id: id, state: AssetAvailabilityState.local),
      );
      expect(
        availabilityOn(h, b, id),
        AssetAvailability(
          id: id,
          state: AssetAvailabilityState.remoteReady,
          totalBytes: bytes.length,
        ),
      );
      expect(a.engine.status.assets, AssetTransferSummary.idle);
      expect(a.engine.status.display, SyncDisplayState.done);
      h.checkConverged([a, b]);
    });

    harnessTest('stat dedupe: an object already on the server is not uploaded '
        'again (markUploaded only)', (h, async) {
      final bytes = bytesOf(2 * kMiB, seed: 3);
      final id = idOf(bytes);
      final server = h.server.blobsOf('user-1');
      final path = server.pathFor(id);
      h.run(
        server.upload(
          path,
          bytes,
          contentType: 'application/pdf',
          metadata: {'sha256': id},
        ),
      );
      final a = liveDevice(h, 'A');
      expect(h.run(a.putAsset(bytes)), id);
      h.settle();
      expect(a.link.callCount(FakeOp.stat), 1);
      expect(a.link.callCount(FakeOp.upload), 0);
      expect(server.uploadCount, 1);
      expect(assetOn(a, id)!.storagePath, path);
    });

    harnessTest('the same bytes put on two devices at once are written once', (
      h,
      async,
    ) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      final bytes = bytesOf(4 * kMiB, seed: 5);
      final id = h.run(a.putAsset(bytes));
      expect(h.run(b.putAsset(bytes)), id);
      h.settle();
      expect(h.server.blobsOf('user-1').uploadCount, 1);
      expect(assetOn(a, id)!.storagePath, isNotNull);
      expect(assetOn(b, id)!.storagePath, assetOn(a, id)!.storagePath);
      h.checkConverged([a, b]);
    });

    harnessTest('larger than maxAssetUploadBytes → assetTooLarge, kept local, '
        'not pending; a smaller one still goes', (h, async) {
      expect(const SyncConfig().maxAssetUploadBytes, 300 * kMiB);
      final a = liveDevice(
        h,
        'A',
        config: const SyncConfig(maxAssetUploadBytes: 1000),
      );
      final big = h.run(a.putAsset(bytesOf(1001)));
      final small = h.run(a.putAsset(bytesOf(1000, seed: 2)));
      h.settle();
      final issue = issueOf(a, SyncIssueCode.assetTooLarge)!;
      expect(issue.assetId, big);
      expect(issue.code.isBlocking, isFalse);
      expect(assetOn(a, big)!.storagePath, isNull);
      expect(assetOn(a, small)!.storagePath, isNotNull);
      expect(h.server.blobsOf('user-1').uploadCount, 1);
      expect(a.engine.status.assets.uploadsPending, 0);
      expect(a.engine.status.display, SyncDisplayState.done);
    });

    harnessTest('an upload stopped at 60 % is retried after the backoff and '
        'succeeds; progress and the batch reset are reported', (h, async) {
      final a = liveDevice(h, 'A');
      final summaries = Collected(a.engine.assets.summary);
      a.link.failNext(const FakeInterrupt(0.6), op: FakeOp.upload);
      final bytes = bytesOf(10 * kMiB, seed: 7);
      final id = h.run(a.putAsset(bytes));
      // 6 pieces of 10 ms after the request: stopped, waiting for the ~1 s backoff.
      h.elapse(const Duration(milliseconds: 400));
      expect(a.link.callCount(FakeOp.upload), 1);
      expect(assetOn(a, id)!.storagePath, isNull);
      expect(a.engine.status.assets.uploadsPending, 1);
      expect(a.engine.status.display, SyncDisplayState.inProgress);
      h.settle();
      expect(a.link.callCount(FakeOp.upload), 2);
      expect(h.server.blobsOf('user-1').uploadCount, 1);
      expect(
        h.server.blobsOf('user-1').objects[assetOn(a, id)!.storagePath],
        bytes,
      );
      final done = [for (final s in summaries.values) s.uploadBytesDone];
      expect(done, contains(6 * kMiB));
      final stopped = done.indexOf(6 * kMiB);
      expect(
        done.sublist(stopped + 1),
        contains(0),
        reason: 'reset on failure',
      );
      expect(done, contains(10 * kMiB));
      expect(
        summaries.values.where((s) => s.uploadsPending > 0),
        everyElement(
          predicate<AssetTransferSummary>(
            (s) => s.uploadBytesTotal == 0 || s.uploadBytesTotal == 10 * kMiB,
          ),
        ),
      );
      expect(summaries.values.last, AssetTransferSummary.idle);
      expect(issueOf(a, SyncIssueCode.assetUploadFailed), isNull);
      summaries.cancel();
    });

    harnessTest('three failures in a row → assetUploadFailed (still retried); '
        'the next success clears it', (h, async) {
      final a = liveDevice(h, 'A');
      final log = EngineLog(a.engine);
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.internal),
        op: FakeOp.upload,
        times: 3,
      );
      final id = h.run(a.putAsset(bytesOf(kMiB, seed: 9)));
      h.settle();
      expect(a.link.callCount(FakeOp.upload), 4);
      expect(
        log.statuses.any(
          (s) => s.issues.any(
            (i) => i.code == SyncIssueCode.assetUploadFailed && i.assetId == id,
          ),
        ),
        isTrue,
      );
      expect(issueOf(a, SyncIssueCode.assetUploadFailed), isNull);
      expect(assetOn(a, id)!.storagePath, isNotNull);
      log.cancel();
    });

    harnessTest(
      'local assets that were never uploaded go after sign-in (scan at '
      'attach)',
      (h, async) {
        final a = h.device('A', signedIn: false);
        final id = h.run(a.putAsset(bytesOf(kMiB, seed: 11)));
        h.settle();
        expect(a.engine.status.phase, SyncPhase.signedOut);
        expect(a.engine.status.assets, AssetTransferSummary.idle);
        a.auth.setUser(const AuthUser(uid: 'user-1'));
        h.settle();
        expect(a.engine.status.phase, SyncPhase.live);
        expect(assetOn(a, id)!.storagePath, isNotNull);
        expect(h.server.blobsOf('user-1').uploadCount, 1);
      },
    );
  });

  group('download (6.9.2)', () {
    harnessTest('waitingForUpload → remoteReady without a request; a request '
        'made while waiting goes on by itself to local', (h, async) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      // Both uploads are refused once: rules errors wait 10 minutes (6.5.4).
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.permissionDenied),
        op: FakeOp.upload,
        times: 2,
      );
      final requested = bytesOf(2 * kMiB, seed: 13);
      final watched = bytesOf(kMiB, seed: 14);
      final x = h.run(a.putAsset(requested));
      final y = h.run(a.putAsset(watched));
      h.elapse(const Duration(seconds: 10));
      expect(assetOn(b, x)!.storagePath, isNull, reason: 'record arrived');
      expect(
        availabilityOn(h, b, x).state,
        AssetAvailabilityState.waitingForUpload,
      );
      final xs = Collected(b.engine.assets.watch(x));
      final ys = Collected(b.engine.assets.watch(y));
      expect(h.run(b.engine.assets.ensureLocal(x)), isFalse);
      h.elapse(const Duration(minutes: 10));
      h.settle();
      expect(h.run(b.store.assets.readBytes(x)), requested);
      expect(h.run(b.store.assets.hasBytes(y)), isFalse);
      final xStates = [for (final v in xs.values) v.state];
      expect(xStates.first, AssetAvailabilityState.waitingForUpload);
      expect(xStates, contains(AssetAvailabilityState.downloading));
      expect(xStates.last, AssetAvailabilityState.local);
      expect(xs.done, isTrue, reason: 'watch closes after local');
      expect(
        [for (final v in ys.values) v.state],
        [
          AssetAvailabilityState.waitingForUpload,
          AssetAvailabilityState.remoteReady,
        ],
      );
      expect(ys.done, isFalse);
      ys.cancel();
    });

    harnessTest('an id with no record yet is unknown; the request goes on when '
        'the record arrives', (h, async) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      final bytes = bytesOf(kMiB, seed: 15);
      final id = idOf(bytes);
      expect(availabilityOn(h, b, id).state, AssetAvailabilityState.unknown);
      expect(h.run(b.engine.assets.ensureLocal(id)), isFalse);
      expect(availabilityOn(h, b, id).state, AssetAvailabilityState.unknown);
      h.run(a.putAsset(bytes));
      h.settle();
      expect(h.run(b.store.assets.readBytes(id)), bytes);
      expect(availabilityOn(h, b, id).state, AssetAvailabilityState.local);
    });

    harnessTest('concurrent requests for one id share one download', (
      h,
      async,
    ) {
      final bytes = bytesOf(5 * kMiB, seed: 17);
      final (:a, :b, :id, path: _) = uploadedByA(h, bytes);
      final calls = [
        b.engine.assets.ensureLocal(id),
        b.engine.assets.ensureLocal(id),
        b.engine.assets.ensureLocal(id, priority: AssetPriority.background),
      ];
      expect(h.run(Future.wait(calls)), [true, true, true]);
      expect(b.link.callCount(FakeOp.download), 1);
      expect(h.server.blobsOf('user-1').downloadCount, 1);
      expect(h.run(b.store.assets.readBytes(id)), bytes);
      expect(assetOn(b, id)!.hasLocalBytes, isTrue);
      expect(h.run(b.engine.assets.ensureLocal(id)), isTrue);
      expect(b.link.callCount(FakeOp.download), 1);
      expect(a.link.callCount(FakeOp.download), 0);
    });

    harnessTest('bytes that fail the hash check are downloaded once more, then '
        'assetCorrupt / failed; the next ensureLocal tries again', (h, async) {
      final bytes = bytesOf(2 * kMiB, seed: 19);
      final (a: _, :b, :id, :path) = uploadedByA(h, bytes);
      final server = h.server.blobsOf('user-1');
      server.objects[path] = bytesOf(2 * kMiB, seed: 20);
      expect(h.run(b.engine.assets.ensureLocal(id)), isFalse);
      expect(server.downloadCount, 2);
      final failed = availabilityOn(h, b, id);
      expect(failed.state, AssetAvailabilityState.failed);
      expect(failed.error!.code, SyncIssueCode.assetCorrupt);
      expect(failed.error!.assetId, id);
      expect(issueOf(b, SyncIssueCode.assetCorrupt)!.assetId, id);
      expect(h.run(b.store.assets.hasBytes(id)), isFalse);
      h.settle();
      expect(server.downloadCount, 2, reason: 'failed waits for ensureLocal');
      server.objects[path] = bytes;
      expect(h.run(b.engine.assets.ensureLocal(id)), isTrue);
      expect(server.downloadCount, 3);
      expect(issueOf(b, SyncIssueCode.assetCorrupt), isNull);
    });

    harnessTest('a missing object → failed with assetDownloadFailed', (
      h,
      async,
    ) {
      final (a: _, :b, :id, :path) = uploadedByA(h, bytesOf(kMiB, seed: 21));
      h.server.blobsOf('user-1').objects.remove(path);
      expect(h.run(b.engine.assets.ensureLocal(id)), isFalse);
      final failed = availabilityOn(h, b, id);
      expect(failed.state, AssetAvailabilityState.failed);
      expect(failed.error!.code, SyncIssueCode.assetDownloadFailed);
      expect(issueOf(b, SyncIssueCode.assetDownloadFailed)!.assetId, id);
      b.engine.assets.cancel(id);
      expect(issueOf(b, SyncIssueCode.assetDownloadFailed), isNull);
      expect(
        availabilityOn(h, b, id).state,
        AssetAvailabilityState.remoteReady,
      );
    });

    harnessTest(
      'offline: the request waits (offline) and resumes by itself when '
      'live again; a transfer cut by going offline resumes too',
      (h, async) {
        final bytes = bytesOf(20 * kMiB, seed: 23);
        final (:a, :b, :id, path: _) = uploadedByA(h, bytes);
        b.goOffline();
        h.elapse(const Duration(milliseconds: 10));
        expect(h.run(b.engine.assets.ensureLocal(id)), isFalse);
        expect(
          availabilityOn(h, b, id),
          AssetAvailability(
            id: id,
            state: AssetAvailabilityState.offline,
            totalBytes: bytes.length,
          ),
        );
        expect(b.engine.status.assets.downloadsActive, 0);
        b.goOnline();
        h.settle();
        expect(h.run(b.store.assets.readBytes(id)), bytes);
        expect(b.link.callCount(FakeOp.download), 1);

        // A second asset: the link drops in the middle of its transfer.
        final more = bytesOf(20 * kMiB, seed: 24);
        final other = h.run(a.putAsset(more));
        h.settle();
        final download = b.engine.assets.ensureLocal(other);
        h.elapse(const Duration(milliseconds: 150));
        expect(
          availabilityOn(h, b, other).state,
          AssetAvailabilityState.downloading,
        );
        b.goOffline();
        expect(h.run(download), isFalse);
        expect(
          availabilityOn(h, b, other).state,
          AssetAvailabilityState.offline,
        );
        h.elapse(const Duration(minutes: 1));
        b.goOnline();
        h.settle();
        expect(h.run(b.store.assets.readBytes(other)), more);
      },
    );

    harnessTest('visible requests go before background ones (one slot)', (
      h,
      async,
    ) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(
        h,
        'B',
        config: const SyncConfig(assetDownloadConcurrency: 1),
      );
      final ids = [
        for (var i = 0; i < 3; i++)
          h.run(a.putAsset(bytesOf(2 * kMiB, seed: 30 + i))),
      ];
      h.settle();
      final arrived = <AssetId>[];
      final sub = b.store.assets.bytesArrived.listen(arrived.add);
      final futures = [
        b.engine.assets.ensureLocal(ids[0], priority: AssetPriority.background),
        b.engine.assets.ensureLocal(ids[1], priority: AssetPriority.background),
        b.engine.assets.ensureLocal(ids[2]),
      ];
      expect(h.run(Future.wait(futures)), [true, true, true]);
      expect(arrived, [ids[0], ids[2], ids[1]]);
      unawaited(sub.cancel());
    });

    harnessTest('cancel stops the transfer; the asset is remoteReady again', (
      h,
      async,
    ) {
      final (a: _, :b, :id, path: _) = uploadedByA(
        h,
        bytesOf(30 * kMiB, seed: 25),
      );
      final download = b.engine.assets.ensureLocal(id);
      h.elapse(const Duration(milliseconds: 150));
      expect(
        availabilityOn(h, b, id).state,
        AssetAvailabilityState.downloading,
      );
      b.engine.assets.cancel(id);
      expect(h.run(download), isFalse);
      h.settle();
      expect(h.run(b.store.assets.hasBytes(id)), isFalse);
      expect(
        availabilityOn(h, b, id).state,
        AssetAvailabilityState.remoteReady,
      );
      expect(h.server.blobsOf('user-1').downloadCount, 0);
      expect(h.run(b.engine.assets.ensureLocal(id)), isTrue);
    });

    harnessTest(
      'signed out or sync disabled → syncDisabled unless the bytes are '
      'local',
      (h, async) {
        final c = h.device('C', signedIn: false);
        final local = h.run(c.putAsset(bytesOf(1000, seed: 27)));
        h.settle();
        final missing = idOf(bytesOf(1000, seed: 28));
        expect(availabilityOn(h, c, local).state, AssetAvailabilityState.local);
        expect(
          availabilityOn(h, c, missing).state,
          AssetAvailabilityState.syncDisabled,
        );
        expect(h.run(c.engine.assets.ensureLocal(missing)), isFalse);
        expect(h.run(c.engine.assets.ensureLocal(local)), isTrue);

        final store = FakeLocalStore(
          nodeId: 'ffffffffffffffff',
          clock: h.serverClock,
        );
        final disabled = SyncEngine(
          local: store,
          auth: AuthService(FakeAuthBackend()),
        );
        h.run(disabled.start());
        expect(disabled.status.phase, SyncPhase.disabled);
        expect(
          h.run(disabled.assets.availability(missing)).state,
          AssetAvailabilityState.syncDisabled,
        );
        expect(h.run(disabled.assets.ensureLocal(missing)), isFalse);
        h.run(disabled.dispose());
      },
    );

    harnessTest('signing out during a download stops it (syncDisabled); after '
        'signing in again the request goes on', (h, async) {
      final bytes = bytesOf(30 * kMiB, seed: 29);
      final (a: _, :b, :id, path: _) = uploadedByA(h, bytes);
      final download = b.engine.assets.ensureLocal(id);
      h.elapse(const Duration(milliseconds: 150));
      b.auth.setUser(null);
      expect(h.run(download), isFalse);
      expect(
        availabilityOn(h, b, id).state,
        AssetAvailabilityState.syncDisabled,
      );
      b.auth.setUser(const AuthUser(uid: 'user-1'));
      h.settle();
      expect(h.run(b.store.assets.readBytes(id)), bytes);
    });
  });

  group('progress', () {
    harnessTest(
      'watch reports queued, growing downloading bytes, then local and '
      'closes; summary and status follow transfers',
      (h, async) {
        final bytes = bytesOf(5 * kMiB, seed: 41);
        final (:a, :b, :id, path: _) = uploadedByA(h, bytes);
        final watch = Collected(b.engine.assets.watch(id));
        final summaries = Collected(b.engine.assets.summary);
        h.elapse(Duration.zero);
        expect(h.run(b.engine.assets.ensureLocal(id)), isTrue);
        h.elapse(Duration.zero);
        final values = watch.values;
        expect(values.first.state, AssetAvailabilityState.remoteReady);
        expect(
          values.last,
          AssetAvailability(id: id, state: AssetAvailabilityState.local),
        );
        expect(watch.done, isTrue);
        final downloading = [
          for (final v in values)
            if (v.state == AssetAvailabilityState.downloading) v,
        ];
        expect(downloading, isNotEmpty);
        expect(downloading.every((v) => v.totalBytes == bytes.length), isTrue);
        final received = [for (final v in downloading) v.receivedBytes!];
        expect(received, orderedEquals([...received]..sort()));
        expect(received.last, bytes.length);
        expect(downloading.last.progress, 1);
        for (var i = 1; i < values.length; i++) {
          expect(
            values[i],
            isNot(values[i - 1]),
            reason: 'no equal neighbours',
          );
        }

        final s = summaries.values;
        expect(s.first, AssetTransferSummary.idle);
        expect(
          s.any(
            (v) =>
                v.downloadsActive == 1 && v.downloadBytesTotal == bytes.length,
          ),
          isTrue,
        );
        expect(s.any((v) => v.downloadBytesDone == bytes.length), isTrue);
        expect(s.last, AssetTransferSummary.idle);
        expect(b.engine.status.assets, AssetTransferSummary.idle);
        summaries.cancel();

        // Uploads count in the status (display inProgress) while they run.
        final log = EngineLog(a.engine);
        h.run(a.putAsset(bytesOf(8 * kMiB, seed: 42)));
        h.settle();
        final busy = [
          for (final st in log.statuses)
            if (st.assets.uploadsPending > 0) st,
        ];
        expect(busy, isNotEmpty);
        expect(
          busy.every((st) => st.display == SyncDisplayState.inProgress),
          isTrue,
        );
        expect(
          busy.any((st) => st.assets.uploadBytesTotal == 8 * kMiB),
          isTrue,
        );
        expect(a.engine.status.assets, AssetTransferSummary.idle);
        expect(a.engine.status.display, SyncDisplayState.done);
        log.cancel();
      },
    );
  });

  harnessTest('usage(): uploaded vs local-only CORE sizes', (h, async) {
    final a = liveDevice(
      h,
      'A',
      config: const SyncConfig(maxAssetUploadBytes: 3000),
    );
    final b = liveDevice(h, 'B');
    expect(
      h.run(a.engine.usage()),
      isA<SyncUsage>()
          .having((u) => u.uploadedAssetCount, 'uploaded', 0)
          .having((u) => u.localOnlyAssetCount, 'local only', 0),
    );
    h.run(a.putAsset(bytesOf(1000, seed: 51)));
    h.run(a.putAsset(bytesOf(2000, seed: 52)));
    h.run(a.putAsset(bytesOf(4000, seed: 53))); // too large: local only
    h.settle();
    final ua = h.run(a.engine.usage());
    expect(ua.uploadedAssetCount, 2);
    expect(ua.uploadedAssetBytes, 3000);
    expect(ua.localOnlyAssetCount, 1);
    expect(ua.localOnlyAssetBytes, 4000);
    // B has the two uploaded records (metadata only) and the local-only one's record
    // without bytes: neither uploaded nor local.
    final ub = h.run(b.engine.usage());
    expect(ub.uploadedAssetCount, 2);
    expect(ub.uploadedAssetBytes, 3000);
    expect(ub.localOnlyAssetCount, 0);
    expect(ub.localOnlyAssetBytes, 0);
  });
}
