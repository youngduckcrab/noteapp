// Internal (not exported). Byte uploads of this device's assets (6.9.1). One queue, at most
// assetUploadConcurrency transfers at a time, only while the engine is live. Each asset:
// stat first (another device may already have uploaded the same bytes — dedupe, S09b),
// otherwise upload with the storage rules' metadata (6.14), then markUploaded: CORE records
// {storagePath} in the outbox with origin local, so the next push carries it (5.1.2 S-17).
// Failures back off per asset (6.8.1); assetUploadFailed after 3 failures in a row, and
// the asset keeps being retried.
import 'dart:async';
import 'dart:math';

import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../common/cancel_token.dart';
import '../common/errors.dart';
import '../config.dart';
import '../engine/backoff.dart';
import '../status/sync_issue.dart';

/// Sets ([message] non-null) or clears the issue [code] of asset [id] (engine status).
typedef AssetIssueReport = void Function(
  SyncIssueCode code,
  AssetId id,
  String? message,
);

final class AssetUploader {
  AssetUploader({
    required this.assets,
    required this.blobs,
    required this.config,
    required this._random,
    required this.onChanged,
    required this.report,
    this.onError,
  });

  /// Consecutive failures of one asset before assetUploadFailed (6.9.1).
  static const int failuresBeforeIssue = 3;

  final AssetStore assets;
  final RemoteBlobStore blobs;
  final SyncConfig config;

  /// Pending count or batch bytes changed.
  final void Function() onChanged;
  final AssetIssueReport report;

  /// A scan of the local assets failed (logged by the engine).
  final void Function(Object error)? onError;

  final Random _random;

  /// Waiting for a slot, in arrival order.
  final Set<AssetId> _ready = {};
  final Map<AssetId, SyncCancelToken> _running = {};

  /// Waiting for a per-asset backoff.
  final Map<AssetId, Timer> _retry = {};
  final Map<AssetId, Backoff> _backoff = {};

  /// The current batch (6.9.1 AssetTransferSummary): size and bytes done per asset started
  /// since the queue was last empty.
  final Map<AssetId, int> _batchSize = {}, _batchDone = {};

  bool _active = false, _closed = false, _scanned = false;
  int _scanning = 0;

  /// Objects written / assets marked uploaded after a stat found the object.
  int uploads = 0, deduped = 0;

  bool get isActive => _active;

  /// Assets queued, uploading or waiting for a retry.
  int get pending => {..._ready, ..._running.keys, ..._retry.keys}.length;

  int get batchBytesTotal => _sum(_batchSize);
  int get batchBytesDone => _sum(_batchDone);

  /// Work left while active (SyncTestHarness.settle), or null.
  String? get busyReason {
    if (!_active || _closed) return null;
    if (_scanning > 0) return 'scanning assets to upload';
    final n = pending;
    return n == 0 ? null : '$n asset uploads pending';
  }

  /// Live (true) or not. Going active scans the local assets once and retries every asset
  /// that waits for a backoff at once (back online); going inactive starts nothing new.
  void setActive(bool active) {
    if (_closed || _active == active) return;
    _active = active;
    if (!active) return;
    if (!_scanned) {
      _scanned = true;
      unawaited(_scan());
    }
    for (final MapEntry(key: id, value: timer) in _retry.entries) {
      timer.cancel();
      _ready.add(id);
    }
    _retry.clear();
    _pump();
  }

  /// Uploads [id] if it is a local asset without storagePath (checked when it starts).
  void enqueue(AssetId id) {
    if (_closed || _running.containsKey(id) || _retry.containsKey(id)) return;
    if (!_ready.add(id)) return;
    onChanged();
    _pump();
  }

  /// Stops every transfer; nothing more happens.
  void close() {
    if (_closed) return;
    _closed = true;
    _active = false;
    for (final token in _running.values) {
      token.cancel();
    }
    for (final timer in _retry.values) {
      timer.cancel();
    }
    _running.clear();
    _retry.clear();
    _ready.clear();
    _batchSize.clear();
    _batchDone.clear();
  }

  Future<void> _scan() async {
    _scanning++;
    try {
      final list = await assets.listAssets(
        uploaded: false,
        hasLocalBytes: true,
      );
      for (final a in list) {
        if (a.deletedAt == null) enqueue(a.id);
      }
    } on Object catch (e) {
      onError?.call(e);
    } finally {
      _scanning--;
    }
  }

  void _pump() {
    final slots = config.assetUploadConcurrency < 1
        ? 1
        : config.assetUploadConcurrency;
    while (_active &&
        !_closed &&
        _ready.isNotEmpty &&
        _running.length < slots) {
      final id = _ready.first;
      _ready.remove(id);
      final token = SyncCancelToken();
      _running[id] = token;
      unawaited(_run(id, token));
    }
  }

  Future<void> _run(AssetId id, SyncCancelToken token) async {
    Object? failure;
    try {
      await _upload(id, token);
    } on Object catch (e) {
      failure = e;
    }
    if (_closed || token.isCancelled) return;
    _running.remove(id);
    if (failure == null) {
      _backoff.remove(id);
      report(SyncIssueCode.assetUploadFailed, id, null);
    } else {
      _failed(id, failure);
    }
    if (pending == 0) {
      _batchSize.clear();
      _batchDone.clear();
    }
    onChanged();
    _pump();
  }

  Future<void> _upload(AssetId id, SyncCancelToken token) async {
    final asset = await assets.getAsset(id);
    if (asset == null ||
        asset.deletedAt != null ||
        asset.storagePath != null ||
        !asset.hasLocalBytes) {
      _forget(id);
      return;
    }
    if (asset.size > config.maxAssetUploadBytes) {
      _forget(id);
      report(
        SyncIssueCode.assetTooLarge,
        id,
        'asset $id has ${asset.size} B, more than the upload limit of '
        '${config.maxAssetUploadBytes} B: kept on this device only',
      );
      return;
    }
    _batchSize[id] = asset.size;
    _batchDone[id] = 0;
    onChanged();
    final path = blobs.pathFor(id);
    final info = await blobs.stat(path);
    token.throwIfCancelled();
    final present = info != null && (info.sha256 == null || info.sha256 == id);
    if (present) {
      deduped++;
    } else {
      final bytes = await assets.readBytes(id);
      token.throwIfCancelled();
      if (bytes == null) {
        _forget(id);
        return;
      }
      await blobs.upload(
        path,
        bytes,
        contentType: asset.mimeType,
        metadata: {
          'sha256': id,
          'size': '${asset.size}',
          'type': asset.type.name,
        },
        onProgress: (sent, _) {
          if (token.isCancelled || !_batchDone.containsKey(id)) return;
          _batchDone[id] = sent;
          onChanged();
        },
        cancel: token,
      );
      uploads++;
    }
    token.throwIfCancelled();
    await assets.markUploaded(id, path);
    if (_batchSize.containsKey(id)) _batchDone[id] = asset.size;
  }

  void _failed(AssetId id, Object error) {
    final backoff = _backoff.putIfAbsent(
      id,
      () => Backoff(config: config, random: _random),
    );
    final delay = backoff.next(
      error is SyncBackendException ? error.code : null,
    );
    if (_batchDone.containsKey(id)) _batchDone[id] = 0;
    if (backoff.failures >= failuresBeforeIssue) {
      report(
        SyncIssueCode.assetUploadFailed,
        id,
        'upload of asset $id failed ${backoff.failures} times in a row '
        '($error); retrying',
      );
    }
    _retry[id] = Timer(delay, () {
      if (_closed || _retry.remove(id) == null) return;
      _ready.add(id);
      _pump();
    });
  }

  void _forget(AssetId id) {
    _batchSize.remove(id);
    _batchDone.remove(id);
  }

  static int _sum(Map<AssetId, int> m) {
    var total = 0;
    for (final v in m.values) {
      total += v;
    }
    return total;
  }
}
