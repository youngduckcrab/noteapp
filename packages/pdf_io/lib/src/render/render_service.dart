// lib/src/render/render_service.dart — 06-pdf 4.7, 6.7.
//
// Value types (PdfRenderStats.zero + ==/hashCode are real from B4) and PdfRenderService
// (PDF T8): one render queue (render_scheduler.dart), one image cache with byte budgets
// (render_cache.dart) and one handle per mounted page background that decides what to draw
// (tile_math.dart, 6.7.2), keeps its images referenced while they are in its snapshot and
// releases them a frame after they leave it (6.7.5). Remote originals (6.7.7) come with T9.
//
// PdfRenderService keeps the 4.7 parameter list word for word (plain named parameters
// assigned to private fields), hence:
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:note_core/note_core.dart' as core;

import '../common/error_report.dart';
import '../config.dart';
import '../engine/page_info.dart';
import '../errors.dart';
import '../tuning.dart';
import 'document_pool.dart';
import 'render_cache.dart';
import 'render_scheduler.dart';
import 'tile_math.dart';

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
  ///
  /// The listener is registered on the first attach / renderThumbnail (nothing is cached
  /// before), so building the service — e.g. reading pdfRenderStatsProvider — needs no
  /// binding.
  PdfRenderService({
    required PdfDocumentPool pool,
    required PdfRenderBudget budget,
    int maxInflight = PdfTuning.maxInflightRenders,
    bool trimOnAppHidden = true,
  }) : _pool = pool,
       _trimOnAppHidden = trimOnAppHidden {
    _cache = PdfRenderCache(budget: budget, onChanged: _statsChanged);
    _scheduler = PdfRenderScheduler(
      maxInflight: maxInflight,
      onChanged: _statsChanged,
    );
  }

  final PdfDocumentPool _pool;
  final bool _trimOnAppHidden;
  late final PdfRenderCache _cache;
  late final PdfRenderScheduler _scheduler;
  final ValueNotifier<PdfRenderStats> _stats = ValueNotifier(
    PdfRenderStats.zero,
  );
  final Set<_PageHandle> _handles = {};
  AppLifecycleListener? _lifecycle;
  bool _statsScheduled = false;
  bool _disposed = false;

  final List<VoidCallback> _afterFrame = [];
  bool _afterFrameScheduled = false;

  @override
  PdfPageRenderHandle attach(PdfBackgroundParams params) {
    if (_disposed) throw StateError('PdfRenderService is disposed');
    _ensureLifecycleListener();
    final handle = _PageHandle(this, params);
    _handles.add(handle);
    return handle;
  }

  @override
  Future<ui.Image?> renderThumbnail({
    required core.AssetId assetId,
    required int pdfPageIndex,
    required int longSidePx,
    int backgroundArgb = 0xFFFFFFFF,
  }) async {
    if (_disposed) return null;
    PdfDocumentLease? lease;
    try {
      _ensureLifecycleListener();
      final acquired = lease = await _pool.acquire(assetId);
      final page = _pageOf(acquired, pdfPageIndex);
      final request = PdfRenderRequest(
        pageIndex: pdfPageIndex,
        scale: scaleForLongSide(longSidePx, ui.Size(page.width, page.height)),
        backgroundArgb: backgroundArgb,
        priority: PdfRenderClass.thumbnail.priorityHint,
      );
      final job = _scheduler.submit(
        PdfRenderClass.thumbnail,
        (token) => acquired.document.render(request, cancelToken: token),
      );
      return await job.result;
    } on PdfIoException catch (e, s) {
      // A missing original / a needed password is a normal "cannot render now" (6.13).
      if (e.code != PdfErrorCode.assetMissing &&
          e.code != PdfErrorCode.passwordCancelled) {
        reportPdfError(e, s, 'pdf renderThumbnail $assetId #$pdfPageIndex');
      }
      return null;
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf renderThumbnail $assetId #$pdfPageIndex');
      return null;
    } finally {
      lease?.release();
    }
  }

  @override
  PdfRenderStats get stats => _computeStats();

  @override
  ValueListenable<PdfRenderStats> get statsListenable => _stats;

  @override
  void trimMemory() => _cache.trimMemory();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lifecycle?.dispose();
    _lifecycle = null;
    for (final handle in _handles.toList()) {
      handle._shutdown();
    }
    _handles.clear();
    _runAfterFrame();
    _scheduler.dispose();
    _cache.dispose();
    _stats.dispose();
  }

  void _ensureLifecycleListener() {
    if (!_trimOnAppHidden || _lifecycle != null || _disposed) return;
    _lifecycle = AppLifecycleListener(onHide: trimMemory);
  }

  PdfRenderStats _computeStats() => PdfRenderStats(
    previewBytes: _cache.bytesOf(PdfRenderKind.preview),
    tileBytes: _cache.bytesOf(PdfRenderKind.tile),
    thumbnailBytes: _cache.bytesOf(PdfRenderKind.thumbnail),
    liveImages: _cache.liveImages,
    queued: _scheduler.queued,
    inflight: _scheduler.inflight,
    rendered: _scheduler.rendered,
    cancelled: _scheduler.cancelled,
    lastRenderMs: _scheduler.lastRenderMs,
    p95RenderMs: _scheduler.p95RenderMs,
    openDocuments: _pool.openCount,
    overBudgetBytes: _cache.overBudgetBytes,
  );

  /// Cache / queue changes are coalesced into one statsListenable update per microtask:
  /// a listener never runs inside a widget build that attached or updated a handle, and
  /// an equal value notifies nobody (PdfRenderStats ==, ValueNotifier).
  void _statsChanged() {
    if (_statsScheduled || _disposed) return;
    _statsScheduled = true;
    scheduleMicrotask(() {
      _statsScheduled = false;
      if (!_disposed) _stats.value = _computeStats();
    });
  }

  /// 6.7.5: images that left a snapshot are released after the next frame (the frame being
  /// drawn may still paint them).
  void _releaseAfterFrame(VoidCallback release) {
    if (_disposed) {
      release();
      return;
    }
    _afterFrame.add(release);
    if (_afterFrameScheduled) return;
    _afterFrameScheduled = true;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => _runAfterFrame());
    binding.ensureVisualUpdate();
  }

  void _runAfterFrame() {
    _afterFrameScheduled = false;
    final releases = List.of(_afterFrame);
    _afterFrame.clear();
    for (final release in releases) {
      release();
    }
  }

  static PdfPageInfo _pageOf(PdfDocumentLease lease, int pageIndex) {
    final pages = lease.document.info.pages;
    if (pageIndex < 0 || pageIndex >= pages.length) {
      throw PdfIoException(
        PdfErrorCode.corrupt,
        detail:
            'page index $pageIndex out of range (${pages.length} pages) '
            'in ${lease.assetId}',
      );
    }
    return pages[pageIndex];
  }
}

/// One image a handle draws: the base (preview / thumbnail) or one tile.
final class _Slot {
  _Slot(
    this.key, {
    required this.renderClass,
    required this.request,
    required this.pageRect,
    this.srcRect,
  });

  final PdfRenderKey key;
  PdfRenderClass renderClass;
  final PdfRenderRequest request;

  /// NOTE page pt.
  ui.Rect pageRect;

  /// Pixels of the image to draw; null = the whole image.
  final ui.Rect? srcRect;

  PdfCacheLease? image;
  PdfRenderJob? job;
  bool retried = false;
  bool failed = false;

  bool get settled => image != null || failed;

  PdfPlacedImage? placed() {
    final lease = image;
    if (lease == null) return null;
    final img = lease.image;
    return PdfPlacedImage(
      image: img,
      srcRect:
          srcRect ??
          ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      pageRect: pageRect,
    );
  }
}

/// One mounted page background (6.7.2–6.7.6).
final class _PageHandle extends ChangeNotifier implements PdfPageRenderHandle {
  _PageHandle(this._service, this._params) : _quiet = _params.isScaling {
    _acquire();
  }

  final PdfRenderService _service;
  PdfBackgroundParams _params;
  PdfRenderSnapshot _snapshot = PdfRenderSnapshot.loading;
  bool _disposed = false;

  // document
  PdfDocumentLease? _lease;
  PdfPageInfo? _page;
  int _generation = 0;
  bool _openRetried = false;
  Timer? _retryTimer;

  /// Set when opening failed for good (assetMissing / needsPassword / failed).
  PdfRenderStatus? _openStatus;
  PdfIoException? _error;

  // images
  _Slot? _base;

  /// The base shown until [_base] arrives (bucket / mode change).
  _Slot? _previousBase;
  final Map<(int, int), _Slot> _tiles = {};
  final Set<(int, int)> _visibleTiles = {};
  double? _tileBucket;

  /// Older-bucket tiles kept under the new ones until those cover the visible area.
  final List<_Slot> _oldTiles = [];

  // pinch (6.7.2 step 5): no new requests while scaling and until settleDelay passes
  // without a change after it.
  bool _quiet;
  Timer? _settleTimer;

  @override
  PdfBackgroundParams get params => _params;

  @override
  PdfRenderSnapshot get snapshot => _snapshot;

  PdfRenderCache get _cache => _service._cache;

  /// No notification: the caller (didUpdateWidget) rebuilds and reads [snapshot] anyway.
  @override
  void update(PdfBackgroundParams params) {
    if (_disposed) return;
    final old = _params;
    _params = params;
    if (old.assetId != params.assetId ||
        old.pdfPageIndex != params.pdfPageIndex) {
      _restart();
      return;
    }
    if (_sameParams(old, params)) return;
    if (params.isScaling) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _quiet = true;
      _replan();
    } else if (_quiet) {
      _settleTimer?.cancel();
      _settleTimer = Timer(PdfTuning.settleDelay, _settled);
      _replan();
    } else {
      _replan();
    }
    _rebuildSnapshot();
  }

  void _settled() {
    _settleTimer = null;
    if (_disposed) return;
    _quiet = false;
    _replan();
    _rebuildSnapshot();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _shutdown();
    _service._handles.remove(this);
    super.dispose();
  }

  /// dispose() without the ChangeNotifier part (also used by PdfRenderService.dispose).
  /// 6.7.6: queued / running renders are cancelled, tiles are released at once (and
  /// disposed when no other handle uses them), the preview stays in the LRU.
  void _shutdown() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _retryTimer?.cancel();
    _settleTimer?.cancel();
    for (final slot in [..._tiles.values, ..._oldTiles]) {
      slot.job?.cancel();
      slot.image?.release(dropIfUnused: true);
    }
    _tiles.clear();
    _oldTiles.clear();
    for (final slot in [_base, _previousBase]) {
      slot?.job?.cancel();
      slot?.image?.release();
    }
    _base = _previousBase = null;
    _lease?.release();
    _lease = null;
    _snapshot = PdfRenderSnapshot.loading;
  }

  /// Another asset / page in the same handle: start over.
  void _restart() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _quiet = _params.isScaling;
    for (final slot in [..._tiles.values, ..._oldTiles]) {
      _drop(slot);
    }
    _tiles.clear();
    _visibleTiles.clear();
    _oldTiles.clear();
    _tileBucket = null;
    for (final slot in [_base, _previousBase]) {
      if (slot != null) _drop(slot);
    }
    _base = _previousBase = null;
    _lease?.release();
    _lease = null;
    _page = null;
    _openRetried = false;
    _openStatus = null;
    _error = null;
    _snapshot = PdfRenderSnapshot.loading;
    _acquire();
  }

  void _acquire() {
    final generation = ++_generation;
    final assetId = _params.assetId;
    _service._pool
        .acquire(assetId)
        .then(
          (lease) {
            if (_disposed || generation != _generation) {
              lease.release();
              return;
            }
            _opened(lease);
          },
          onError: (Object error, StackTrace stack) {
            if (_disposed || generation != _generation) return;
            _openFailed(error, stack);
          },
        );
  }

  void _opened(PdfDocumentLease lease) {
    final PdfPageInfo page;
    try {
      page = PdfRenderService._pageOf(lease, _params.pdfPageIndex);
    } on PdfIoException catch (e, s) {
      lease.release();
      reportPdfError(e, s, 'pdf background ${_params.assetId}');
      _setOpenStatus(PdfRenderStatus.failed, e);
      return;
    }
    _lease = lease;
    _page = page;
    _replan();
    _rebuildSnapshot();
    notifyListeners();
  }

  void _openFailed(Object error, StackTrace stack) {
    final e = error is PdfIoException
        ? error
        : PdfIoException(
            PdfErrorCode.corrupt,
            detail: 'opening ${_params.assetId} failed',
            cause: error,
          );
    switch (e.code) {
      case PdfErrorCode.assetMissing:
        // 6.7.7 (remote request, arrival) comes with T9.
        _setOpenStatus(PdfRenderStatus.assetMissing, e);
      case PdfErrorCode.passwordCancelled:
        _setOpenStatus(PdfRenderStatus.needsPassword, e);
      default:
        // Engine errors are retried once, after the pool's failure memo (6.6, 6.7.5).
        if (!_openRetried) {
          _openRetried = true;
          _retryTimer = Timer(PdfTuning.failureMemo, () {
            _retryTimer = null;
            if (!_disposed) _acquire();
          });
          return;
        }
        reportPdfError(e, stack, 'pdf background ${_params.assetId}');
        _setOpenStatus(PdfRenderStatus.failed, e);
    }
  }

  void _setOpenStatus(PdfRenderStatus status, PdfIoException error) {
    _openStatus = status;
    _error = error;
    _rebuildSnapshot();
    notifyListeners();
  }

  /// 6.7.2: what to draw for the current params; requests what is missing unless quiet.
  void _replan() {
    final page = _page;
    if (_disposed || page == null) return;
    final plan = PdfRenderPlan.of(_params, ui.Size(page.width, page.height));
    final quiet = _quiet || _params.isScaling;

    // Base: preview or thumbnail. While quiet, only a page with no base at all asks for one
    // (a page that mounts during a pinch still shows the PDF).
    final baseKey = _key(plan.baseKind, plan.baseScale);
    final base = _base;
    if (base != null && base.key == baseKey) {
      base.pageRect = plan.fit.pdfBoxInNote;
    } else if (!quiet || (base == null && _previousBase == null)) {
      final slot = _Slot(
        baseKey,
        renderClass: plan.thumbnailMode
            ? PdfRenderClass.thumbnail
            : PdfRenderClass.visiblePreview,
        request: PdfRenderRequest(
          pageIndex: _params.pdfPageIndex,
          scale: plan.baseScale,
          backgroundArgb: opaquePaperArgb(_params.paperColorArgb),
          priority: plan.thumbnailMode
              ? PdfRenderClass.thumbnail.priorityHint
              : PdfRenderClass.visiblePreview.priorityHint,
        ),
        pageRect: plan.fit.pdfBoxInNote,
      );
      _base = slot;
      if (base != null) {
        if (base.image != null) {
          // Keep showing the old base until the new one arrives.
          final previous = _previousBase;
          if (previous != null) _drop(previous);
          _previousBase = base;
        } else {
          _drop(base);
        }
      }
      _fill(slot);
      if (slot.image != null) _dropPreviousBase();
    }

    if (quiet) return;
    final grid = plan.grid;
    if (grid == null) {
      _dropTiles();
      return;
    }
    if (_tileBucket != grid.bucket) {
      for (final slot in _tiles.values) {
        if (slot.image != null) {
          _oldTiles.add(slot);
        } else {
          _drop(slot);
        }
      }
      _tiles.clear();
      _tileBucket = grid.bucket;
    }
    final wanted = {for (final t in plan.tiles) (t.column, t.row): t};
    for (final cell in _tiles.keys.toList()) {
      if (!wanted.containsKey(cell)) _drop(_tiles.remove(cell)!);
    }
    _visibleTiles.clear();
    for (final tile in plan.tiles) {
      final cell = (tile.column, tile.row);
      if (!tile.prefetch) _visibleTiles.add(cell);
      final pageRect = plan.tilePageRect(tile.column, tile.row);
      final existing = _tiles[cell];
      if (existing != null) {
        existing
          ..pageRect = pageRect
          ..renderClass = tile.renderClass;
        continue;
      }
      final slot = _Slot(
        _key(PdfRenderKind.tile, grid.bucket, tile.column, tile.row),
        renderClass: tile.renderClass,
        request: PdfRenderRequest(
          pageIndex: _params.pdfPageIndex,
          scale: grid.bucket,
          region: grid.requestRect(tile.column, tile.row),
          backgroundArgb: opaquePaperArgb(_params.paperColorArgb),
          priority: tile.renderClass.priorityHint,
        ),
        pageRect: pageRect,
        srcRect: grid.srcRect(tile.column, tile.row),
      );
      _tiles[cell] = slot;
      _fill(slot);
    }
    _dropOldTilesWhenCovered();
  }

  PdfRenderKey _key(
    PdfRenderKind kind,
    double scale, [
    int tileX = 0,
    int tileY = 0,
  ]) => (
    assetId: _params.assetId,
    pageIndex: _params.pdfPageIndex,
    kind: kind,
    scale: scale,
    tileX: tileX,
    tileY: tileY,
    backgroundArgb: opaquePaperArgb(_params.paperColorArgb),
  );

  /// From the cache, else queue a render.
  void _fill(_Slot slot) {
    final cached = _cache.take(slot.key);
    if (cached != null) {
      slot.image = cached;
      return;
    }
    final lease = _lease;
    if (lease == null) return;
    final job = _service._scheduler.submit(
      slot.renderClass,
      (token) => lease.document.render(slot.request, cancelToken: token),
    );
    slot.job = job;
    final generation = _generation;
    job.result.then(
      (image) => _rendered(slot, job, image, generation),
      onError: (Object error, StackTrace stack) =>
          _renderFailed(slot, job, error, stack, generation),
    );
  }

  bool _isLive(_Slot slot) =>
      identical(slot, _base) || identical(_tiles[_cellOf(slot)], slot);

  static (int, int) _cellOf(_Slot slot) => (slot.key.tileX, slot.key.tileY);

  void _rendered(
    _Slot slot,
    PdfRenderJob job,
    ui.Image? image,
    int generation,
  ) {
    if (identical(slot.job, job)) slot.job = null;
    if (image == null) return; // cancelled
    if (_disposed || generation != _generation || !_isLive(slot)) {
      // Not wanted here any more: keep it for the next user (LRU / TTL).
      _cache.put(slot.key, image).release();
      return;
    }
    slot.image = _cache.put(slot.key, image);
    if (identical(slot, _base)) _dropPreviousBase();
    _dropOldTilesWhenCovered();
    _rebuildSnapshot();
    notifyListeners();
  }

  void _renderFailed(
    _Slot slot,
    PdfRenderJob job,
    Object error,
    StackTrace stack,
    int generation,
  ) {
    if (identical(slot.job, job)) slot.job = null;
    if (_disposed || generation != _generation || !_isLive(slot)) return;
    if (!slot.retried) {
      slot.retried = true; // engine errors: one retry (6.7.5)
      _fill(slot);
      return;
    }
    slot.failed = true;
    reportPdfError(
      error,
      stack,
      'pdf background render ${slot.key.kind.name} '
      '${_params.assetId} #${_params.pdfPageIndex}',
    );
    if (identical(slot, _base)) {
      _error = error is PdfIoException
          ? error
          : PdfIoException(
              PdfErrorCode.corrupt,
              detail: 'rendering ${_params.assetId} failed',
              cause: error,
            );
    }
    _dropOldTilesWhenCovered();
    _rebuildSnapshot();
    notifyListeners();
  }

  /// Cancels the slot's render; its image leaves after the frame (6.7.5).
  void _drop(_Slot slot) {
    slot.job?.cancel();
    slot.job = null;
    final image = slot.image;
    slot.image = null;
    if (image != null) _service._releaseAfterFrame(image.release);
  }

  void _dropPreviousBase() {
    final previous = _previousBase;
    _previousBase = null;
    if (previous != null) _drop(previous);
  }

  void _dropTiles() {
    for (final slot in [..._tiles.values, ..._oldTiles]) {
      _drop(slot);
    }
    _tiles.clear();
    _visibleTiles.clear();
    _oldTiles.clear();
    _tileBucket = null;
  }

  /// 6.7.2 step 5: older-bucket tiles go once every visible tile of the current bucket is
  /// drawn (or failed for good).
  void _dropOldTilesWhenCovered() {
    if (_oldTiles.isEmpty) return;
    final covered = _visibleTiles.every(
      (cell) => _tiles[cell]?.settled ?? true,
    );
    if (!covered) return;
    for (final slot in _oldTiles) {
      _drop(slot);
    }
    _oldTiles.clear();
  }

  void _rebuildSnapshot() {
    if (_disposed) return;
    final base = _base?.placed() ?? _previousBase?.placed();
    final PdfRenderStatus status;
    if (_openStatus != null) {
      status = _openStatus!;
    } else if (base != null) {
      status = PdfRenderStatus.ready;
    } else if (_base?.failed ?? false) {
      status = PdfRenderStatus.failed;
    } else {
      status = PdfRenderStatus.loading;
    }
    _snapshot = PdfRenderSnapshot(
      status: status,
      base: status == PdfRenderStatus.ready ? base : null,
      tiles: status == PdfRenderStatus.ready
          ? [
              for (final slot in _oldTiles) ?slot.placed(),
              for (final slot in _tiles.values) ?slot.placed(),
            ]
          : const [],
      error: status == PdfRenderStatus.ready ? null : _error,
    );
  }

  static bool _sameParams(PdfBackgroundParams a, PdfBackgroundParams b) =>
      a.assetId == b.assetId &&
      a.pdfPageIndex == b.pdfPageIndex &&
      a.pageSize == b.pageSize &&
      a.deviceScale == b.deviceScale &&
      a.paperColorArgb == b.paperColorArgb &&
      a.visiblePageRect == b.visiblePageRect &&
      a.isScaling == b.isScaling &&
      a.isThumbnail == b.isThumbnail &&
      a.pageId == b.pageId;
}
