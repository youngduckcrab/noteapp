// Internal (not exported). Splits records into change chunks and commits (6.4.3).
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../backend/remote_chunk.dart';
import '../config.dart';
import '../model/records.dart';
import 'chunk_codec.dart';
import 'chunk_id.dart';

/// One record to send and the scope it goes to (SyncScopes, 6.4.3 step 1). [tag] is the
/// caller's handle (e.g. the outbox entry) and comes back with the chunk it landed in.
@immutable
final class PackItem<T> {
  const PackItem(this.record, {required this.scope, required this.tag});
  final SyncRecord record;
  final String scope;
  final T tag;
}

/// A chunk ready to commit and the items it carries, in payload order.
@immutable
final class PackedChunk<T> {
  const PackedChunk(this.write, this.items);
  final ChunkWrite write;
  final List<PackItem<T>> items;
}

/// Chunks committed together (one atomic SyncBackend.commitChunks call).
@immutable
final class PackedCommit<T> {
  const PackedCommit(this.chunks);
  final List<PackedChunk<T>> chunks;
  int get bytes => chunks.fold(0, (sum, c) => sum + c.write.payload.length);
}

@immutable
final class PackResult<T> {
  const PackResult(this.commits, this.tooLarge);
  final List<PackedCommit<T>> commits;

  /// Items whose single-record chunk would exceed SyncConfig.chunkHardLimitBytes
  /// (quarantined as entityTooLarge, kept local only — 6.4.3 step 4).
  final List<PackItem<T>> tooLarge;
}

final class ChunkPacker {
  ChunkPacker({required this.config, required this.authorNodeId});

  final SyncConfig config;
  final String authorNodeId;

  /// Kind order inside a scope (6.4.3 step 2; 2nd round: contract 7.2.8), then id, then
  /// upsert before purge.
  static const List<EntityKind> kindOrder = [
    EntityKind.folder,
    EntityKind.note,
    EntityKind.page,
    EntityKind.penPreset,
    EntityKind.setting,
    EntityKind.asset,
    EntityKind.recording,
    EntityKind.stroke,
    EntityKind.pageObject,
    EntityKind.handwriting,
  ];

  static int compareRecords(SyncRecord a, SyncRecord b) {
    final k = kindOrder
        .indexOf(a.ref.kind)
        .compareTo(kindOrder.indexOf(b.ref.kind));
    if (k != 0) return k;
    final i = a.ref.id.compareTo(b.ref.id);
    if (i != 0) return i;
    return (a is UpsertRecord ? 0 : 1).compareTo(b is UpsertRecord ? 0 : 1);
  }

  PackResult<T> pack<T>(
    List<PackItem<T>> items, {
    ChunkKind kind = ChunkKind.delta,
  }) {
    final byScope = <String, List<(PackItem<T>, Uint8List)>>{};
    final tooLarge = <PackItem<T>>[];
    for (final item in items) {
      final bytes = ChunkCodec.encodeRecord(item.record);
      if (ChunkCodec.payloadLength(1, bytes.length) >
          config.chunkHardLimitBytes) {
        tooLarge.add(item);
        continue;
      }
      (byScope[item.scope] ??= []).add((item, bytes));
    }
    final chunks = <PackedChunk<T>>[];
    for (final scope in byScope.keys.toList()..sort()) {
      final list = byScope[scope]!
        ..sort((a, b) => compareRecords(a.$1.record, b.$1.record));
      var current = <(PackItem<T>, Uint8List)>[];
      var currentBytes = 0;
      for (final entry in list) {
        final grown = ChunkCodec.payloadLength(
          current.length + 1,
          currentBytes + entry.$2.length,
        );
        if (current.isNotEmpty &&
            (grown > config.chunkSoftLimitBytes ||
                current.length + 1 > config.maxRecordsPerChunk)) {
          chunks.add(_chunk(scope, current, kind));
          current = [];
          currentBytes = 0;
        }
        current.add(entry);
        currentBytes += entry.$2.length;
      }
      if (current.isNotEmpty) chunks.add(_chunk(scope, current, kind));
    }
    final commits = <PackedCommit<T>>[];
    var batch = <PackedChunk<T>>[];
    var batchBytes = 0;
    for (final c in chunks) {
      final size = c.write.payload.length;
      if (batch.isNotEmpty &&
          (batch.length + 1 > config.maxChunksPerCommit ||
              batchBytes + size > config.maxBytesPerCommit)) {
        commits.add(PackedCommit(List.unmodifiable(batch)));
        batch = [];
        batchBytes = 0;
      }
      batch.add(c);
      batchBytes += size;
    }
    if (batch.isNotEmpty) commits.add(PackedCommit(List.unmodifiable(batch)));
    return PackResult(List.unmodifiable(commits), List.unmodifiable(tooLarge));
  }

  PackedChunk<T> _chunk<T>(
    String scope,
    List<(PackItem<T>, Uint8List)> entries,
    ChunkKind kind,
  ) {
    final payload = ChunkCodec.assemble([for (final e in entries) e.$2]);
    final records = [for (final e in entries) e.$1.record];
    return PackedChunk(
      ChunkWrite(
        id: chunkIdOf(authorNodeId, payload),
        scope: scope,
        authorNodeId: authorNodeId,
        recordCount: entries.length,
        format: ChunkCodec.formatVersion,
        kind: kind,
        maxHlc: ChunkCodec.maxHlcOf(records).toString(),
        payload: payload,
      ),
      List.unmodifiable([for (final e in entries) e.$1]),
    );
  }
}
