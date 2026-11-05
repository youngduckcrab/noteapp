import '../backend/remote_chunk.dart';

abstract final class FirestoreChunkMapper {
  static const String collection = 'changes';

  /// Document fields for a write; 'su' = FieldValue.serverTimestamp().
  static Map<String, Object?> toFirestore(ChunkWrite chunk) =>
      throw UnimplementedError('SYNC T17');

  /// null when the document is malformed or 'su' is still pending (null).
  static RemoteChunk? fromFirestore(String id, Map<String, Object?> data) =>
      throw UnimplementedError('SYNC T17');
}
