// lib/src/render/ink_page_view.dart — 03-ink 4.9, viewport report 6.12 R9.
//
// The layer stack of 6.12: background builder widget, then one RepaintBoundary
// + CustomPaint per controller layer (highlighter base picture, active
// highlighter groups, ink chunk pictures, pending / live / previewed strokes,
// lasso path), clipped to the page. The viewport report follows 6.12 R9
// (post-frame setViewport, no notification, currentBucket). Raster tiles come
// with INK T19.
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

import '../background/background_builder.dart';
import '../background/builder_choice.dart';
import '../interop/core_interop.dart' as interop;
import 'ink_page_controller.dart';

/// Paints one page: background → highlighter → active highlighter → ink → active ink → overlay.
/// Fills its box; page pt are mapped uniformly (viewScale = size.width / pageSize.width).
/// No gesture handling (EDITOR wraps it with its own Listener).
/// The ONLY caller of controller.setViewport (contract 7.2.15 v1.1): after layout, from one
/// post-frame callback per changed (visiblePageRect, deviceScale, isScaling), with
/// deviceScale = viewScale × ancestorScale × MediaQuery.devicePixelRatioOf(context) —
/// never during build / layout (6.12 R9). One InkPageView per controller (debug assert).
class InkPageView extends StatefulWidget {
  const InkPageView({
    super.key,
    required this.controller,
    this.ancestorScale = 1.0,
    this.isScaling = false,
    this.visiblePageRect,
    this.showBackground = true,
  });
  final InkPageController controller;

  /// ancestor Transforms (pinch preview): deviceScale only, never layout
  final double ancestorScale;

  /// true while zoom animates → no re-raster
  final bool isScaling;

  /// page-space visible rect; null = whole page
  final Rect? visiblePageRect;
  final bool showBackground;

  @override
  State<InkPageView> createState() => _InkPageViewState();
}

@immutable
final class _ViewportReport {
  const _ViewportReport(this.visiblePageRect, this.deviceScale, this.isScaling);
  final Rect? visiblePageRect;
  final double deviceScale;
  final bool isScaling;

  @override
  bool operator ==(Object other) =>
      other is _ViewportReport &&
      other.visiblePageRect == visiblePageRect &&
      other.deviceScale == deviceScale &&
      other.isScaling == isScaling;

  @override
  int get hashCode => Object.hash(visiblePageRect, deviceScale, isScaling);
}

class _InkPageViewState extends State<InkPageView> {
  _ViewportReport? _reported;
  _ViewportReport? _pending;
  bool _scheduled = false;

  static const List<InkRenderLayer> _paintedLayers = [
    InkRenderLayer.highlighterBase,
    InkRenderLayer.highlighterActive,
    InkRenderLayer.inkBase,
    InkRenderLayer.inkActive,
    InkRenderLayer.overlay,
  ];

  @override
  void initState() {
    super.initState();
    _attach(widget.controller);
  }

  @override
  void didUpdateWidget(InkPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach(oldWidget.controller);
      _attach(widget.controller);
      _reported = null;
    }
  }

  @override
  void dispose() {
    _detach(widget.controller);
    super.dispose();
  }

  void _attach(InkPageController c) {
    inkPageRenderOf(c).attachView(this);
    c.addListener(_changed);
  }

  void _detach(InkPageController c) {
    c.removeListener(_changed);
    inkPageRenderOf(c).detachView(this);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// 6.12 R9 ①②: compare with the last report and, when different, register ONE
  /// post-frame callback (several changes in a frame collapse into the last value).
  void _scheduleReport(_ViewportReport report) {
    _pending = report;
    if (_scheduled || report == _reported) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final p = _pending;
      if (!mounted || p == null || p == _reported) return;
      widget.controller.setViewport(
        visiblePageRect: p.visiblePageRect,
        deviceScale: p.deviceScale,
        isScaling: p.isScaling,
      );
      _reported = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final content = controller.content;
    if (content == null) return const SizedBox.shrink();
    final render = inkPageRenderOf(controller);
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageSize = content.pageSize;
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : pageSize.width;
        final viewScale = width / pageSize.width;
        final height = pageSize.height * viewScale;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        _scheduleReport(
          _ViewportReport(
            widget.visiblePageRect,
            viewScale * widget.ancestorScale * dpr,
            widget.isScaling,
          ),
        );
        final background = content.background;
        return SizedBox(
          width: width,
          height: height,
          child: ClipRect(
            child: Stack(
              children: [
                if (widget.showBackground)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: IgnorePointer(
                      child:
                          backgroundBuilderFor(
                            controller.backgroundBuilders,
                            background,
                          ).build(
                            context,
                            PageBackgroundContext(
                              pageId: content.pageId,
                              pageSize: pageSize,
                              background: background,
                              viewScale: viewScale,
                              ancestorScale: widget.ancestorScale,
                              devicePixelRatio: dpr,
                              isScaling: widget.isScaling,
                              visiblePageRect: widget.visiblePageRect,
                            ),
                          ),
                    ),
                  ),
                for (final layer in _paintedLayers)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _LayerPainter(
                          render,
                          layer,
                          viewScale,
                          controller.layerRepaint(layer),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LayerPainter extends CustomPainter {
  _LayerPainter(this.render, this.layer, this.viewScale, Listenable repaint)
    : super(repaint: repaint);

  final InkPageRender render;
  final InkRenderLayer layer;
  final double viewScale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(viewScale);
    render.paint(canvas, layer, viewScale);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LayerPainter oldDelegate) =>
      !identical(oldDelegate.render, render) ||
      oldDelegate.layer != layer ||
      oldDelegate.viewScale != viewScale;
}

abstract final class InkPageGeometry {
  static double viewScaleOf(Size viewSize, Size pageSize) =>
      viewSize.width / pageSize.width;

  static Offset localToPage(Offset local, Size viewSize, Size pageSize) =>
      local / viewScaleOf(viewSize, pageSize);

  static Offset pageToLocal(Offset page, Size viewSize, Size pageSize) =>
      page * viewScaleOf(viewSize, pageSize);

  // CORE ↔ dart:ui conversions (delegate to core_interop.dart)
  static Size sizeOf(core.PageSize size) => interop.sizeOf(size);
  static Rect rectOf(core.PageRect rect) => interop.rectOf(rect);
  static core.PageRect pageRectOf(Rect rect) => interop.pageRectOf(rect);
  static Offset applyAffine(core.Affine2 m, Offset p) =>
      interop.applyAffine(m, p);

  /// Column-major 4x4 for Canvas.transform / Transform widgets.
  static Float64List matrix4Of(core.Affine2 m) => interop.matrix4Of(m);
}
