import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../common/cancel_token.dart';

@immutable
final class RemoteBlobInfo {
  const RemoteBlobInfo({
    required this.path,
    required this.size,
    this.sha256,
    this.contentType,
  });
  final String path;
  final int size;

  /// Custom metadata.
  final String? sha256;
  final String? contentType;
}

abstract interface class RemoteBlobStore {
  /// 'users/{uid}/assets/{assetId}'
  String pathFor(AssetId id);

  /// null if missing.
  Future<RemoteBlobInfo?> stat(String path);

  Future<void> upload(
    String path,
    Uint8List bytes, {
    required String contentType,
    required Map<String, String> metadata,
    void Function(int sent, int total)? onProgress,
    SyncCancelToken? cancel,
  });

  /// Throws SyncBackendException(invalidArgument) if the object is larger than [maxBytes].
  Future<Uint8List> download(
    String path, {
    required int maxBytes,
    void Function(int received, int total)? onProgress,
    SyncCancelToken? cancel,
  });
}
