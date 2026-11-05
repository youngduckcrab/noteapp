// lib/src/render/document_pool.dart — 06-pdf 4.7, 6.6 (PDF T7).
//
// DefaultPdfDocumentPool keeps the 4.7 parameter list word for word (plain named parameters
// assigned to private fields), hence:
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:collection';

import 'package:note_core/note_core.dart' as core;

import '../common/error_report.dart';
import '../engine/pdf_engine.dart';
import '../errors.dart';
import '../gateway/pdf_note_gateway.dart';
import '../tuning.dart';

abstract interface class PdfDocumentLease {
  core.AssetId get assetId;
  PdfEngineDocument get document;
  void release(); // idempotent
}

abstract interface class PdfDocumentPool {
  /// Opens (once, deduplicated) from gateway.readAssetBytes. Throws assetMissing / corrupt /
  /// passwordCancelled (needsPassword) / engineUnavailable. Failures are not cached (6.6).
  Future<PdfDocumentLease> acquire(core.AssetId assetId);

  /// Import hands over its already opened document (no second open).
  void adopt(core.AssetId assetId, PdfEngineDocument document);

  /// Ids whose bytes just arrived (gateway.bytesArrived, or ensureLocal() completed true).
  /// The pool has already dropped the failure memo for the id, so acquire() opens it again.
  Stream<core.AssetId> get assetArrived;

  /// P-2: requests the download through core.RemoteAssetFetcher (at most one request in flight
  /// per asset) and returns its shared progress stream. null when no fetcher is installed
  /// (before M4). Called by on-screen background handles only (6.7.7).
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId);
  int get openCount;
  Future<void> closeIdle();
  Future<void> dispose();
}

final class DefaultPdfDocumentPool implements PdfDocumentPool {
  /// [remoteAssets] = core.remoteAssetFetcherProvider (null until INFRA SyncModule, M4).
  ///
  /// Subscribes to gateway.bytesArrived at once (6.6 'arrival'); opens nothing until
  /// acquire().
  DefaultPdfDocumentPool({
    required PdfEngine engine,
    required PdfNoteGateway gateway,
    core.RemoteAssetFetcher? remoteAssets,
    int maxIdleDocuments = PdfTuning.maxIdleDocuments,
    Duration idleTtl = PdfTuning.idleDocumentTtl,
  }) : _engine = engine,
       _gateway = gateway,
       _remoteAssets = remoteAssets,
       _maxIdle = maxIdleDocuments,
       _idleTtl = idleTtl {
    _arrivedSub = gateway.bytesArrived.listen(_onArrived);
  }

  final PdfEngine _engine;
  final PdfNoteGateway _gateway;
  final core.RemoteAssetFetcher? _remoteAssets;
  final int _maxIdle;
  final Duration _idleTtl;
  late final StreamSubscription<core.AssetId> _arrivedSub;
  final StreamController<core.AssetId> _arrived =
      StreamController<core.AssetId>.broadcast();

  final Map<core.AssetId, _PoolEntry> _entries = {};
  final Map<core.AssetId, Future<PdfEngineDocument>> _opening = {};

  /// Ids with no lease, oldest first (6.6: more than maxIdle → close the oldest).
  final LinkedHashSet<core.AssetId> _idle = LinkedHashSet<core.AssetId>();

  /// 6.6: the same failure is returned at once for PdfTuning.failureMemo.
  final Map<core.AssetId, ({PdfIoException error, Timer timer})> _failures = {};

  /// Bumped on every arrival: an open that started before it never memoizes its failure.
  final Map<core.AssetId, int> _arrivals = {};

  /// One remote request (ensureLocal) in flight per asset; the value is that request.
  final Map<core.AssetId, Object> _remoteRequests = {};
  final Map<core.AssetId, _SharedRemoteWatch> _watches = {};
  bool _disposed = false;

  void _checkOpen() {
    if (_disposed) throw StateError('PdfDocumentPool is disposed');
  }

  @override
  Future<PdfDocumentLease> acquire(core.AssetId assetId) async {
    _checkOpen();
    final existing = _entries[assetId];
    if (existing != null) return _lease(existing);
    final memo = _failures[assetId];
    if (memo != null) throw memo.error;
    final opening = _opening[assetId] ??= _open(assetId);
    await opening;
    _checkOpen();
    final entry = _entries[assetId];
    if (entry == null) {
      // Closed again before this caller resumed (dispose / closeIdle): open anew.
      return acquire(assetId);
    }
    return _lease(entry);
  }

  Future<PdfEngineDocument> _open(core.AssetId assetId) async {
    final arrivals = _arrivals[assetId] ?? 0;
    try {
      // Future.sync: a synchronous throw still lands after acquire() stored this open.
      final bytes = await Future.sync(() => _gateway.readAssetBytes(assetId));
      if (bytes == null) {
        throw PdfIoException(
          PdfErrorCode.assetMissing,
          detail: 'asset $assetId has no bytes on this device',
        );
      }
      final document = await _engine.open(
        bytes,
        sourceName: 'asset:$assetId',
        transferOwnership: true,
      );
      final existing = _entries[assetId];
      if (_disposed || existing != null) {
        // Disposed meanwhile, or adopt() put a document in first.
        await document.dispose();
        if (_disposed) throw StateError('PdfDocumentPool is disposed');
        return existing!.document;
      }
      _entries[assetId] = _PoolEntry(assetId, document);
      return document;
    } on Object catch (e, s) {
      final error = e is PdfIoException
          ? e
          : e is StateError && _disposed
          ? null
          : PdfIoException(
              PdfErrorCode.corrupt,
              detail: 'could not open asset $assetId',
              cause: e,
            );
      if (error == null) rethrow;
      if (!_disposed && (_arrivals[assetId] ?? 0) == arrivals) {
        _remember(assetId, error);
      }
      Error.throwWithStackTrace(error, s);
    } finally {
      unawaited(_opening.remove(assetId));
    }
  }

  void _remember(core.AssetId assetId, PdfIoException error) {
    _failures.remove(assetId)?.timer.cancel();
    _failures[assetId] = (
      error: error,
      timer: Timer(PdfTuning.failureMemo, () => _failures.remove(assetId)),
    );
  }

  PdfDocumentLease _lease(_PoolEntry entry) {
    entry.refs++;
    entry.idleTimer?.cancel();
    entry.idleTimer = null;
    _idle.remove(entry.assetId);
    return _Lease(this, entry);
  }

  void _release(_PoolEntry entry) {
    if (!identical(_entries[entry.assetId], entry)) return; // closed already
    entry.refs--;
    if (entry.refs == 0) _makeIdle(entry);
  }

  void _makeIdle(_PoolEntry entry) {
    _idle.add(entry.assetId);
    entry.idleTimer = Timer(_idleTtl, () => _close(entry.assetId));
    while (_idle.length > _maxIdle) {
      _close(_idle.first);
    }
  }

  void _close(core.AssetId assetId) {
    final entry = _entries.remove(assetId);
    _idle.remove(assetId);
    if (entry == null) return;
    entry.idleTimer?.cancel();
    unawaited(entry.document.dispose());
  }

  @override
  void adopt(core.AssetId assetId, PdfEngineDocument document) {
    if (_disposed || _entries.containsKey(assetId)) {
      // The pool keeps the document it already has (same file imported again).
      unawaited(document.dispose());
      return;
    }
    _failures.remove(assetId)?.timer.cancel();
    final entry = _entries[assetId] = _PoolEntry(assetId, document);
    _makeIdle(entry);
  }

  @override
  Stream<core.AssetId> get assetArrived => _arrived.stream;

  void _onArrived(core.AssetId assetId) {
    if (_disposed) return;
    _arrivals[assetId] = (_arrivals[assetId] ?? 0) + 1;
    _failures.remove(assetId)?.timer.cancel();
    _remoteRequests.remove(assetId);
    _arrived.add(assetId);
  }

  @override
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId) {
    _checkOpen();
    final fetcher = _remoteAssets;
    if (fetcher == null) return null;
    if (!_remoteRequests.containsKey(assetId)) {
      final request = _remoteRequests[assetId] = Object();
      unawaited(_ensureLocal(fetcher, assetId, request));
    }
    return _watch(fetcher, assetId);
  }

  Future<void> _ensureLocal(
    core.RemoteAssetFetcher fetcher,
    core.AssetId assetId,
    Object request,
  ) async {
    final bool local;
    try {
      local = await fetcher.ensureLocal(assetId);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf document pool: ensureLocal($assetId)');
      if (identical(_remoteRequests[assetId], request)) {
        _remoteRequests.remove(assetId);
      }
      _watches[assetId]?.add(
        const core.RemoteAssetProgress(core.RemoteAssetState.failed),
      );
      return;
    }
    if (_disposed) return;
    if (local) {
      _onArrived(assetId);
    } else if (identical(_remoteRequests[assetId], request)) {
      // offline / waiting / failed / unavailable: asked again only when a page mounts anew.
      _remoteRequests.remove(assetId);
    }
  }

  Stream<core.RemoteAssetProgress> _watch(
    core.RemoteAssetFetcher fetcher,
    core.AssetId assetId,
  ) => Stream<core.RemoteAssetProgress>.multi((listener) {
    if (_disposed) {
      listener.closeSync();
      return;
    }
    final shared = _watches[assetId] ??= _SharedRemoteWatch(
      fetcher,
      assetId,
      onError: (e, s) {
        reportPdfError(e, s, 'pdf document pool: watch($assetId)');
        _remoteRequests.remove(assetId);
      },
      onIdle: () => _watches.remove(assetId),
    );
    shared.addListener(listener);
  });

  @override
  int get openCount => _entries.length;

  @override
  Future<void> closeIdle() async {
    for (final assetId in [..._idle]) {
      _close(assetId);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Not awaited: a cancel future may complete in the root zone only (fake_async tests).
    unawaited(_arrivedSub.cancel());
    for (final memo in _failures.values) {
      memo.timer.cancel();
    }
    _failures.clear();
    _remoteRequests.clear();
    for (final watch in [..._watches.values]) {
      watch.close();
    }
    _watches.clear();
    final entries = [..._entries.values];
    _entries.clear();
    _idle.clear();
    for (final entry in entries) {
      entry.idleTimer?.cancel();
      await entry.document.dispose();
    }
    await _arrived.close();
  }
}

final class _PoolEntry {
  _PoolEntry(this.assetId, this.document);
  final core.AssetId assetId;
  final PdfEngineDocument document;
  int refs = 0;
  Timer? idleTimer;
}

final class _Lease implements PdfDocumentLease {
  _Lease(this._pool, this._entry);
  final DefaultPdfDocumentPool _pool;
  final _PoolEntry _entry;
  bool _released = false;

  @override
  core.AssetId get assetId => _entry.assetId;

  @override
  PdfEngineDocument get document => _entry.document;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _pool._release(_entry);
  }
}

/// fetcher.watch(id) shared by every handle of one asset (6.6): one subscription while any
/// listener is left; a new listener gets the latest value first.
final class _SharedRemoteWatch {
  _SharedRemoteWatch(
    core.RemoteAssetFetcher fetcher,
    this.assetId, {
    required this.onError,
    required this.onIdle,
  }) {
    _sub = fetcher
        .watch(assetId)
        .listen(
          add,
          onError: (Object e, StackTrace s) {
            onError(e, s);
            add(const core.RemoteAssetProgress(core.RemoteAssetState.failed));
          },
        );
  }

  final core.AssetId assetId;
  final void Function(Object error, StackTrace stack) onError;
  final void Function() onIdle;
  late final StreamSubscription<core.RemoteAssetProgress> _sub;
  final Set<MultiStreamController<core.RemoteAssetProgress>> _listeners = {};
  core.RemoteAssetProgress? _latest;

  void add(core.RemoteAssetProgress progress) {
    _latest = progress;
    for (final listener in [..._listeners]) {
      listener.addSync(progress);
    }
  }

  void addListener(MultiStreamController<core.RemoteAssetProgress> listener) {
    _listeners.add(listener);
    final latest = _latest;
    if (latest != null) listener.add(latest);
    listener.onCancel = () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        unawaited(_sub.cancel());
        onIdle();
      }
    };
  }

  void close() {
    unawaited(_sub.cancel());
    for (final listener in [..._listeners]) {
      listener.closeSync();
    }
    _listeners.clear();
  }
}
