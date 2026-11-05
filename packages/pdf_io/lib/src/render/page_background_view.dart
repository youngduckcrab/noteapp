// lib/src/render/page_background_view.dart — 06-pdf 4.7, 6.8 (PDF T9).
//
// One page background: attaches a PdfPageRenderHandle (initState), forwards new params
// (didUpdateWidget), disposes it (dispose) and repaints on its snapshot. The box is
// params.pageSize × viewScale logical px (contract 7.2.16 v1.1: viewScale only, never
// ancestorScale), always opaque paper, never takes pointer events. Status display (6.8 ⑤):
// logical-px overlay — icon only in thumbnail mode, 14 px text otherwise (6.14 texts).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../text/search_types.dart';
import '../tuning.dart';
import '../ui/strings_ko.dart';
import 'page_background_painter.dart';
import 'render_service.dart';

/// Fills the page box (params.pageSize * viewScale logical px), paints opaque paper,
/// never handles pointer events (wrapped in IgnorePointer).
class PdfPageBackgroundView extends StatefulWidget {
  const PdfPageBackgroundView({
    super.key,
    required this.params,
    required this.renderer,
    this.highlights,
    required this.viewScale,
  });
  final PdfBackgroundParams params;
  final PdfPageRenderer renderer;

  /// Active search state for highlight rects (null = no highlights).
  final ValueListenable<PdfSearchState>? highlights;

  /// Logical px per NOTE pt = ink.PageBackgroundContext.viewScale. Widget size and painter
  /// scale use THIS ONLY (contract 7.2.16 v1.1). ancestorScale is never multiplied in: an
  /// ancestor Transform already applies it on screen; it reaches the render resolution only
  /// through params.deviceScale (= ctx.deviceScale).
  final double viewScale;

  @override
  State<PdfPageBackgroundView> createState() => _PdfPageBackgroundViewState();
}

class _PdfPageBackgroundViewState extends State<PdfPageBackgroundView> {
  late PdfPageRenderHandle _handle;
  Timer? _loadingTimer;

  /// loading for longer than PdfTuning.loadingIndicatorDelay (6.8).
  bool _slowLoading = false;

  @override
  void initState() {
    super.initState();
    _handle = widget.renderer.attach(widget.params)..addListener(_changed);
    widget.highlights?.addListener(_changed);
    _syncLoadingTimer();
  }

  @override
  void didUpdateWidget(PdfPageBackgroundView old) {
    super.didUpdateWidget(old);
    if (!identical(old.renderer, widget.renderer)) {
      _handle
        ..removeListener(_changed)
        ..dispose();
      _handle = widget.renderer.attach(widget.params)..addListener(_changed);
    } else {
      _handle.update(widget.params);
    }
    if (!identical(old.highlights, widget.highlights)) {
      old.highlights?.removeListener(_changed);
      widget.highlights?.addListener(_changed);
    }
    _syncLoadingTimer();
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    widget.highlights?.removeListener(_changed);
    _handle
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(_syncLoadingTimer);
  }

  void _syncLoadingTimer() {
    if (_handle.snapshot.status == PdfRenderStatus.loading) {
      _loadingTimer ??= Timer(PdfTuning.loadingIndicatorDelay, () {
        if (mounted) setState(() => _slowLoading = true);
      });
    } else {
      _loadingTimer?.cancel();
      _loadingTimer = null;
      _slowLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = widget.params;
    final snapshot = _handle.snapshot;
    final pageId = params.pageId;
    final search = widget.highlights?.value;
    final hasHits = pageId != null && search != null && search.hits.isNotEmpty;
    final size = Size(
      params.pageSize.width * widget.viewScale,
      params.pageSize.height * widget.viewScale,
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox.fromSize(
          size: size,
          child: CustomPaint(
            painter: PdfPageBackgroundPainter(
              snapshot: snapshot,
              paperColorArgb: params.paperColorArgb,
              viewScale: widget.viewScale,
              highlightRects: hasHits ? search.rectsFor(pageId) : const [],
              currentRects: hasHits ? search.currentRectsFor(pageId) : const [],
            ),
            child: _status(context, snapshot, params.usesThumbnailMode),
          ),
        ),
      ),
    );
  }

  /// 6.8 ⑤: null when nothing is shown (ready, or loading for less than 300 ms).
  Widget? _status(
    BuildContext context,
    PdfRenderSnapshot snapshot,
    bool iconOnly,
  ) {
    final remote = snapshot.remote;
    final IconData icon;
    final String text;
    double? progress;
    var showProgress = false;
    switch (snapshot.status) {
      case PdfRenderStatus.ready:
        return null;
      case PdfRenderStatus.loading:
        if (!_slowLoading) return null;
        return const Center(
          child: SizedBox.square(
            dimension: _loadingIndicatorSize,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case PdfRenderStatus.assetMissing:
        icon = Icons.description_outlined;
        text = switch (remote?.state) {
          core.RemoteAssetState.offline => PdfStringsKo.backgroundOffline,
          core.RemoteAssetState.failed => PdfStringsKo.backgroundDownloadFailed,
          _ => PdfStringsKo.backgroundNoSource,
        };
      case PdfRenderStatus.downloading:
        icon = Icons.cloud_download_outlined;
        showProgress = true;
        if (remote?.state == core.RemoteAssetState.waiting) {
          text = PdfStringsKo.backgroundWaiting;
        } else {
          final received = remote?.received;
          final total = remote?.total;
          if (received != null && total != null && total > 0) {
            progress = (received / total).clamp(0.0, 1.0);
          }
          text = PdfStringsKo.backgroundDownloading(
            progress == null ? null : (progress * 100).floor(),
          );
        }
      case PdfRenderStatus.needsPassword:
        icon = Icons.lock_outline;
        text = PdfStringsKo.backgroundNeedsPassword;
      case PdfRenderStatus.failed:
        icon = Icons.warning_amber;
        text = PdfStringsKo.backgroundRenderFailed;
    }
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconOnly ? _thumbnailIconSize : _iconSize,
              color: scheme.onSurfaceVariant,
              semanticLabel: text,
            ),
            if (showProgress) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: iconOnly ? _thumbnailIconSize * 2 : _progressWidth,
                child: LinearProgressIndicator(value: progress),
              ),
            ],
            if (!iconOnly) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _textMaxWidth),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _statusFontSize,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Status display sizes, logical px whatever the zoom (6.8 ⑤).
  static const double _statusFontSize = 14;
  static const double _iconSize = 32;
  static const double _thumbnailIconSize = 20;
  static const double _loadingIndicatorSize = 20;
  static const double _progressWidth = 160;
  static const double _textMaxWidth = 280;
}
