import 'package:cloud_firestore/cloud_firestore.dart';

import '../backend/blob_store.dart';
import '../backend/profile.dart';
import '../backend/remote_chunk.dart';
import '../backend/sync_backend.dart';
import '../common/server_cursor.dart';

final class FirebaseSyncBackend implements SyncBackend {
  FirebaseSyncBackend({
    required FirebaseFirestore firestore,
    required this.blobs,
    required this.uid,
    Duration timeout = const Duration(seconds: 30),
  });

  // implements SyncBackend (6.4.6)
  @override
  final String uid;

  @override
  final RemoteBlobStore blobs;

  @override
  Future<void> commitChunks(List<ChunkWrite> chunks) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  }) => throw UnimplementedError('SYNC T17');

  @override
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since}) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<int?> countChunks({ServerCursor? since}) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  }) => throw UnimplementedError('SYNC T17');

  @override
  Future<void> deleteChunks(List<String> ids) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<void> upsertProfile(UserProfile profile) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<ServerCursor> upsertDevice(DeviceInfo device) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<List<RemoteChunk>> getChunks(List<String> ids) =>
      throw UnimplementedError('SYNC T17');

  @override
  Future<void> close() => throw UnimplementedError('SYNC T17');
}
