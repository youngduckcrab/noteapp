import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../backend/profile.dart';
import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../common/cancel_token.dart';
import '../common/errors.dart';
import '../common/server_cursor.dart';
import 'fake_blob_store.dart';
import 'fake_network.dart';
import 'fake_sync_server.dart';

/// Via FakeSyncServer.connect.
///
/// One device's view of the FakeSyncServer through its FakeNetworkLink (see
/// there for latency, offline and faults). The watch stream always sends its
/// initial result (possibly empty) first, then one batch per commit (or late
/// visibility) with the chunks that match; it is opened when listened to. After
/// [close] its watch streams are done and new calls throw StateError.
final class FakeSyncBackend implements SyncBackend {
  @internal
  FakeSyncBackend.internal({
    required this._server,
    required this.uid,
    required this._link,
  }) {
    blobs = _LinkedBlobStore(this, _server.blobsOf(uid));
  }

  final FakeSyncServer _server;
  final FakeNetworkLink _link;
  bool _closed = false;
  final Set<_WatchSession> _watches = {};

  @override
  final String uid;

  @override
  late final RemoteBlobStore blobs;

  @override
  Future<void> commitChunks(List<ChunkWrite> chunks) =>
      _roundTrip(FakeOp.commit, () {
        final code = _link.rejectionFor(chunks);
        if (code != null) {
          throw SyncBackendException(code, 'commit rejected by the server');
        }
        _server.serveCommit(uid, chunks);
      });

  @override
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  }) => _roundTrip(
    FakeOp.fetch,
    () => _server.serveFetch(
      uid,
      since: since,
      pageToken: pageToken,
      limit: limit,
    ),
  );

  @override
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since}) {
    _checkOpen();
    final session = _WatchSession(this, since);
    return session.controller.stream;
  }

  @override
  Future<int?> countChunks({ServerCursor? since}) =>
      _roundTrip(FakeOp.count, () => _server.serveCount(uid, since: since));

  @override
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  }) => _roundTrip(
    FakeOp.fetch,
    () => _server.serveScope(uid, scope, pageToken: pageToken, limit: limit),
  );

  @override
  Future<void> deleteChunks(List<String> ids) =>
      _roundTrip(FakeOp.delete, () => _server.serveDelete(uid, ids));

  @override
  Future<void> upsertProfile(UserProfile profile) =>
      _roundTrip(FakeOp.profile, () => _server.serveProfile(uid, profile));

  @override
  Future<ServerCursor> upsertDevice(DeviceInfo device) =>
      _roundTrip(FakeOp.device, () => _server.serveDevice(uid, device));

  @override
  Future<List<RemoteChunk>> getChunks(List<String> ids) =>
      _roundTrip(FakeOp.byId, () => _server.serveGetChunks(uid, ids));

  @override
  Future<void> close() async {
    _closed = true;
    for (final session in List.of(_watches)) {
      session.end();
    }
  }

  // ---------------------------------------------------------------------------

  void _checkOpen() {
    if (_closed) throw StateError('FakeSyncBackend($uid) is closed');
  }

  /// Request → [serve] on the server → response, with the link's latency,
  /// offline state and the fault queued for [op].
  Future<T> _roundTrip<T>(FakeOp op, T Function() serve) async {
    _checkOpen();
    final fault = await _request(op);
    T result;
    try {
      result = serve();
    } on SyncBackendException {
      await _respond(null);
      rethrow;
    }
    await _respond(fault);
    return result;
  }

  /// Counts the call, waits for the request to arrive and throws the faults
  /// that stop it before the server; returns the fault still to apply
  /// (FakeAckLost or FakeInterrupt on a transfer) or null.
  Future<FakeFault?> _request(FakeOp op, {bool transfer = false}) async {
    final fault = _link.beginCall(op);
    if (!_link.online) throw _network('offline');
    await Future<void>.delayed(_link.latency);
    if (!_link.online) throw _network('offline');
    switch (fault) {
      case FakeNetworkError():
        throw _network('injected network error');
      case FakeInterrupt() when !transfer:
        throw _network('injected network error');
      case FakeErrorCode(:final code):
        await Future<void>.delayed(_link.latency);
        throw SyncBackendException(code, 'injected ${code.name}');
      case FakeAckLost() || FakeInterrupt() || null:
        return fault;
    }
  }

  /// Waits for the response; throws a network error when it is lost.
  Future<void> _respond(FakeFault? fault) async {
    await Future<void>.delayed(_link.latency);
    if (!_link.online) throw _network('offline before the response');
    if (fault is FakeAckLost) throw _network('injected lost response');
  }

  static SyncBackendException _network(String message) =>
      SyncBackendException(SyncErrorCode.network, message);
}

/// One watchChunks stream: opened on listen, ended by the listener's cancel,
/// an offline link, a fault or FakeSyncBackend.close.
final class _WatchSession {
  _WatchSession(this.backend, this.since) {
    controller = StreamController<List<RemoteChunk>>(
      onListen: _start,
      onCancel: _stop,
    );
  }

  final FakeSyncBackend backend;
  final ServerCursor? since;
  late final StreamController<List<RemoteChunk>> controller;
  bool _ended = false;
  void Function()? _cancelServer;
  void Function()? _cancelOffline;

  /// Batches sent by the server, in order, not yet delivered.
  final List<_Pending> _inFlight = [];

  FakeNetworkLink get _link => backend._link;

  Future<void> _start() async {
    backend._watches.add(this);
    _cancelOffline = _link.onOffline(
      () => _fail(FakeSyncBackend._network('offline')),
    );
    try {
      final fault = await backend._request(FakeOp.watch);
      if (_ended) return;
      if (fault != null) {
        // FakeAckLost: the listen reached the server, the answer did not.
        throw FakeSyncBackend._network('injected network error');
      }
    } on SyncBackendException catch (e) {
      _fail(e);
      return;
    }
    final (initial, cancel) = backend._server.serveWatch(
      backend.uid,
      since: since,
      onBatch: _send,
    );
    _cancelServer = cancel;
    _send(initial);
  }

  void _send(List<RemoteChunk> batch) {
    if (_ended) return;
    final pending = _Pending(batch);
    _inFlight.add(pending);
    Timer(_link.latency, () => _arrive(pending));
  }

  /// Delivers every batch up to [pending] in send order.
  void _arrive(_Pending pending) {
    if (_ended || !_inFlight.contains(pending)) return;
    while (_inFlight.isNotEmpty) {
      final next = _inFlight.removeAt(0);
      controller.add(next.batch);
      if (identical(next, pending)) break;
    }
  }

  void _fail(SyncBackendException error) {
    if (_ended) return;
    _release();
    controller
      ..addError(error)
      ..close();
  }

  /// FakeSyncBackend.close: done without error.
  void end() {
    if (_ended) return;
    _release();
    controller.close();
  }

  void _stop() {
    if (_ended) return;
    _release();
  }

  void _release() {
    _ended = true;
    _inFlight.clear();
    _cancelServer?.call();
    _cancelOffline?.call();
    backend._watches.remove(this);
  }
}

final class _Pending {
  _Pending(this.batch);
  final List<RemoteChunk> batch;
}

/// FakeSyncBackend.blobs: the uid's FakeBlobStore through the link.
final class _LinkedBlobStore implements RemoteBlobStore {
  _LinkedBlobStore(this.backend, this.store);

  final FakeSyncBackend backend;
  final FakeBlobStore store;

  FakeNetworkLink get _link => backend._link;

  @override
  String pathFor(AssetId id) => store.pathFor(id);

  @override
  Future<RemoteBlobInfo?> stat(String path) =>
      backend._roundTrip(FakeOp.stat, () => store.serveStat(path));

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
  }) async {
    backend._checkOpen();
    final fault = await backend._request(FakeOp.upload, transfer: true);
    try {
      await store.serveUpload(
        path,
        bytes,
        contentType: contentType,
        metadata: metadata,
        onProgress: onProgress,
        cancel: cancel,
        stopAt: _stopAt(fault, bytes.length),
        isOnline: () => _link.online,
      );
    } on SyncBackendException catch (e) {
      if (_immediate(e.code)) rethrow;
      await backend._respond(null);
      rethrow;
    }
    await backend._respond(fault);
  }

  @override
  Future<Uint8List> download(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
  }) async {
    backend._checkOpen();
    final fault = await backend._request(FakeOp.download, transfer: true);
    final size = store.objects[path]?.length ?? 0;
    final Uint8List bytes;
    try {
      bytes = await store.serveDownload(
        path,
        maxBytes: maxBytes,
        onProgress: onProgress,
        cancel: cancel,
        stopAt: _stopAt(fault, size),
        isOnline: () => _link.online,
      );
    } on SyncBackendException catch (e) {
      if (_immediate(e.code)) rethrow;
      await backend._respond(null);
      rethrow;
    }
    await backend._respond(fault);
    return bytes;
  }

  /// Errors raised on the client side (lost link, cancel): no response to wait
  /// for.
  static bool _immediate(SyncErrorCode code) =>
      code == SyncErrorCode.network || code == SyncErrorCode.cancelled;

  static int? _stopAt(FakeFault? fault, int total) => switch (fault) {
    FakeInterrupt(:final fraction) => (total * fraction).floor(),
    _ => null,
  };
}
