// lib/src/math/offscreen_host.dart — INTERNAL (m5-7/03-ink 6.12.2).
//
// An off-screen render pipeline (its own PipelineOwner, BuildOwner and
// RenderView over the implicit view) that builds and lays out a widget away
// from the app's tree — VM `flutter test` and Chrome (CanvasKit) alike.
// A host is made once and reused: each job swaps the widget and runs
// buildScope → finalizeTree → flushLayout. There are two per isolate:
// - the layout host: synchronous layout / validate, never waits (R2-B3);
// - (T36) the raster host: rasterize only. Requests queue FIFO and run one at a
//   time, each starting on a later turn — a microtask after the caller's code,
//   so after the frame when a painter asks (the engine runs build / layout /
//   paint in one go; microtasks run after it) and never inside the app's build
//   / layout / paint (S-9; a job that still finds a frame phase waits a timer
//   turn) — so a job that waits cannot have its tree overwritten. The same
//   request while queued or running joins that job. A job waits for the glyph
//   pictures flutter_math_fork draws through flutter_svg (\sqrt, stretchy
//   arrows / braces …: vector_graphics' VectorGraphic builds an empty box until
//   its picture arrives — on native profile / release from another isolate): it
//   captures only when every VectorGraphic in the tree has its picture child
//   (FittedBox) and no rebuild is pending; otherwise it yields — a few
//   microtask turns first (debug and web decode on the same isolate), then
//   InkTuning.mathSvgPollMs timer turns — and builds again, at most
//   mathSvgSettleMaxRebuilds rebuilds and mathSvgSettleMs in all, then null
//   rather than an image without its root sign (6.12.2, M-3).
// The capture is RenderRepaintBoundary.toImageSync at k = pixelsPerPt lowered
// to 4 Mpx / 8192 px (7.4.5): synchronous on the VM and CanvasKit. A job that
// needs no wait therefore leaves no timer behind (widget tests of a page with a
// formula end without pending timers).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:vector_graphics/vector_graphics.dart'
    show BytesLoader, VectorGraphic;

import '../text/text_layout.dart' show rasterScaleFor;
import '../tuning.dart';

/// The result of one off-screen layout: size and alphabetic baseline (logical px).
@internal
typedef OffscreenLayout = ({Size size, double baseline});

/// One off-screen raster: the image (owned by the receiver) and the laid-out size it was
/// captured from (logical px = pt).
@internal
typedef OffscreenRaster = ({ui.Image image, Size size});

/// A raster request: equal requests while one is queued or running share its job.
@internal
typedef OffscreenRasterKey = ({
  String latex,
  int colorArgb,
  double fontSizePt,
  double pixelsPerPt,
});

@internal
final class OffscreenMathHost {
  OffscreenMathHost._({bool raster = false}) : _isRaster = raster;

  /// The layout host (synchronous layout / validate, never waits).
  static final OffscreenMathHost layoutHost = OffscreenMathHost._();

  /// (T36) The raster host (rasterize only — queued, waits for the glyph pictures).
  static final OffscreenMathHost rasterHost = OffscreenMathHost._(raster: true);

  /// Off-screen constraints (6.12.2): at most 4000 × 4000 logical px.
  static const double maxExtent = 4000;

  /// (T36, test seam — 총괄 답 Q5) A loader the raster host draws in one more
  /// VectorGraphic (8 × 8 px at the top left, over the formula): a delayed loader
  /// reproduces the native release path (picture from an isolate, a later setState)
  /// on the VM debug and Chrome test runners.
  @visibleForTesting
  static BytesLoader? debugExtraSvgLoader;

  /// (T36) The clock of the settle cap (µs). The cap also counts the timer polls
  /// (mathSvgPollMs each), so it holds under fake_async too.
  @visibleForTesting
  static int Function() debugNowUs = _stopwatchUs;

  /// Microtask turns a job yields before its first timer poll (debug and web decode the
  /// glyph pictures on the same isolate, a few Future hops).
  static const int _microtaskPolls = 16;

  /// (T36, tests) Raster jobs started, jobs that ended without an image because the glyph
  /// pictures did not settle (mathRasterFailed), the scheduler phase the last job
  /// started in.
  @visibleForTesting
  static int debugRasterJobs = 0;
  @visibleForTesting
  static int debugSettleFailures = 0;
  @visibleForTesting
  static SchedulerPhase? debugLastJobPhase;

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static int _stopwatchUs() => _stopwatch.elapsedMicroseconds;

  final bool _isRaster;
  PipelineOwner? _pipeline;
  BuildOwner? _build;
  _MeasureBox? _box;
  RenderRepaintBoundary? _boundary;
  RenderObjectToWidgetElement<RenderBox>? _element;
  bool _rebuildRequested = false;
  int _serial = 0;

  // the raster queue
  final List<_Job> _queue = [];
  final Map<OffscreenRasterKey, _Job> _jobs = {};
  bool _running = false;

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
    _requireBinding();
    if (!_ensureTree()) return null;
    _mount(child);
    final box = _box!;
    return (size: box.size, baseline: box.baseline ?? box.size.height);
  }

  /// (T36) Queues a raster of [build]'s widget for [key] (raster host only). The caller
  /// receives its own image handle, or null (invalid formula, no view, glyph pictures not
  /// settled). An equal request while one is queued or running joins that job; its image
  /// is disposed once every caller took its copy.
  Future<OffscreenRaster?> raster(
    OffscreenRasterKey key,
    Widget Function() build,
  ) async {
    assert(_isRaster, 'rasterize runs on the raster host');
    final job = _jobs[key] ?? _enqueue(key, build);
    job.takers++;
    final result = await job.completer.future;
    if (result == null) {
      job.takers--;
      return null;
    }
    final copy = (image: result.image.clone(), size: result.size);
    if (--job.takers == 0) result.image.dispose();
    return copy;
  }

  /// Requests not finished yet (queued + running).
  @visibleForTesting
  int get pendingCount => _jobs.length;

  _Job _enqueue(OffscreenRasterKey key, Widget Function() build) {
    final job = _Job(key, build);
    _jobs[key] = job;
    _queue.add(job);
    if (!_running) {
      _running = true;
      unawaited(_drain());
    }
    return job;
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      // a later turn, never inside the app's build / layout / paint (S-9)
      await Future<void>.value();
      while (inFramePhase) {
        await Future<void>.delayed(Duration.zero);
      }
      final job = _queue.removeAt(0);
      OffscreenRaster? result;
      try {
        result = await _run(job);
      } on Object catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'ink_engine',
            context: ErrorDescription('while rasterizing a formula off screen'),
          ),
        );
        result = null;
      }
      _jobs.remove(job.key);
      job.completer.complete(result);
    }
    _running = false;
  }

  Future<OffscreenRaster?> _run(_Job job) async {
    debugRasterJobs++;
    debugLastJobPhase = _phaseOrNull();
    _requireBinding();
    if (!_ensureTree()) return null;
    final serial = ++_serial;
    final extra = debugExtraSvgLoader;
    final formula = job.build();
    _mount(
      KeyedSubtree(
        key: ValueKey<int>(serial),
        child: extra == null
            ? formula
            : Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(
                  children: [
                    formula,
                    Positioned(
                      left: 0,
                      top: 0,
                      width: 8,
                      height: 8,
                      child: VectorGraphic(loader: extra),
                    ),
                  ],
                ),
              ),
      ),
    );
    // attaching the new widget marked the root dirty; that build is done
    _rebuildRequested = false;
    final box = _box!;
    if (box.size.isEmpty) return null; // an invalid formula builds nothing
    // settle: every glyph picture attached and no rebuild pending (6.12.2)
    final startUs = debugNowUs();
    var rebuilds = 0;
    var microtaskPolls = 0;
    var timerPolls = 0;
    while (_rebuildRequested || !_picturesAttached()) {
      final waitedMs = (debugNowUs() - startUs) / 1000;
      if (waitedMs >= InkTuning.mathSvgSettleMs ||
          timerPolls * InkTuning.mathSvgPollMs >= InkTuning.mathSvgSettleMs ||
          (_rebuildRequested &&
              rebuilds >= InkTuning.mathSvgSettleMaxRebuilds)) {
        debugSettleFailures++;
        return null;
      }
      if (_rebuildRequested) {
        _rebuildRequested = false;
        rebuilds++;
        _rebuild();
        continue;
      }
      if (microtaskPolls < _microtaskPolls) {
        microtaskPolls++;
        await Future<void>.value();
      } else {
        timerPolls++;
        await Future<void>.delayed(
          const Duration(milliseconds: InkTuning.mathSvgPollMs),
        );
      }
    }
    final size = box.size;
    final k = rasterScaleFor(size.width, size.height, job.key.pixelsPerPt);
    if (!(k > 0) || !k.isFinite) return null;
    _pipeline!
      ..flushCompositingBits()
      ..flushPaint();
    final image = _boundary!.toImageSync(pixelRatio: k);
    return (image: image, size: size);
  }

  static SchedulerPhase? _phaseOrNull() {
    try {
      return SchedulerBinding.instance.schedulerPhase;
    } on Object {
      return null;
    }
  }

  static void _requireBinding() {
    try {
      WidgetsBinding.instance;
    } on Object {
      throw StateError(
        'InkMathRenderer.layout needs an initialized WidgetsBinding '
        '(runApp or WidgetsFlutterBinding.ensureInitialized)',
      );
    }
  }

  /// The pipeline over the implicit view; false when there is no view.
  bool _ensureTree() {
    if (_pipeline != null && !_fontsChanged) return true;
    if (_pipeline != null) _abandonTree();
    final view = _viewOrNull();
    if (view == null) return false;
    if (!_fontsListening) {
      _fontsListening = true;
      PaintingBinding.instance.systemFonts.addListener(_systemFontsChanged);
    }
    _build = BuildOwner(
      focusManager: FocusManager(),
      onBuildScheduled: _isRaster ? () => _rebuildRequested = true : null,
    );
    final box = _box = _MeasureBox();
    final RenderBox content = _isRaster
        ? (_boundary = RenderRepaintBoundary(child: box))
        : box;
    final renderView = RenderView(
      view: view,
      configuration: const ViewConfiguration(
        logicalConstraints: BoxConstraints(
          maxWidth: maxExtent,
          maxHeight: maxExtent,
        ),
        devicePixelRatio: 1,
      ),
      child: RenderPositionedBox(alignment: Alignment.topLeft, child: content),
    );
    _pipeline = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();
    return true;
  }

  /// (T41) A system fonts change (NoteSans arriving — InkFonts) marks every paragraph of
  /// the tree with a font update that only the next frame runs; unmounting such a
  /// paragraph before that frame trips RenderObject.detach's assert (debug, tests) and the
  /// old formula stays mounted — every later raster was the formula before the change.
  /// So the next job builds a new tree and the old one is dropped as it is (still attached
  /// to its own pipeline: its pending updates run harmlessly on a later frame; one small
  /// tree per fonts change).
  bool _fontsChanged = false;
  bool _fontsListening = false;

  void _systemFontsChanged() => _fontsChanged = true;

  void _abandonTree() {
    _fontsChanged = false;
    _element = null;
    _box = null;
    _boundary = null;
    _pipeline = null;
    _build = null;
  }

  void _mount(Widget child) {
    final build = _build!;
    final element = _element = RenderObjectToWidgetAdapter<RenderBox>(
      container: _box!,
      child: child,
    ).attachToRenderTree(build, _element);
    build
      ..buildScope(element)
      ..finalizeTree();
    _pipeline!.flushLayout();
  }

  void _rebuild() {
    final element = _element;
    if (element == null) return;
    _build!
      ..buildScope(element)
      ..finalizeTree();
    _pipeline!.flushLayout();
  }

  /// Every VectorGraphic of the tree shows its picture: its subtree has the FittedBox
  /// vector_graphics 1.2.3 builds around a loaded picture (a placeholder box before).
  bool _picturesAttached() {
    final root = _element;
    if (root == null) return true;
    var attached = true;
    void visit(Element e) {
      if (!attached) return;
      if (e.widget is VectorGraphic && !_hasFittedBox(e)) {
        attached = false;
        return;
      }
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    return attached;
  }

  static bool _hasFittedBox(Element graphic) {
    var found = false;
    void visit(Element e) {
      if (found) return;
      if (e.widget is FittedBox) {
        found = true;
        return;
      }
      e.visitChildren(visit);
    }

    graphic.visitChildren(visit);
    return found;
  }

  static ui.FlutterView? _viewOrNull() {
    final dispatcher = ui.PlatformDispatcher.instance;
    final implicit = dispatcher.implicitView;
    if (implicit != null) return implicit;
    final views = dispatcher.views;
    return views.isEmpty ? null : views.first;
  }
}

final class _Job {
  _Job(this.key, this.build);
  final OffscreenRasterKey key;
  final Widget Function() build;
  final Completer<OffscreenRaster?> completer = Completer();

  /// Callers still to take their copy of the image.
  int takers = 0;
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
