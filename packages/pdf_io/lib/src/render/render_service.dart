// lib/src/render/render_service.dart — 06-pdf 4.7, 6.7.
//
// Foundation step B4 (T0): value types are real (PdfRenderStats.zero + ==/hashCode, read by
// INFRA through pdfRenderStatsProvider); the render service comes with PDF T8.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../config.dart';
import '../errors.dart';
import '../tuning.dart';
import 'document_pool.dart';

@immutable
final class PdfBackgroundParams {
  const PdfBackgroundParams({
    required this.assetId,
    required this.pdfPageIndex,
    required this.pageSize,
    required this.deviceScale,
    this.paperColorArgb = 0xFFFFFFFF,
    this.visiblePageRect,
    this.isScaling = false,
    this.isThumbnail = false,
    this.pageId,
  });
  final core.AssetId assetId;
  final int pdfPageIndex;
  final ui.Size pageSize; // note page size in pt (box to fill)
  /// Device px per NOTE pt = ctx.deviceScale (viewScale × ancestorScale × DPR). Resolution /
  /// bucket choice ONLY — never layout (contract 7.2.16 v1.1). Per displayed PDF pt the
  /// render scale is deviceScale × PdfPageFit.k (6.7.1).
  final double deviceScale;
  final int paperColorArgb;
  final ui.Rect? visiblePageRect; // NOTE page pt (= ctx.visiblePageRect); null = whole page visible
  final bool isScaling; // pinch in progress → no new resolution requests
  final bool isThumbnail; // = ink.PageBackgroundContext.isThumbnail (page panel / thumbnails)
  final String? pageId; // = ctx.pageId: search highlight lookup (rectsFor) + diagnostics; null → no highlights

  /// isThumbnail || deviceScale * longest side <= PdfTuning.thumbnailModeMaxLongSidePx.
  bool get usesThumbnailMode =>
      isThumbnail ||
      deviceScale * math.max(pageSize.width, pageSize.height) <=
          PdfTuning.thumbnailModeMaxLongSidePx;
}

enum PdfRenderStatus {
  loading, // no image yet
  ready, // base image (preview or thumbnail) present
  assetMissing, // bytes not on this device; remote shows why (null = no fetcher / unavailable)
  downloading, // core.RemoteAssetFetcher is downloading / waiting for the source device (6.7.7)
  needsPassword, // stored asset needs a password (6.4)
  failed,
}

@immutable
final class PdfPlacedImage {
  const PdfPlacedImage({
    required this.image,
    required this.srcRect,
    required this.pageRect,
  });
  final ui.Image image; // owned by the cache — never dispose
  final ui.Rect srcRect; // pixels (overlap border excluded)
  /// NOTE page pt (already placed with PdfPageFit, 6.5.1)
  final ui.Rect pageRect;
}

@immutable
final class PdfRenderSnapshot {
  const PdfRenderSnapshot({
    required this.status,
    this.base,
    this.tiles = const [],
    this.remote,
    this.error,
  });
  static const PdfRenderSnapshot loading = PdfRenderSnapshot(
    status: PdfRenderStatus.loading,
  );
  final PdfRenderStatus status;
  final PdfPlacedImage? base; // preview or thumbnail covering the whole page
  final List<PdfPlacedImage> tiles; // older bucket first, then current bucket
  /// Latest progress of core.RemoteAssetFetcher.watch (assetMissing / downloading only).
  final core.RemoteAssetProgress? remote;
  final PdfIoException? error;
}

/// Developer overlay values (INFRA formatPdfRenderStats reads these fields, 01-infra 4.5.9).
/// Real from B4 (T0): const zero + ==/hashCode (the B4 pdfRenderStatsProvider body is
/// ValueNotifier(PdfRenderStats.zero), contract 7.6 B4 v1.2 — 4.12).
@immutable
final class PdfRenderStats {
  const PdfRenderStats({
    required this.previewBytes,
    required this.tileBytes,
    required this.thumbnailBytes,
    required this.liveImages,
    required this.queued,
    required this.inflight,
    required this.rendered,
    required this.cancelled,
    required this.lastRenderMs,
    required this.p95RenderMs,
    required this.openDocuments,
    required this.overBudgetBytes,
  });
  static const PdfRenderStats zero = PdfRenderStats(
    previewBytes: 0,
    tileBytes: 0,
    thumbnailBytes: 0,
    liveImages: 0,
    queued: 0,
    inflight: 0,
    rendered: 0,
    cancelled: 0,
    lastRenderMs: 0,
    p95RenderMs: 0,
    openDocuments: 0,
    overBudgetBytes: 0,
  );
  final int previewBytes,
      tileBytes,
      thumbnailBytes,
      liveImages,
      queued,
      inflight;
  final int rendered, cancelled, openDocuments;
  final int overBudgetBytes; // > 0 when in-use images exceed the budget
  final double lastRenderMs, p95RenderMs;

  /// All twelve fields (contract 7.4.4): statsListenable is a ValueNotifier, which skips
  /// notifying when the new value == the old one.
  @override
  bool operator ==(Object other) =>
      other is PdfRenderStats &&
      other.previewBytes == previewBytes &&
      other.tileBytes == tileBytes &&
      other.thumbnailBytes == thumbnailBytes &&
      other.liveImages == liveImages &&
      other.queued == queued &&
      other.inflight == inflight &&
      other.rendered == rendered &&
      other.cancelled == cancelled &&
      other.lastRenderMs == lastRenderMs &&
      other.p95RenderMs == p95RenderMs &&
      other.openDocuments == openDocuments &&
      other.overBudgetBytes == overBudgetBytes;

  @override
  int get hashCode => Object.hash(
    previewBytes,
    tileBytes,
    thumbnailBytes,
    liveImages,
    queued,
    inflight,
    rendered,
    cancelled,
    lastRenderMs,
    p95RenderMs,
    openDocuments,
    overBudgetBytes,
  );

  @override
  String toString() =>
      'PdfRenderStats(previewBytes: $previewBytes, tileBytes: $tileBytes, '
      'thumbnailBytes: $thumbnailBytes, liveImages: $liveImages, '
      'queued: $queued, inflight: $inflight, rendered: $rendered, '
      'cancelled: $cancelled, lastRenderMs: $lastRenderMs, '
      'p95RenderMs: $p95RenderMs, openDocuments: $openDocuments, '
      'overBudgetBytes: $overBudgetBytes)';
}

/// One mounted page background. Notifies when [snapshot] changes.
abstract interface class PdfPageRenderHandle implements Listenable {
  PdfBackgroundParams get params;
  PdfRenderSnapshot get snapshot;
  void update(PdfBackgroundParams params);
  void dispose(); // cancels requests, releases tiles, stops remote watch
}

abstract interface class PdfPageRenderer {
  PdfPageRenderHandle attach(PdfBackgroundParams params);

  /// Small standalone render (cover thumbnails, still images). Caller owns the image.
  /// null when the bytes are missing / a password is needed / rendering failed.
  /// Never requests a remote download (6.9).
  Future<ui.Image?> renderThumbnail({
    required core.AssetId assetId,
    required int pdfPageIndex,
    required int longSidePx,
    int backgroundArgb = 0xFFFFFFFF,
  });
  PdfRenderStats get stats;
  ValueListenable<PdfRenderStats> get statsListenable;

  /// Drops every image not in use (tab hidden, memory pressure).
  void trimMemory();
  Future<void> dispose();
}

final class PdfRenderService implements PdfPageRenderer {
  /// [trimOnAppHidden]: registers an AppLifecycleListener(onHide: trimMemory) itself — no app
  /// shell wiring needed (6.7.4). Tests without a binding pass false.
  PdfRenderService({
    required PdfDocumentPool pool,
    required PdfRenderBudget budget,
    int maxInflight = PdfTuning.maxInflightRenders,
    bool trimOnAppHidden = true,
  });

  static Never _t8(String member) =>
      throw UnimplementedError('PdfRenderService.$member (PDF T8)');

  @override
  PdfPageRenderHandle attach(PdfBackgroundParams params) => _t8('attach');

  @override
  Future<ui.Image?> renderThumbnail({
    required core.AssetId assetId,
    required int pdfPageIndex,
    required int longSidePx,
    int backgroundArgb = 0xFFFFFFFF,
  }) => _t8('renderThumbnail');

  @override
  PdfRenderStats get stats => _t8('stats');

  @override
  ValueListenable<PdfRenderStats> get statsListenable => _t8('statsListenable');

  @override
  void trimMemory() => _t8('trimMemory');

  @override
  Future<void> dispose() => _t8('dispose');
}
