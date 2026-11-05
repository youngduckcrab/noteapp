import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../common/server_cursor.dart';

enum ChunkKind { delta, snapshot }

/// What the engine writes. The server adds serverTime.
@immutable
final class ChunkWrite {
  const ChunkWrite({
    required this.id,
    required this.scope,
    required this.authorNodeId,
    required this.recordCount,
    required this.format,
    required this.kind,
    required this.maxHlc,
    required this.payload,
  });

  /// 6.4.5
  final String id;

  /// 'lib' or note id.
  final String scope;

  /// 16 hex.
  final String authorNodeId;

  /// 1..5000
  final int recordCount;

  /// ChunkCodec.formatVersion
  final int format;
  final ChunkKind kind;

  /// Newest record HLC text.
  final String maxHlc;

  /// <= SyncConfig.chunkHardLimitBytes
  final Uint8List payload;
}

/// What the engine reads.
@immutable
final class RemoteChunk {
  const RemoteChunk({
    required this.id,
    required this.scope,
    required this.authorNodeId,
    required this.recordCount,
    required this.format,
    required this.kind,
    required this.maxHlc,
    required this.payload,
    required this.serverTime,
  });
  final String id, scope, authorNodeId, maxHlc;
  final int recordCount, format;
  final ChunkKind kind;
  final Uint8List payload;
  final ServerCursor serverTime;
}

@immutable
final class ChunkPage {
  const ChunkPage(this.chunks, {this.nextPageToken});

  /// Ordered by (serverTime, id).
  final List<RemoteChunk> chunks;

  /// Opaque; null = no more.
  final Object? nextPageToken;
}
