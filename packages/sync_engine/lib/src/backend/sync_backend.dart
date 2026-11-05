import '../common/server_cursor.dart';
import 'blob_store.dart';
import 'profile.dart';
import 'remote_chunk.dart';

/// One signed-in user's remote store. All methods throw SyncBackendException.
abstract interface class SyncBackend {
  String get uid;

  /// Atomic: all chunks become visible together, with the same serverTime.
  /// Re-committing an existing id with identical content is allowed (lost ack).
  Future<void> commitChunks(List<ChunkWrite> chunks);

  /// Chunks with serverTime >= since (null = from the beginning), ordered by
  /// (serverTime, id), at most [limit].
  Future<ChunkPage> fetchChunks({
    ServerCursor? since,
    Object? pageToken,
    int limit = 50,
  });

  /// Live query for serverTime >= since. Emits batches of added or modified
  /// chunks (initial result first). Removed chunks are not reported. The stream
  /// ends with an error on disconnect.
  Stream<List<RemoteChunk>> watchChunks({ServerCursor? since});

  /// Approximate count for progress; null if unsupported.
  Future<int?> countChunks({ServerCursor? since});

  /// All chunks of one scope (compaction).
  Future<ChunkPage> fetchScope(
    String scope, {
    Object? pageToken,
    int limit = 50,
  });

  Future<void> deleteChunks(List<String> ids);

  Future<void> upsertProfile(UserProfile profile);

  /// Writes the device document (lastSeenAt = serverTimestamp) and returns that server
  /// time read back from the server: the clock-skew probe (6.2.4).
  Future<ServerCursor> upsertDevice(DeviceInfo device);

  /// Chunks by id; missing ids are omitted (held-chunk release, 6.2.5 K2).
  Future<List<RemoteChunk>> getChunks(List<String> ids);

  RemoteBlobStore get blobs;

  Future<void> close();
}
