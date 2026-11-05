import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../common/cancel_token.dart';

final class FirebaseBlobStore implements RemoteBlobStore {
  FirebaseBlobStore({required FirebaseStorage storage, required String uid});

  @override
  String pathFor(AssetId id) => throw UnimplementedError('SYNC T17');

  @override
  Future<RemoteBlobInfo?> stat(String path) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
  }) => throw UnimplementedError('SYNC T17');

  @override
  Future<Uint8List> download(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
  }) => throw UnimplementedError('SYNC T17');
}
