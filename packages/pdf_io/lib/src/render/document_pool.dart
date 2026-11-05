// lib/src/render/document_pool.dart — 06-pdf 4.7, 6.6.
//
// Foundation step B4 (T0): signatures only; the pool comes with PDF T7.
import 'package:note_core/note_core.dart' as core;

import '../engine/pdf_engine.dart';
import '../gateway/pdf_note_gateway.dart';
import '../tuning.dart';

abstract interface class PdfDocumentLease {
  core.AssetId get assetId;
  PdfEngineDocument get document;
  void release(); // idempotent
}

abstract interface class PdfDocumentPool {
  /// Opens (once, deduplicated) from gateway.readAssetBytes. Throws assetMissing / corrupt /
  /// passwordCancelled (needsPassword) / engineUnavailable. Failures are not cached (6.6).
  Future<PdfDocumentLease> acquire(core.AssetId assetId);

  /// Import hands over its already opened document (no second open).
  void adopt(core.AssetId assetId, PdfEngineDocument document);

  /// Ids whose bytes just arrived (gateway.bytesArrived, or ensureLocal() completed true).
  /// The pool has already dropped the failure memo for the id, so acquire() opens it again.
  Stream<core.AssetId> get assetArrived;

  /// P-2: requests the download through core.RemoteAssetFetcher (at most one request in flight
  /// per asset) and returns its shared progress stream. null when no fetcher is installed
  /// (before M4). Called by on-screen background handles only (6.7.7).
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId);
  int get openCount;
  Future<void> closeIdle();
  Future<void> dispose();
}

final class DefaultPdfDocumentPool implements PdfDocumentPool {
  /// [remoteAssets] = core.remoteAssetFetcherProvider (null until INFRA SyncModule, M4).
  DefaultPdfDocumentPool({
    required PdfEngine engine,
    required PdfNoteGateway gateway,
    core.RemoteAssetFetcher? remoteAssets,
    int maxIdleDocuments = PdfTuning.maxIdleDocuments,
    Duration idleTtl = PdfTuning.idleDocumentTtl,
  });

  static Never _t7(String member) =>
      throw UnimplementedError('DefaultPdfDocumentPool.$member (PDF T7)');

  @override
  Future<PdfDocumentLease> acquire(core.AssetId assetId) => _t7('acquire');

  @override
  void adopt(core.AssetId assetId, PdfEngineDocument document) => _t7('adopt');

  @override
  Stream<core.AssetId> get assetArrived => _t7('assetArrived');

  @override
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId) =>
      _t7('requestRemote');

  @override
  int get openCount => _t7('openCount');

  @override
  Future<void> closeIdle() => _t7('closeIdle');

  @override
  Future<void> dispose() => _t7('dispose');
}
