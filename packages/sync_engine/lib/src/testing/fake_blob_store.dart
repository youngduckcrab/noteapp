import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../common/cancel_token.dart';
import '../common/errors.dart';

/// Via FakeSyncServer.blobsOf.
///
/// The server-side object store of one uid. Its own methods act on the server
/// directly (no latency, no faults); FakeSyncBackend.blobs reaches the same
/// store through the device's FakeNetworkLink. Rules of 6.14 storage.rules:
/// path `users/{uid}/assets/{64 hex}` of this uid, at most 300 MiB, metadata
/// `sha256` = asset id, objects are immutable. Uploading an object that
/// already exists with the same `sha256` succeeds without writing (what
/// FirebaseBlobStore makes of the permission-denied answer, 6.4.6).
///
/// Bytes move in 1 MiB pieces of 10 ms (virtual) each; `onProgress` is called
/// with 0 first and after every piece. [uploadCount] / [downloadCount] count
/// objects written / transfers completed. Tests may change [objects] directly
/// (e.g. corrupt bytes); `stat` reports the size of the stored bytes.
final class FakeBlobStore implements RemoteBlobStore {
  @internal
  FakeBlobStore.internal({required this.uid});

  /// The owner (path prefix `users/{uid}/assets/`).
  @internal
  final String uid;

  final Map<String, Uint8List> _objects = {};
  final Map<String, _ObjectMeta> _meta = {};

  Map<String, Uint8List> get objects => _objects;
  int uploadCount = 0, downloadCount = 0;

  static const int _maxObjectBytes = 300 * 1024 * 1024;
  static const int _pieceBytes = 1024 * 1024;
  static const Duration _pieceTime = Duration(milliseconds: 10);
  static final RegExp _assetIdPattern = RegExp(r'^[0-9a-f]{64}$');

  @override
  String pathFor(AssetId id) => 'users/$uid/assets/$id';

  @override
  Future<RemoteBlobInfo?> stat(String path) async => serveStat(path);

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
  }) => serveUpload(
    path,
    bytes,
    contentType: contentType,
    metadata: metadata,
    onProgress: onProgress,
    cancel: cancel,
  );

  @override
  Future<Uint8List> download(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
  }) => serveDownload(
    path,
    maxBytes: maxBytes,
    onProgress: onProgress,
    cancel: cancel,
  );

  @internal
  RemoteBlobInfo? serveStat(String path) {
    _checkPath(path);
    final bytes = _objects[path];
    if (bytes == null) return null;
    final meta = _meta[path];
    return RemoteBlobInfo(
      path: path,
      size: bytes.length,
      sha256: meta?.metadata['sha256'],
      contentType: meta?.contentType,
    );
  }

  /// [stopAt]: bytes after which the transfer fails with a network error
  /// (FakeInterrupt). [isOnline] is checked before every piece.
  @internal
  Future<void> serveUpload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
    int? stopAt,
    bool Function()? isOnline,
  }) async {
    cancel?.throwIfCancelled();
    final assetId = _checkPath(path);
    if (bytes.length > _maxObjectBytes) {
      throw _denied('object larger than 300 MiB', path);
    }
    if (metadata['sha256'] != assetId) {
      throw _denied('metadata sha256 must equal the asset id', path);
    }
    final existing = _objects[path];
    if (existing != null) {
      if (_meta[path]?.metadata['sha256'] == assetId &&
          existing.length == bytes.length) {
        onProgress?.call(bytes.length, bytes.length);
        return;
      }
      throw _denied('objects are immutable', path);
    }
    await _transfer(bytes.length, onProgress, cancel, stopAt, isOnline);
    _objects[path] = Uint8List.fromList(bytes);
    _meta[path] = _ObjectMeta(contentType, Map.of(metadata));
    uploadCount++;
  }

  @internal
  Future<Uint8List> serveDownload(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
    int? stopAt,
    bool Function()? isOnline,
  }) async {
    cancel?.throwIfCancelled();
    _checkPath(path);
    final bytes = _objects[path];
    if (bytes == null) {
      throw SyncBackendException(SyncErrorCode.notFound, 'no object $path');
    }
    if (bytes.length > maxBytes) {
      throw SyncBackendException(
        SyncErrorCode.invalidArgument,
        'object of ${bytes.length} B is larger than maxBytes $maxBytes: $path',
      );
    }
    final copy = Uint8List.fromList(bytes);
    await _transfer(copy.length, onProgress, cancel, stopAt, isOnline);
    downloadCount++;
    return copy;
  }

  Future<void> _transfer(
    int total,
    void Function(int done, int total)? onProgress,
    SyncCancelToken? cancel,
    int? stopAt,
    bool Function()? isOnline,
  ) async {
    final stop = stopAt?.clamp(0, total);
    var done = 0;
    onProgress?.call(0, total);
    while (true) {
      if (stop != null && done >= stop) {
        throw const SyncBackendException(
          SyncErrorCode.network,
          'transfer interrupted',
        );
      }
      if (done >= total) return;
      await Future<void>.delayed(_pieceTime);
      cancel?.throwIfCancelled();
      if (isOnline != null && !isOnline()) {
        throw const SyncBackendException(
          SyncErrorCode.network,
          'offline during transfer',
        );
      }
      var next = done + _pieceBytes;
      if (next > total) next = total;
      if (stop != null && next > stop) next = stop;
      done = next;
      onProgress?.call(done, total);
    }
  }

  /// Returns the asset id of a path of this uid; permission denied otherwise.
  String _checkPath(String path) {
    final prefix = 'users/$uid/assets/';
    final assetId = path.startsWith(prefix)
        ? path.substring(prefix.length)
        : '';
    if (!_assetIdPattern.hasMatch(assetId)) {
      throw _denied('not an asset path of this user', path);
    }
    return assetId;
  }

  static SyncBackendException _denied(String why, String path) =>
      SyncBackendException(
        SyncErrorCode.permissionDenied,
        'storage rules: $why ($path)',
      );
}

final class _ObjectMeta {
  const _ObjectMeta(this.contentType, this.metadata);
  final String contentType;
  final Map<String, String> metadata;
}
