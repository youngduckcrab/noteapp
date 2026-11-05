// Internal (not exported). On-demand downloads (6.9.2). A request per asset id lives until
// the bytes are local or it is cancelled; requests that cannot go on now (no metadata yet,
// not uploaded yet, signed out, not live) wait and go on by themselves when that changes
// (onRemoteAssets, attach + setLive). At most assetDownloadConcurrency transfers at a time,
// visible priority first. CORE putDownloadedBytes verifies the sha-256: a mismatch is
// downloaded once more, then the request fails with assetCorrupt. A lost connection waits
// (offline) and retries with backoff while live; any other error fails the request with
// assetDownloadFailed until the next ensureLocal.
import 'dart:async';
import 'dart:math';

import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../common/cancel_token.dart';
import '../common/errors.dart';
import '../config.dart';
import '../engine/backoff.dart';
import '../status/sync_issue.dart';
import 'asset_uploader.dart';
import 'sync_asset_service.dart';

enum DownloadStage {
  /// Cannot start now: no metadata, no storagePath, or not attached. The availability
  /// comes from the store.
  waiting,
  queued,
  downloading,

  /// Not live, or the connection was lost: goes on when live again.
  offline,

  /// See [DownloadRequest.error]; tried again on the next ensureLocal.
  failed,
}

final class DownloadRequest {
  DownloadRequest(this.id, this.priority, this.seq);

  final AssetId id;
  AssetPriority priority;

  /// Arrival order (FIFO within a priority).
  final int seq;
  DownloadStage stage = DownloadStage.waiting;
  String? path;
  int received = 0;
  int? total;
  SyncIssue? error;
  int hashFailures = 0;

  SyncCancelToken? _token;
  Completer<bool>? _finished;
  Future<bool>? _evaluating;
  bool _recheck = false;
  Timer? _retry;
  Backoff? _backoff;
}

final class AssetDownloader {
  AssetDownloader({
    required this.assets,
    required this.config,
    required this._random,
    required this.nowMillis,
    required this.onChanged,
    required this.report,
  });

  /// Downloads of one request after a hash mismatch, the first included (6.9.2: retry once).
  static const int hashAttempts = 2;

  final AssetStore assets;
  final SyncConfig config;
  final int Function() nowMillis;

  /// The availability of [id] may have changed (null: of every asset).
  final void Function(AssetId? id) onChanged;
  final AssetIssueReport report;
  final Random _random;

  final Map<AssetId, DownloadRequest> _requests = {};
  RemoteBlobStore? _blobs;
  bool _live = false, _closed = false;
  int _seq = 0, _running = 0;

  /// Completed downloads (bytes stored).
  int downloads = 0;

  bool get isAttached => _blobs != null;
  bool get isLive => _live;

  DownloadRequest? requestOf(AssetId id) => _requests[id];

  Iterable<DownloadRequest> get requests => _requests.values;

  /// Work in progress (SyncTestHarness.settle), or null.
  String? get busyReason {
    if (_closed) return null;
    var busy = 0;
    for (final r in _requests.values) {
      if (r._evaluating != null || (_live && r._retry != null)) busy++;
    }
    return busy == 0 ? null : '$busy asset downloads in progress';
  }

  Future<bool> ensureLocal(AssetId id, AssetPriority priority) {
    if (_closed) return assets.hasBytes(id);
    var r = _requests[id];
    if (r == null) {
      r = _requests[id] = DownloadRequest(id, priority, _seq++);
    } else {
      if (priority == AssetPriority.visible) r.priority = priority;
      if (r.stage == DownloadStage.failed) {
        r
          ..stage = DownloadStage.waiting
          ..error = null
          ..hashFailures = 0;
        _clearIssues(id);
        onChanged(id);
      }
    }
    return _kick(r);
  }

  void cancel(AssetId id) {
    final r = _requests.remove(id);
    if (r == null) return;
    r._token?.cancel();
    r._retry?.cancel();
    r._retry = null;
    _complete(r, false);
    _clearIssues(id);
    onChanged(id);
  }

  void attach(RemoteBlobStore blobs) {
    if (_closed) return;
    _blobs = blobs;
    onChanged(null);
  }

  /// Signed out: transfers stop; requests wait (syncDisabled) until the next attach.
  void detach() {
    _blobs = null;
    _live = false;
    for (final r in _requests.values) {
      r._token?.cancel();
      r._token = null;
      r._retry?.cancel();
      r._retry = null;
      r
        ..stage = DownloadStage.waiting
        ..error = null
        ..hashFailures = 0
        ..received = 0;
      _complete(r, false);
    }
    onChanged(null);
  }

  void setLive(bool live) {
    if (_closed || _live == live) return;
    _live = live;
    if (!live) {
      for (final r in _requests.values) {
        r._retry?.cancel();
        r._retry = null;
        if (r.stage == DownloadStage.queued) {
          r.stage = DownloadStage.offline;
          _complete(r, false);
          onChanged(r.id);
        }
      }
      return;
    }
    for (final r in List.of(_requests.values)) {
      if (r.stage == DownloadStage.waiting ||
          r.stage == DownloadStage.offline) {
        unawaited(_kick(r));
      }
    }
  }

  /// Asset records were applied: waiting requests for them may go on now.
  void onRemoteAssets(Iterable<AssetId> ids) {
    for (final id in ids) {
      final r = _requests[id];
      if (r != null && r.stage == DownloadStage.waiting) unawaited(_kick(r));
      onChanged(id);
    }
  }

  /// The bytes of [id] are local (CORE bytesArrived): the request is done.
  void onBytesArrived(AssetId id) {
    final r = _requests[id];
    if (r != null) _resolve(r);
    onChanged(id);
  }

  void close() {
    if (_closed) return;
    detach();
    _closed = true;
    _requests.clear();
  }

  // ---- internals ------------------------------------------------------------------------

  /// One evaluation per request at a time; callers during it share its result. A change
  /// noticed during an evaluation that ends waiting evaluates again.
  Future<bool> _kick(DownloadRequest r) {
    final current = r._evaluating;
    if (current != null) {
      r._recheck = true;
      return current;
    }
    r._recheck = false;
    final f = _evaluate(r);
    r._evaluating = f;
    unawaited(
      f.then((ok) {
        if (!identical(r._evaluating, f)) return;
        r._evaluating = null;
        if (!ok &&
            r._recheck &&
            identical(_requests[r.id], r) &&
            (r.stage == DownloadStage.waiting ||
                r.stage == DownloadStage.offline)) {
          unawaited(_kick(r));
        }
      }),
    );
    return f;
  }

  Future<bool> _evaluate(DownloadRequest r) async {
    try {
      if (await assets.hasBytes(r.id)) {
        _resolve(r);
        return true;
      }
      if (!_current(r)) return false;
      if (_blobs == null) {
        _setStage(r, DownloadStage.waiting);
        return false;
      }
      final meta = await assets.getAsset(r.id);
      if (!_current(r)) return false;
      if (meta == null || meta.storagePath == null) {
        _setStage(r, DownloadStage.waiting);
        return false;
      }
      r.total = meta.size;
      if (!_live || _blobs == null) {
        _setStage(r, DownloadStage.offline);
        return false;
      }
      r
        ..path = meta.storagePath
        ..received = 0;
      final finished = r._finished = Completer<bool>();
      _setStage(r, DownloadStage.queued);
      _pump();
      return await finished.future;
    } on Object catch (e) {
      if (!_current(r)) return false;
      _fail(r, SyncIssueCode.assetDownloadFailed, 'reading asset ${r.id}: $e');
      return false;
    }
  }

  bool _current(DownloadRequest r) => !_closed && identical(_requests[r.id], r);

  void _pump() {
    final slots = config.assetDownloadConcurrency < 1
        ? 1
        : config.assetDownloadConcurrency;
    while (_live && _running < slots) {
      final blobs = _blobs;
      if (blobs == null) return;
      DownloadRequest? next;
      for (final r in _requests.values) {
        if (r.stage != DownloadStage.queued) continue;
        if (next == null ||
            (r.priority.index < next.priority.index) ||
            (r.priority == next.priority && r.seq < next.seq)) {
          next = r;
        }
      }
      if (next == null) return;
      _running++;
      unawaited(_download(next, blobs));
    }
  }

  Future<void> _download(DownloadRequest r, RemoteBlobStore blobs) async {
    final token = r._token = SyncCancelToken();
    final finished = r._finished;
    _setStage(r, DownloadStage.downloading);
    bool? ok;
    try {
      while (true) {
        final bytes = await blobs.download(
          r.path!,
          maxBytes: config.maxAssetDownloadBytes,
          onProgress: (received, total) {
            if (token.isCancelled) return;
            r
              ..received = received
              ..total = total;
            onChanged(r.id);
          },
          cancel: token,
        );
        token.throwIfCancelled();
        try {
          await assets.putDownloadedBytes(r.id, bytes);
          downloads++;
          ok = true;
          break;
        } on AssetHashMismatchException catch (e) {
          token.throwIfCancelled();
          r.hashFailures++;
          if (r.hashFailures >= hashAttempts) {
            _fail(
              r,
              SyncIssueCode.assetCorrupt,
              'downloaded bytes of asset ${r.id} failed the hash check '
              '${r.hashFailures} times ($e)',
            );
            ok = false;
            break;
          }
          r.received = 0;
          onChanged(r.id);
        }
      }
    } on SyncBackendException catch (e) {
      if (!token.isCancelled && identical(r._token, token)) {
        if (e.code.isConnectivity) {
          _lostConnection(r);
        } else {
          _fail(
            r,
            SyncIssueCode.assetDownloadFailed,
            'download of asset ${r.id} failed ($e)',
          );
        }
      }
      ok = false;
    } on Object catch (e) {
      if (!token.isCancelled && identical(r._token, token)) {
        _fail(
          r,
          SyncIssueCode.assetDownloadFailed,
          'storing asset ${r.id} failed ($e)',
        );
      }
      ok = false;
    } finally {
      _running--;
    }
    if (identical(r._token, token)) r._token = null;
    if (ok) {
      if (_requests[r.id] == r) r._backoff = null;
      _resolve(r);
    }
    if (finished != null && !finished.isCompleted) finished.complete(ok);
    _pump();
  }

  /// The transfer stopped on a connectivity error: offline, retried with backoff while live
  /// (and at once when live again).
  void _lostConnection(DownloadRequest r) {
    r.received = 0;
    _setStage(r, DownloadStage.offline);
    if (!_live) return;
    final delay = (r._backoff ??= Backoff(
      config: config,
      random: _random,
    )).next(SyncErrorCode.network);
    r._retry?.cancel();
    r._retry = Timer(delay, () {
      r._retry = null;
      if (_current(r) && r.stage == DownloadStage.offline) unawaited(_kick(r));
    });
  }

  void _fail(DownloadRequest r, SyncIssueCode code, String message) {
    final now = nowMillis();
    r
      ..stage = DownloadStage.failed
      ..received = 0
      ..error = SyncIssue(
        code: code,
        message: message,
        firstAt: now,
        lastAt: now,
        assetId: r.id,
      );
    report(code, r.id, message);
    onChanged(r.id);
  }

  void _resolve(DownloadRequest r) {
    if (identical(_requests[r.id], r)) _requests.remove(r.id);
    r._retry?.cancel();
    r._retry = null;
    r._token?.cancel();
    _complete(r, true);
    _clearIssues(r.id);
    onChanged(r.id);
  }

  void _setStage(DownloadRequest r, DownloadStage stage) {
    if (stage == DownloadStage.queued || stage == DownloadStage.downloading) {
      r._retry?.cancel();
      r._retry = null;
    }
    r
      ..stage = stage
      ..error = null;
    onChanged(r.id);
  }

  void _complete(DownloadRequest r, bool value) {
    final finished = r._finished;
    r._finished = null;
    if (finished != null && !finished.isCompleted) finished.complete(value);
  }

  void _clearIssues(AssetId id) {
    report(SyncIssueCode.assetDownloadFailed, id, null);
    report(SyncIssueCode.assetCorrupt, id, null);
  }
}
