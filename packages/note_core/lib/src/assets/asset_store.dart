// lib/src/assets/asset_store.dart, thumbnail_cache.dart, page_thumbnail_renderer.dart,
// remote_asset.dart — contract 00-overview 7.2.11 (v1.3) / CORE 4.7.
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/asset.dart';
import '../model/page.dart';
import '../session/page_content.dart';

@immutable
final class AssetStorageUsage {
  const AssetStorageUsage({
    required this.assetCount,
    required this.totalBytes,
    required this.thumbnailBytes,
    this.bytesByType = const {},
  });

  final int assetCount, totalBytes, thumbnailBytes;

  /// (v2.0, 2nd-round contract 7.2.6 — C2-14) Σ Asset.size of rows with hasLocalBytes, per
  /// type (same rule as totalBytes, 1차 T13); a type with no bytes is absent (read as 0).
  /// == / hashCode include it.
  final Map<AssetType, int> bytesByType;

  @override
  bool operator ==(Object other) =>
      other is AssetStorageUsage &&
      other.assetCount == assetCount &&
      other.totalBytes == totalBytes &&
      other.thumbnailBytes == thumbnailBytes &&
      const MapEquality<AssetType, int>().equals(
        other.bytesByType,
        bytesByType,
      );

  @override
  int get hashCode => Object.hash(
    assetCount,
    totalBytes,
    thumbnailBytes,
    const MapEquality<AssetType, int>().hash(bytesByType),
  );
}

abstract interface class AssetStore {
  /// Hashes (SHA-256), stores bytes once, upserts metadata. Same bytes → same Asset (PDF C-5).
  /// (v1.2) put(): a failed byte-chunk write (blob store) completes the Future with that
  /// error at once, no retry, no metadata row (orphan chunks only). The metadata commit
  /// follows the write-Future rule of 7.2.9 (pending while the write queue retries).
  /// CORE: 4.5 head is that rule; 6.13 steps.
  Future<Asset> put(
    Uint8List bytes, {
    required AssetType type,
    required String mimeType,
    String? fileName,
  });
  Future<Asset?> getAsset(AssetId id);
  // null if bytes not on this device (PDF C-6)
  Future<Uint8List?> readBytes(AssetId id);
  Future<bool> hasBytes(AssetId id);

  /// SYNC download path. Throws AssetHashMismatchException.
  /// (v1.3) putDownloadedBytes(): a hash mismatch (AssetHashMismatchException) or a failed
  /// byte-chunk write completes with that error at once, no retry, metadata unchanged; its
  /// metadata commit (hasLocalBytes) and markUploaded() follow the write-Future rule of 7.2.9.
  Future<void> putDownloadedBytes(AssetId id, Uint8List bytes);

  /// hasLocalBytes: false = metadata only (e.g. a remote asset taken by applyRemote whose
  /// bytes are not in the blob store — SYNC's download list, 6.10.3).
  Future<List<Asset>> listAssets({bool? hasLocalBytes, bool? uploaded});

  /// SYNC after upload. Records {storagePath} in the outbox and publishes
  /// ChangeBatch(origin: local) (7.2.10 v1.1).
  Future<void> markUploaded(AssetId id, String storagePath);
  Future<AssetStorageUsage> usage();

  /// Emits the id after put() stored new bytes or putDownloadedBytes() succeeded.
  Stream<AssetId> get bytesArrived;
}

// lib/src/assets/thumbnail_cache.dart — device-local, never synced
@immutable
final class PageThumbnail {
  const PageThumbnail({
    required this.pageId,
    required this.contentRevision,
    required this.width,
    required this.height,
    required this.mimeType,
    required this.bytes,
  });

  final PageId pageId;
  final int contentRevision; // Page.contentRevision when rendered
  final int width, height; // pixels
  final String mimeType; // 'image/png' | 'image/jpeg' | 'image/webp'
  final Uint8List bytes;

  /// true when page.id != pageId or page.contentRevision != contentRevision.
  bool isStaleFor(Page page) =>
      page.id != pageId || page.contentRevision != contentRevision;

  @override
  String toString() =>
      'PageThumbnail($pageId rev $contentRevision, ${width}x$height $mimeType)';
}

abstract interface class ThumbnailCache {
  Future<PageThumbnail?> read(PageId pageId);

  /// Allowed for pages never opened in a session (PDF import cover, PDF C-7).
  Future<void> write(PageThumbnail thumbnail);
  Future<void> delete(PageId pageId);
  Stream<PageId> get updates; // pageId after each write/delete
}

// lib/src/assets/page_thumbnail_renderer.dart
/// Renders one page (paper + template / PDF background + committed strokes) to an encoded
/// image. Implemented by ink_engine (InkPageThumbnailRenderer), injected by the app shell.
abstract interface class PageThumbnailRenderer {
  /// PNG, long side ≤ maxSidePx; result.pageId == content.page.id and result.contentRevision
  /// == content.page.contentRevision. null when it cannot render now (e.g. PDF bytes missing).
  Future<PageThumbnail?> render(PageContent content, {int maxSidePx = 512});
}

// lib/src/assets/remote_asset.dart
enum RemoteAssetState {
  local,
  downloading,
  waiting,
  offline,
  failed,
  unavailable,
}

@immutable
final class RemoteAssetProgress {
  const RemoteAssetProgress(this.state, {this.received, this.total});
  final RemoteAssetState state;
  final int? received, total;

  @override
  bool operator ==(Object other) =>
      other is RemoteAssetProgress &&
      other.state == state &&
      other.received == received &&
      other.total == total;

  @override
  int get hashCode => Object.hash(state, received, total);
}

/// Download hook so PDF/EDITOR need not depend on sync_engine. Implemented by SYNC
/// (SyncRemoteAssetFetcher), injected by the app shell from M4. null before that.
abstract interface class RemoteAssetFetcher {
  Future<bool> ensureLocal(AssetId id); // true when bytes are local
  Stream<RemoteAssetProgress> watch(AssetId id);
}
