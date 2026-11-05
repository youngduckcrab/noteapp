import 'package:meta/meta.dart';

import '../backend/blob_store.dart';
import '../backend/profile.dart';
import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../common/server_cursor.dart';

/// Via FakeSyncServer.connect.
final class FakeSyncBackend implements SyncBackend {
  @internal
  FakeSyncBackend.internal();

  @override
  String get uid => throw UnimplementedError('SYNC T5');

  @override
  RemoteBlobStore get blobs => throw UnimplementedError('SYNC T5');

  @override
  Future<void> commitChunks(List<ChunkWrite> chunks) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  }) => throw UnimplementedError('SYNC T5');

  @override
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since}) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<int?> countChunks({ServerCursor? since}) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  }) => throw UnimplementedError('SYNC T5');

  @override
  Future<void> deleteChunks(List<String> ids) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<void> upsertProfile(UserProfile profile) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<ServerCursor> upsertDevice(DeviceInfo device) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<List<RemoteChunk>> getChunks(List<String> ids) =>
      throw UnimplementedError('SYNC T5');

  @override
  Future<void> close() => throw UnimplementedError('SYNC T5');
}
