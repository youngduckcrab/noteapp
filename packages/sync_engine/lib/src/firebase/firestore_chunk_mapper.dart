// Chunk documents `users/{uid}/changes/{chunkId}` (6.4.1, 6.4.2) ↔ ChunkWrite / RemoteChunk.
// `su` (serverTimestamp) is the cursor (6.6.2, ChunkFields.cursorOf).
import 'dart:typed_data';

// cloud_firestore 7.1.0 exports its own `Type` (pipeline expressions).
import 'package:cloud_firestore/cloud_firestore.dart' hide Type;

import '../backend/remote_chunk.dart';
import 'chunk_fields.dart';

abstract final class FirestoreChunkMapper {
  static const String collection = 'changes';

  /// Document fields for a write; 'su' = FieldValue.serverTimestamp().
  static Map<String, Object?> toFirestore(ChunkWrite chunk) => {
    ChunkFields.fmt: chunk.format,
    ChunkFields.scope: chunk.scope,
    ChunkFields.by: chunk.authorNodeId,
    ChunkFields.n: chunk.recordCount,
    ChunkFields.bytes: chunk.payload.length,
    ChunkFields.maxHlc: chunk.maxHlc,
    ChunkFields.kind: chunk.kind.name,
    ChunkFields.data: Blob(chunk.payload),
    ChunkFields.su: FieldValue.serverTimestamp(),
  };

  /// null when the document is malformed or 'su' is still pending (null).
  static RemoteChunk? fromFirestore(String id, Map<String, Object?> data) {
    final serverTime = data[ChunkFields.su];
    if (serverTime is! Timestamp) return null;
    final format = data[ChunkFields.fmt],
        count = data[ChunkFields.n],
        length = data[ChunkFields.bytes];
    final scopeValue = data[ChunkFields.scope],
        author = data[ChunkFields.by],
        hlc = data[ChunkFields.maxHlc];
    final kindValue = data[ChunkFields.kind];
    final payload = switch (data[ChunkFields.data]) {
      final Blob blob => blob.bytes,
      final Uint8List list => list,
      _ => null,
    };
    if (id.isEmpty ||
        format is! int ||
        count is! int ||
        count < 1 ||
        scopeValue is! String ||
        scopeValue.isEmpty ||
        author is! String ||
        author.isEmpty ||
        hlc is! String ||
        payload == null ||
        (length is int && length != payload.length)) {
      return null;
    }
    final chunkKind = switch (kindValue) {
      'delta' => ChunkKind.delta,
      'snapshot' => ChunkKind.snapshot,
      _ => null,
    };
    if (chunkKind == null) return null;
    return RemoteChunk(
      id: id,
      scope: scopeValue,
      authorNodeId: author,
      recordCount: count,
      format: format,
      kind: chunkKind,
      maxHlc: hlc,
      payload: payload,
      serverTime: ChunkFields.cursorOf(serverTime),
    );
  }
}
