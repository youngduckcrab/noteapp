// The Cloud Storage adapter of RemoteBlobStore (6.9): objects at users/{uid}/assets/{sha256}
// with the content type and custom metadata the storage rules check (sha256, 6.14). Errors
// map with mapFirebaseError; a cancelled token cancels the running task and throws
// SyncBackendException(cancelled).
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../common/cancel_token.dart';
import '../common/errors.dart';
import 'firebase_error_mapper.dart';

final class FirebaseBlobStore implements RemoteBlobStore {
  FirebaseBlobStore({required this._storage, required this._uid});

  final FirebaseStorage _storage;
  final String _uid;

  /// Metadata reads (stat); transfers are bounded by the SDK's retry times instead.
  static const Duration _statTimeout = Duration(seconds: 30);

  static const SyncBackendException _cancelled = SyncBackendException(
    SyncErrorCode.cancelled,
    'cancelled',
  );

  @override
  String pathFor(AssetId id) => 'users/$_uid/assets/$id';

  @override
  Future<RemoteBlobInfo?> stat(String path) async {
    final FullMetadata meta;
    try {
      meta = await _storage.ref(path).getMetadata().timeout(_statTimeout);
    } on Object catch (e, s) {
      final error = mapFirebaseError(e, stackTrace: s);
      if (error.code == SyncErrorCode.notFound) return null;
      throw error;
    }
    return RemoteBlobInfo(
      path: path,
      size: meta.size ?? 0,
      sha256: meta.customMetadata?['sha256'],
      contentType: meta.contentType,
    );
  }

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final UploadTask task;
    try {
      task = _storage
          .ref(path)
          .putData(
            bytes,
            SettableMetadata(
              contentType: contentType,
              customMetadata: metadata,
            ),
          );
    } on Object catch (e, s) {
      throw mapFirebaseError(e, stackTrace: s);
    }
    final progress = task.snapshotEvents.listen(
      (snapshot) => onProgress?.call(
        snapshot.bytesTransferred,
        snapshot.totalBytes > 0 ? snapshot.totalBytes : bytes.length,
      ),
      // The task future reports the failure.
      onError: (Object _) {},
    );
    unawaited(
      cancel?.whenCancelled
          .then((_) => task.cancel())
          .catchError((Object _) => false),
    );
    try {
      await task;
    } on Object catch (e, s) {
      if (cancel?.isCancelled ?? false) throw _cancelled;
      throw mapFirebaseError(e, stackTrace: s);
    } finally {
      unawaited(progress.cancel());
    }
    cancel?.throwIfCancelled();
    onProgress?.call(bytes.length, bytes.length);
  }

  /// getData has no progress events: progress is reported at the start (0 of the object
  /// size) and at the end.
  @override
  Future<Uint8List> download(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
  }) async {
    cancel?.throwIfCancelled();
    final info = await stat(path);
    cancel?.throwIfCancelled();
    if (info == null) {
      throw SyncBackendException(SyncErrorCode.notFound, 'no object $path');
    }
    if (info.size > maxBytes) {
      throw SyncBackendException(
        SyncErrorCode.invalidArgument,
        '$path has ${info.size} B, more than $maxBytes B',
      );
    }
    onProgress?.call(0, info.size);
    final read = _read(path, maxBytes);
    // Future.any handles a late error of the future that lost.
    final data = cancel == null
        ? await read
        : await Future.any([
            read,
            cancel.whenCancelled.then<Uint8List?>((_) => throw _cancelled),
          ]);
    if (data == null) {
      throw SyncBackendException(SyncErrorCode.notFound, 'no data at $path');
    }
    onProgress?.call(data.length, info.size);
    return data;
  }

  Future<Uint8List?> _read(String path, int maxBytes) async {
    try {
      return await _storage.ref(path).getData(maxBytes);
    } on Object catch (e, s) {
      throw mapFirebaseError(e, stackTrace: s);
    }
  }
}
