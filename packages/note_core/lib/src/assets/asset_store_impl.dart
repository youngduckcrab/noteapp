// lib/src/assets/asset_store_impl.dart (internal) — AssetStore of the SQLite store
// (CORE 6.13, contract 7.2.11 v1.3).
//
// Metadata: the synced `assets` table, written through the write queue. Bytes: the
// blob store (4 MiB chunks), written BEFORE the metadata commit and outside the
// queue: a failed chunk write completes put / putDownloadedBytes with that error at
// once (no retry, metadata unchanged, earlier chunks stay as orphans — GC later).
// The metadata commit follows the write-Future rule (4.5 head): pending while the
// queue retries, complete after the successful commit, then bytesArrived.
import 'dart:async';

import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../model/asset.dart';
import '../storage/db/note_database.dart';
import '../storage/drift_note_store.dart';
import '../storage/row_mappers.dart';
import '../sync/outbox_types.dart';
import 'asset_store.dart';
import 'blob_store.dart';
import 'content_hasher.dart';
import 'image_import.dart';

final class AssetStoreImpl implements AssetStore {
  AssetStoreImpl(this.s, {required this.chunks, required this.thumbnailBytes});

  final DriftNoteStore s;

  /// Asset chunks (6.13); a test may inject a failing store.
  final BlobStore chunks;

  /// Stored thumbnail bytes, for usage().
  final Future<int> Function() thumbnailBytes;

  final StreamController<AssetId> _arrived = StreamController.broadcast();
  final Map<AssetId, Future<Asset>> _pendingPuts = {};
  final Set<Future<void>> _running = {};
  bool _closed = false;

  NoteDatabase get _db => s.db;

  @override
  Stream<AssetId> get bytesArrived => _arrived.stream;

  /// Runs [op] counted as in flight (close waits for it).
  Future<T> _track<T>(Future<T> Function() op) {
    if (_closed) return Future.error(StateError('The note store is closed'));
    final f = op();
    final done = f.then<void>((_) {}, onError: (Object _) {});
    _running.add(done);
    unawaited(done.whenComplete(() => _running.remove(done)));
    return f;
  }

  void _emitArrived(AssetId id) {
    if (!_arrived.isClosed) _arrived.add(id);
  }

  Future<AssetRow?> _row(AssetId id) =>
      (_db.select(_db.assets)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Whether the row says the bytes are here and every chunk key is stored.
  Future<bool> _complete(AssetRow row) async =>
      row.hasLocalBytes && await hasAllChunks(chunks, row.id, row.chunkCount);

  /// Local byte state of a new metadata row of [id] with [size] bytes (6.10.3
  /// remote rows): present when every chunk key is in the blob store.
  Future<({bool hasLocalBytes, int chunkCount})> localStateOf(
    AssetId id,
    int size,
  ) async {
    final count = chunkCountFor(size);
    return (
      hasLocalBytes: await hasAllChunks(chunks, id, count),
      chunkCount: count,
    );
  }

  @override
  Future<Asset> put(
    Uint8List bytes, {
    required AssetType type,
    required String mimeType,
    String? fileName,
  }) => _track(() async {
    checkLocalImageType(type, mimeType);
    final id = await sha256Hex(bytes);
    final pending = _pendingPuts[id];
    if (pending != null) return pending;
    final done = Completer<Asset>();
    _pendingPuts[id] = done.future;
    unawaited(done.future.then<void>((_) {}, onError: (Object _) {}));
    try {
      final asset = await _putNew(id, bytes, type, mimeType, fileName);
      done.complete(asset);
      return asset;
    } on Object catch (e, st) {
      done.completeError(e, st);
      rethrow;
    } finally {
      // The removed Future is done.future, already handled above.
      unawaited(_pendingPuts.remove(id));
    }
  });

  Future<Asset> _putNew(
    AssetId id,
    Uint8List bytes,
    AssetType type,
    String mimeType,
    String? fileName,
  ) async {
    // ② Same bytes already stored: the existing asset, no commit, no bytesArrived.
    final existing = await _row(id);
    if (existing != null && await _complete(existing)) return assetOf(existing);
    // ③ Bytes first (outside the queue, no retry), then the metadata commit.
    final count = await writeChunks(chunks, id, bytes);
    final asset = await s.queue.run((tx) async {
      final cur = await _row(id);
      if (cur != null) {
        // Metadata only (e.g. a remote asset): the local columns, no outbox.
        final next = assetOf(cur).copyWith(hasLocalBytes: true);
        await tx.putLocal(next, const {
          'hasLocalBytes',
        }, assetChunkCount: count);
        return next;
      }
      final created = Asset(
        id: id,
        ownerId: s.ownerId,
        type: type,
        mimeType: mimeType,
        size: bytes.length,
        fileName: fileName,
        createdAt: tx.now,
      );
      final versions = await tx.putLocal(
        created,
        const {kAllFields},
        isNew: true,
        assetChunkCount: count,
      );
      return created.copyWith(version: versions.max);
    });
    _emitArrived(id);
    return asset;
  }

  @override
  Future<Asset?> getAsset(AssetId id) async {
    final row = await _row(id);
    return row == null ? null : assetOf(row);
  }

  @override
  Future<Uint8List?> readBytes(AssetId id) async {
    final row = await _row(id);
    if (row == null || !row.hasLocalBytes) return null;
    return readChunks(chunks, id, row.chunkCount, row.size);
  }

  @override
  Future<bool> hasBytes(AssetId id) async {
    final row = await _row(id);
    return row != null && await _complete(row);
  }

  @override
  Future<void> putDownloadedBytes(AssetId id, Uint8List bytes) => _track(
    () async {
      if (await sha256Hex(bytes) != id) {
        throw AssetHashMismatchException('Downloaded bytes do not hash to $id');
      }
      final count = await writeChunks(chunks, id, bytes);
      // Through the queue even without a row: a queued remote write of this
      // asset's metadata commits first (and a later one finds the chunks).
      await s.queue.run((tx) async {
        final cur = await _row(id);
        if (cur == null || (cur.hasLocalBytes && cur.chunkCount == count)) {
          return;
        }
        await tx.putLocal(assetOf(cur).copyWith(hasLocalBytes: true), const {
          'hasLocalBytes',
        }, assetChunkCount: count);
      });
      _emitArrived(id);
    },
  );

  @override
  Future<List<Asset>> listAssets({bool? hasLocalBytes, bool? uploaded}) async {
    final a = _db.assets;
    final query = _db.select(a)
      ..where((t) => t.deletedAt.isNull() & t.ownerId.equals(s.ownerId));
    if (hasLocalBytes != null) {
      query.where((t) => t.hasLocalBytes.equals(hasLocalBytes));
    }
    if (uploaded != null) {
      query.where(
        (t) => uploaded ? t.storagePath.isNotNull() : t.storagePath.isNull(),
      );
    }
    query.orderBy([
      (t) => OrderingTerm.asc(t.createdAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
    return List.unmodifiable([for (final r in await query.get()) assetOf(r)]);
  }

  @override
  Future<void> markUploaded(AssetId id, String storagePath) =>
      s.queue.run((tx) async {
        final cur = await _row(id);
        if (cur == null) {
          throw EntityNotFoundException('Asset $id does not exist');
        }
        // Always {storagePath} in the outbox (SYNC sends the metadata next).
        await tx.putLocal(
          assetOf(cur).copyWith(storagePath: storagePath),
          const {'storagePath'},
        );
      });

  @override
  Future<AssetStorageUsage> usage() async {
    final a = _db.assets;
    final count = a.id.count();
    final total = a.size.sum();
    final all =
        await (_db.selectOnly(a)
              ..addColumns([count])
              ..where(a.deletedAt.isNull()))
            .getSingle();
    final local =
        await (_db.selectOnly(a)
              ..addColumns([total])
              ..where(a.deletedAt.isNull() & a.hasLocalBytes.equals(true)))
            .getSingle();
    // (v2.0, m5-7/02-core 6.15.1) the same rows as totalBytes, per type.
    final perType =
        await (_db.selectOnly(a)
              ..addColumns([a.type, total])
              ..where(a.deletedAt.isNull() & a.hasLocalBytes.equals(true))
              ..groupBy([a.type]))
            .get();
    final types = AssetType.values.asNameMap();
    final bytesByType = <AssetType, int>{
      for (final row in perType)
        if (types[row.read(a.type)] case final type?)
          if ((row.read(total) ?? 0) > 0) type: row.read(total)!,
    };
    return AssetStorageUsage(
      assetCount: all.read(count) ?? 0,
      totalBytes: local.read(total) ?? 0,
      thumbnailBytes: await thumbnailBytes(),
      bytesByType: Map.unmodifiable(bytesByType),
    );
  }

  /// Waits for running byte writes and closes bytesArrived (store close).
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([..._running]);
    await _arrived.close();
  }
}
