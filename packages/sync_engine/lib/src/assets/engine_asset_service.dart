// Internal (not exported). The engine's SyncAssetService (4.5, 6.9): AssetDownloader for
// requests, the session's AssetUploader for this device's bytes, availability from the
// request and the local store, the transfer summary (SyncStatus.assets, 6.12) and usage.
// The engine calls attach / setLive / detach with its phase (6.8.2), onAssetsPushed after a
// push sent asset records without storagePath (6.9.1) and onRemoteAssets after an apply
// group took asset records (6.9.2: requests waiting for metadata or upload go on).
import 'dart:async';
import 'dart:math';

import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../config.dart';
import '../engine/sync_engine.dart';
import '../status/sync_status.dart';
import 'asset_downloader.dart';
import 'asset_uploader.dart';
import 'sync_asset_service.dart';

final class EngineAssetService implements SyncAssetService {
  EngineAssetService({
    required this.assets,
    required this.config,
    required Random random,
    required int Function() nowMillis,
    required this.onSummary,
    required this.report,
    this.onError,
  }) : _random = random {
    downloader = AssetDownloader(
      assets: assets,
      config: config,
      random: random,
      nowMillis: nowMillis,
      onChanged: _changed,
      report: report,
    );
  }

  final AssetStore assets;
  final SyncConfig config;

  /// SyncStatus.assets (StatusBuilder).
  final void Function(AssetTransferSummary summary) onSummary;
  final AssetIssueReport report;
  final void Function(String what, Object error)? onError;
  final Random _random;

  late final AssetDownloader downloader;

  /// The attached session's uploader (null when signed out or disabled).
  AssetUploader? get uploader => _uploader;
  AssetUploader? _uploader;

  final StreamController<AssetId?> _changes = StreamController.broadcast();
  final StreamController<AssetTransferSummary> _summaries =
      StreamController.broadcast();
  StreamSubscription<AssetId>? _bytesSub;
  AssetTransferSummary _summary = AssetTransferSummary.idle;
  bool _closed = false;

  AssetTransferSummary get currentSummary => _summary;

  // ---- SyncAssetService -----------------------------------------------------------------

  @override
  Future<AssetAvailability> availability(AssetId id) async {
    _listen();
    final r = downloader.requestOf(id);
    switch (r?.stage) {
      case DownloadStage.queued:
        return AssetAvailability(
          id: id,
          state: AssetAvailabilityState.queued,
          receivedBytes: 0,
          totalBytes: r!.total,
        );
      case DownloadStage.downloading:
        return AssetAvailability(
          id: id,
          state: AssetAvailabilityState.downloading,
          receivedBytes: r!.received,
          totalBytes: r.total,
        );
      case DownloadStage.offline:
        return AssetAvailability(
          id: id,
          state: AssetAvailabilityState.offline,
          totalBytes: r!.total,
        );
      case DownloadStage.failed:
        return AssetAvailability(
          id: id,
          state: AssetAvailabilityState.failed,
          totalBytes: r!.total,
          error: r.error,
        );
      case DownloadStage.waiting || null:
        break;
    }
    if (await assets.hasBytes(id)) {
      return AssetAvailability(id: id, state: AssetAvailabilityState.local);
    }
    if (!downloader.isAttached) {
      return AssetAvailability(
        id: id,
        state: AssetAvailabilityState.syncDisabled,
      );
    }
    final meta = await assets.getAsset(id);
    if (meta == null) {
      return AssetAvailability(id: id, state: AssetAvailabilityState.unknown);
    }
    return AssetAvailability(
      id: id,
      state: meta.storagePath == null
          ? AssetAvailabilityState.waitingForUpload
          : AssetAvailabilityState.remoteReady,
      totalBytes: meta.size,
    );
  }

  /// Availability changes are re-read in order per listener; a value equal to the last one
  /// is not emitted again; the stream closes after `local`.
  @override
  Stream<AssetAvailability> watch(AssetId id) {
    _listen();
    return Stream.multi((controller) {
      AssetAvailability? last;
      var done = false;
      var chain = Future<void>.value();
      late final StreamSubscription<AssetId?> sub;
      void refresh() {
        chain = chain.then((_) async {
          if (done) return;
          final AssetAvailability a;
          try {
            a = await availability(id);
          } on Object catch (e, s) {
            if (!done) controller.addError(e, s);
            return;
          }
          if (done || a == last) return;
          last = a;
          controller.add(a);
          if (a.state == AssetAvailabilityState.local) {
            done = true;
            unawaited(sub.cancel());
            unawaited(controller.close());
          }
        });
      }

      sub = _changes.stream.listen(
        (changed) {
          if (changed == null || changed == id) refresh();
        },
        onDone: () {
          done = true;
          unawaited(controller.close());
        },
      );
      // Cancel futures are not returned or awaited: a listener's done event would wait for
      // them (and under fake_async they complete outside the fake zone).
      controller.onCancel = () {
        done = true;
        unawaited(sub.cancel());
      };
      refresh();
    });
  }

  @override
  Future<bool> ensureLocal(
    AssetId id, {
    AssetPriority priority = AssetPriority.visible,
  }) {
    _listen();
    return downloader.ensureLocal(id, priority);
  }

  @override
  void cancel(AssetId id) => downloader.cancel(id);

  /// Emits the current summary on listen, then changes (by ==).
  @override
  Stream<AssetTransferSummary> get summary => Stream.multi((controller) {
    var last = _summary;
    controller.add(last);
    final sub = _summaries.stream.listen((s) {
      if (s == last) return;
      last = s;
      controller.add(s);
    }, onDone: controller.close);
    controller.onCancel = () {
      unawaited(sub.cancel());
    };
  });

  // ---- engine side ------------------------------------------------------------------------

  /// The account is attached (6.10.3 step 4): downloads may use [blobs]; a new uploader.
  void attach(RemoteBlobStore blobs) {
    if (_closed) return;
    _listen();
    _uploader?.close();
    _uploader = AssetUploader(
      assets: assets,
      blobs: blobs,
      config: config,
      random: _random,
      onChanged: _publish,
      report: report,
      onError: (e) => onError?.call('asset scan', e),
    );
    downloader.attach(blobs);
    _publish();
  }

  /// Live (uploads and downloads run) or not (6.9.2: offline, not live, clock paused).
  void setLive(bool live) {
    if (_closed) return;
    _uploader?.setActive(live);
    downloader.setLive(live);
    _changed(null);
  }

  /// Signed out: transfers stop.
  void detach() {
    _uploader?.close();
    _uploader = null;
    downloader.detach();
    _publish();
  }

  /// A push sent these asset records without storagePath (6.9.1 queue).
  void onAssetsPushed(Set<AssetId> ids) {
    final up = _uploader;
    if (up == null) return;
    ids.forEach(up.enqueue);
  }

  /// An apply group took these asset records.
  void onRemoteAssets(Iterable<AssetId> ids) => downloader.onRemoteAssets(ids);

  /// SyncEngine.usage: CORE Asset.size of uploaded / local-only assets.
  Future<SyncUsage> usage() async {
    var uploadedCount = 0, uploadedBytes = 0;
    var localCount = 0, localBytes = 0;
    for (final a in await assets.listAssets(uploaded: true)) {
      if (a.deletedAt != null) continue;
      uploadedCount++;
      uploadedBytes += a.size;
    }
    for (final a in await assets.listAssets(
      uploaded: false,
      hasLocalBytes: true,
    )) {
      if (a.deletedAt != null) continue;
      localCount++;
      localBytes += a.size;
    }
    return SyncUsage(
      uploadedAssetCount: uploadedCount,
      uploadedAssetBytes: uploadedBytes,
      localOnlyAssetCount: localCount,
      localOnlyAssetBytes: localBytes,
    );
  }

  /// Uploads or downloads still to do (SyncTestHarness.settle), or null.
  String? get busyReason => _uploader?.busyReason ?? downloader.busyReason;

  Future<void> close() async {
    if (_closed) return;
    detach();
    downloader.close();
    _closed = true;
    unawaited(_bytesSub?.cancel());
    _bytesSub = null;
    unawaited(_changes.close());
    unawaited(_summaries.close());
  }

  // ---- internals ------------------------------------------------------------------------

  void _listen() {
    if (_closed || _bytesSub != null) return;
    _bytesSub = assets.bytesArrived.listen((id) {
      downloader.onBytesArrived(id);
      // New local bytes of an asset not uploaded yet (put of a file another device
      // registered but has not uploaded): this device can upload them (6.9.1).
      _uploader?.enqueue(id);
    }, onError: (Object e) => onError?.call('bytesArrived', e));
  }

  void _changed(AssetId? id) {
    if (_closed) return;
    _changes.add(id);
    _publish();
  }

  void _publish() {
    if (_closed) return;
    final up = _uploader;
    var active = 0, done = 0, total = 0;
    for (final r in downloader.requests) {
      switch (r.stage) {
        case DownloadStage.queued:
          active++;
          total += r.total ?? 0;
        case DownloadStage.downloading:
          active++;
          done += r.received;
          total += r.total ?? 0;
        case DownloadStage.waiting ||
            DownloadStage.offline ||
            DownloadStage.failed:
          break;
      }
    }
    final s = AssetTransferSummary(
      uploadsPending: up?.pending ?? 0,
      uploadBytesDone: up?.batchBytesDone ?? 0,
      uploadBytesTotal: up?.batchBytesTotal ?? 0,
      downloadsActive: active,
      downloadBytesDone: done,
      downloadBytesTotal: total,
    );
    if (s == _summary) return;
    _summary = s;
    onSummary(s);
    _summaries.add(s);
  }
}
