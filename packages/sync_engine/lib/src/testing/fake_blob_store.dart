import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/blob_store.dart';
import '../common/cancel_token.dart';

/// Via FakeSyncServer.blobsOf.
final class FakeBlobStore implements RemoteBlobStore {
  @internal
  FakeBlobStore.internal();

  Map<String, Uint8List> get objects => throw UnimplementedError('SYNC T5');
  int uploadCount = 0, downloadCount = 0;

  @override
  String pathFor(AssetId id) => throw UnimplementedError('SYNC T5');

  @override
  Future<RemoteBlobInfo?> stat(String path) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
  }) => throw UnimplementedError('SYNC T5');

  @override
  Future<Uint8List> download(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
  }) => throw UnimplementedError('SYNC T5');
}
