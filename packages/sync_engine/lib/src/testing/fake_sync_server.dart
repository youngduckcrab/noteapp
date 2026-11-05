import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/remote_chunk.dart';
import '../common/server_cursor.dart';
import '../model/records.dart';
import 'fake_blob_store.dart';
import 'fake_network.dart';
import 'fake_sync_backend.dart';

@immutable
final class StoredChunk {
  const StoredChunk(this.chunk, {required this.visibleAt});
  final RemoteChunk chunk;

  /// >= chunk.serverTime (late visibility).
  final ServerCursor visibleAt;
}

final class FakeSyncServer {
  FakeSyncServer({required Clock clock});

  /// Backend for one device; all calls go through [link] (latency, faults).
  FakeSyncBackend connect({
    required String uid,
    required FakeNetworkLink link,
  }) => throw UnimplementedError('SYNC T5');

  List<StoredChunk> chunksOf(String uid) => throw UnimplementedError('SYNC T5');

  FakeBlobStore blobsOf(String uid) => throw UnimplementedError('SYNC T5');

  /// uid → data, '$uid/$nodeId' → data.
  Map<String, Map<String, Object?>> profiles = {}, devices = {};

  /// Next commit's chunks become visible this much later than their serverTime.
  void delayVisibilityOfNextCommit(Duration delay) =>
      throw UnimplementedError('SYNC T5');

  /// Stores chunks as if a device had committed them, bypassing any engine (S14b(b):
  /// records whose HLC is far ahead of the server time).
  void commitRaw(String uid, List<ChunkWrite> chunks) =>
      throw UnimplementedError('SYNC T5');

  int writeCount(String uid) => throw UnimplementedError('SYNC T5');
  int readCount(String uid) => throw UnimplementedError('SYNC T5');
  int deleteCount(String uid) => throw UnimplementedError('SYNC T5');

  /// Decodes every chunk of [uid] and merges with FieldMerge (purges applied).
  Map<EntityRef, UpsertRecord> mergedState(String uid) =>
      throw UnimplementedError('SYNC T5');
}
