// lib/src/assets/blob_store.dart (internal) — device-local byte storage outside SQLite
// (CORE 6.13): asset chunks and page thumbnails.
//
// Asset bytes are stored in chunks of [kAssetChunkBytes] under the keys
// '<assetId>/<chunkIndex, 6 digits>'. One key is one IndexedDB value, so a chunk
// is written atomically; the bytes of an asset are complete when every chunk key
// of its size is there (6.10.3 new remote rows, 6.13).
import 'dart:typed_data';

import '../assets/asset_store.dart';
import '../common/ids.dart';

/// Chunk size of asset bytes (4 MiB, 6.13).
const int kAssetChunkBytes = 4 * 1024 * 1024;

/// Key-value store of byte values (one IndexedDB object store).
abstract interface class BlobStore {
  Future<void> put(String key, Uint8List bytes);
  Future<Uint8List?> get(String key);

  /// (v2) The values of [keys] in their order, null for a missing key — one read (one
  /// IndexedDB transaction on the web; m5-7/02-core 6.10.4 search rects).
  Future<List<Uint8List?>> getMany(List<String> keys);
  Future<void> delete(String key);

  /// Deletes every key that starts with [prefix].
  Future<void> deletePrefix(String prefix);

  /// The keys that start with [prefix], in ascending order.
  Future<List<String>> keys(String prefix);
}

/// Page thumbnails by page id (one IndexedDB object store, 6.13).
abstract interface class ThumbnailStore {
  Future<void> put(PageThumbnail thumbnail);
  Future<PageThumbnail?> get(PageId pageId);
  Future<void> delete(Iterable<PageId> pageIds);

  /// Sum of the encoded image bytes of every stored thumbnail.
  Future<int> totalBytes();
}

/// Chunks of an asset of [size] bytes (0 for empty bytes).
int chunkCountFor(int size) =>
    size <= 0 ? 0 : (size + kAssetChunkBytes - 1) ~/ kAssetChunkBytes;

/// The blob key of chunk [index] of [assetId].
String chunkKey(AssetId assetId, int index) =>
    '$assetId/${index.toString().padLeft(6, '0')}';

/// The key prefix of every chunk of [assetId].
String chunkPrefix(AssetId assetId) => '$assetId/';

/// Writes [bytes] as the chunks of [assetId], first to last; returns the chunk
/// count. A failed chunk write throws at once (earlier chunks stay as orphans).
Future<int> writeChunks(
  BlobStore store,
  AssetId assetId,
  Uint8List bytes,
) async {
  final count = chunkCountFor(bytes.length);
  for (var i = 0; i < count; i++) {
    final start = i * kAssetChunkBytes;
    final end = start + kAssetChunkBytes < bytes.length
        ? start + kAssetChunkBytes
        : bytes.length;
    // A copy, not a view: IndexedDB clones a typed array with its whole buffer.
    await store.put(
      chunkKey(assetId, i),
      Uint8List.fromList(Uint8List.sublistView(bytes, start, end)),
    );
  }
  return count;
}

/// Whether every one of [count] chunks of [assetId] is stored.
Future<bool> hasAllChunks(BlobStore store, AssetId assetId, int count) async {
  final keys = (await store.keys(chunkPrefix(assetId))).toSet();
  for (var i = 0; i < count; i++) {
    if (!keys.contains(chunkKey(assetId, i))) return false;
  }
  return true;
}

/// The [count] chunks of [assetId] joined; null when a chunk is missing or the
/// joined length is not [size].
Future<Uint8List?> readChunks(
  BlobStore store,
  AssetId assetId,
  int count,
  int size,
) async {
  final out = Uint8List(size);
  var offset = 0;
  for (var i = 0; i < count; i++) {
    final chunk = await store.get(chunkKey(assetId, i));
    if (chunk == null || offset + chunk.length > size) return null;
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return offset == size ? out : null;
}
