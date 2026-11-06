// lib/src/math/offscreen_host.dart — INTERNAL (m5-7/03-ink 6.12.2).
//
// An off-screen render pipeline (its own PipelineOwner, BuildOwner and
// RenderView over the implicit view) that builds and lays out a widget away
// from the app's tree — VM `flutter test` and Chrome (CanvasKit) alike.
// The host is made once and reused: each layout swaps the widget and runs
// buildScope → finalizeTree → flushLayout. Foundation step R2-B3 has the
// layout host only (InkMathRenderer.layout / validate); the raster host with
// its queue and the wait for asynchronously loaded SVG glyphs is T36.
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The result of one off-screen layout: size and alphabetic baseline (logical px).
@internal
typedef OffscreenLayout = ({Size size, double baseline});

@internal
final class OffscreenMathHost {
  OffscreenMathHost._();

  /// The layout host (synchronous layout / validate, never waits).
  static final OffscreenMathHost layoutHost = OffscreenMathHost._();

  /// Off-screen constraints (6.12.2): at most 4000 × 4000 logical px.
  static const double maxExtent = 4000;

  PipelineOwner? _pipeline;
  BuildOwner? _build;
  _MeasureBox? _box;
  RenderObjectToWidgetElement<RenderBox>? _element;

  /// True while the app is in a build / layout / paint phase (another BuildOwner must not
  /// run then — S-9). False when no binding exists (plain VM tests).
  static bool get inFramePhase {
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on Object {
      return false;
    }
    return binding.schedulerPhase == SchedulerPhase.persistentCallbacks;
  }

  /// Builds and lays out [child]; null when there is no view to attach the pipeline to.
  /// Exceptions from build / layout propagate (the caller maps them). Needs the app's
  /// WidgetsBinding (flutter_math_fork's widgets use global keys) — StateError without one.
  OffscreenLayout? layout(Widget child) {
    try {
      WidgetsBinding.instance;
    } on Object {
      throw StateError(
        'InkMathRenderer.layout needs an initialized WidgetsBinding '
        '(runApp or WidgetsFlutterBinding.ensureInitialized)',
      );
    }
    final view = _viewOrNull();
    if (view == null) return null;
    final build = _build ??= BuildOwner(focusManager: FocusManager());
    final box = _box ??= _MeasureBox();
    if (_pipeline == null) {
      final renderView = RenderView(
        view: view,
        configuration: const ViewConfiguration(
          logicalConstraints: BoxConstraints(
            maxWidth: maxExtent,
            maxHeight: maxExtent,
          ),
          devicePixelRatio: 1,
        ),
        child: RenderPositionedBox(alignment: Alignment.topLeft, child: box),
      );
      _pipeline = PipelineOwner()..rootNode = renderView;
      renderView.prepareInitialFrame();
    }
    final element = _element = RenderObjectToWidgetAdapter<RenderBox>(
      container: box,
      child: child,
    ).attachToRenderTree(build, _element);
    build
      ..buildScope(element)
      ..finalizeTree();
    _pipeline!.flushLayout();
    return (size: box.size, baseline: box.baseline ?? box.size.height);
  }

  static ui.FlutterView? _viewOrNull() {
    final dispatcher = ui.PlatformDispatcher.instance;
    final implicit = dispatcher.implicitView;
    if (implicit != null) return implicit;
    final views = dispatcher.views;
    return views.isEmpty ? null : views.first;
  }
}

/// Lays out its child loosely and records the child's alphabetic baseline while it is the
/// parent doing layout (the only place the baseline may be asked for).
final class _MeasureBox extends RenderProxyBox {
  double? baseline;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      baseline = null;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(child.size);
    baseline = child.getDistanceToBaseline(TextBaseline.alphabetic);
  }
}
