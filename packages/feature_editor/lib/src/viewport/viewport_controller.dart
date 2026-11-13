// lib/src/viewport/viewport_controller.dart — 04-editor 6.3.4, 6.11.6.
//
// Owns the camera of one note screen: layout from the session's pages,
// navigation gestures (pinch / pan / fling / snaps), programmatic moves and the
// "settled" state that PageViewport lays pages out at (6.4.3).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:note_core/note_core.dart' as core;

import 'page_layout.dart';
import 'viewport_camera.dart';
import 'viewport_constants.dart';

@immutable
class ViewportAnchor {
  const ViewportAnchor({
    required this.pageId,
    required this.offsetInPage, // origin - pageRect.topLeft (pt)
    required this.zoom,
  });
  final String pageId;
  final Offset offsetInPage;
  final double zoom;

  /// `{"pageId": .., "dx": .., "dy": .., "zoom": ..}` (an `editor.viewport`
  /// entry without its noteId / at — 6.14).
  Map<String, Object?> toJson() => {
    'pageId': pageId,
    'dx': offsetInPage.dx,
    'dy': offsetInPage.dy,
    'zoom': zoom,
  };

  /// Throws [FormatException] for a missing or invalid field. Integers are
  /// accepted for the double fields (contract 7.4.6).
  factory ViewportAnchor.fromJson(Map<String, Object?> json) {
    final pageId = json['pageId'];
    if (pageId is! String || pageId.isEmpty) {
      throw FormatException('viewport anchor: invalid pageId', pageId);
    }
    double number(String name) {
      final v = json[name];
      if (v is num && v.isFinite) return v.toDouble();
      throw FormatException('viewport anchor: invalid $name', v);
    }

    final zoom = number('zoom');
    if (zoom <= 0) throw FormatException('viewport anchor: invalid zoom', zoom);
    return ViewportAnchor(
      pageId: pageId,
      offsetInPage: Offset(number('dx'), number('dy')),
      zoom: zoom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ViewportAnchor &&
      other.pageId == pageId &&
      other.offsetInPage == offsetInPage &&
      other.zoom == zoom;
  @override
  int get hashCode => Object.hash(pageId, offsetInPage, zoom);

  @override
  String toString() =>
      'ViewportAnchor($pageId, offset: $offsetInPage, zoom: $zoom)';
}

/// Pull to add a page (04-editor 6.11.7) — what the trailing indicator shows.
enum PullToAddPhase {
  /// No pull (the camera is within its bounds).
  idle,

  /// Held past the end, short of [ViewportConstants.pullToAddThreshold]
  /// (also while it springs back after such a release).
  pulling,

  /// Held at or past the threshold: a release adds a page.
  armed,

  /// Released past the threshold: the camera holds there while the page is
  /// added, then moves on to the new page ([updatePages], [endHeldPull]).
  released,
}

/// Minimum fling speed (6.3.4 '제스처 끝' ①).
const double _flingMinVelocity = 50; // px/s
/// Paged mode snaps only near fit (6.3.4 '제스처 끝' ③).
const double _pagedSnapMaxZoom = 1.05;

/// settledScale changes only for a relative difference of at least this.
const double _settleScaleTolerance = 0.001;

/// Share of the viewport scrolled by scrollByViewport (6.3.4).
const double _scrollViewportFraction = 0.9;

/// Margin around a focus rect that has to be zoomed out to fit (6.11.6).
const double _revealMargin = 24; // logical px

/// Owns the camera. Creates its own [Ticker] (no TickerProvider needed), so
/// it can live in a provider. Notifies on every camera change (hot path:
/// listened by PageViewport's ListenableBuilder only).
class ViewportController extends ChangeNotifier {
  ViewportController() {
    _ticker = Ticker(_onTick, debugLabel: 'ViewportController');
  }

  late final Ticker _ticker;
  List<core.Page> _pages = const [];
  LayoutAxis _axis = LayoutAxis.vertical;
  PageLayout _layout = PageLayout.compute(
    pageSizes: const [],
    axis: LayoutAxis.vertical,
  );
  Size _viewportSize = Size.zero;
  double _fitScale = 1;
  ViewportCamera _camera = const ViewportCamera(scale: 1, origin: Offset.zero);
  bool _placed = false; // a real camera exists (size and pages known)
  ({ViewportAnchor? anchor, String? initialPageId, Rect? focusRectPt})?
  _pendingRestore;

  final ValueNotifier<double> _settledScale = ValueNotifier(1);
  final ValueNotifier<bool> _isInteracting = ValueNotifier(false);
  final ValueNotifier<int> _currentPageIndex = ValueNotifier(0);
  Timer? _settleTimer;

  // Gesture state.
  bool _gestureActive = false;
  ViewportCamera? _gestureBase;
  bool _gestureScaled = false;
  bool _pullScaled = false; // spread changed past pullToAddScaleTolerance
  Offset? _lastFocal;
  int _gestureStartPage = 0;

  // Pull to add a page (04-editor 6.11.7).
  bool _pullAllowed = false; // this gesture may overscroll past the end
  double _pullRaw = 0; // finger travel past the end (screen px, undamped)
  final ValueNotifier<PullToAddPhase> _pullPhase = ValueNotifier(
    PullToAddPhase.idle,
  );
  int _pullToken = 0; // invalidates an older spring-back's completion

  // Animation state.
  _CameraAnimation? _animation;
  Completer<void>? _animationDone;
  bool _disposed = false;

  ViewportCamera get camera => _camera;
  PageLayout get layout => _layout;
  Size get viewportSize => _viewportSize;
  double get fitScale => _fitScale;
  double get zoom => _camera.scale / _fitScale; // camera.scale / fitScale
  LayoutAxis get axis => _axis;

  /// The pages last given to [updatePages] (display order).
  List<core.Page> get pages => _pages;

  /// Scale the pages are laid out at; changes only after interactions settle.
  ValueListenable<double> get settledScale => _settledScale;

  /// True during pinch/pan/fling/animation and for settleDelay after.
  ValueListenable<bool> get isInteracting => _isInteracting;

  /// Page containing the viewport centre (nearest if in a gap).
  ValueListenable<int> get currentPageIndex => _currentPageIndex;

  /// Pull to add a page (04-editor 6.11.7): idle unless a navigation drag is held past
  /// the document end, or springs back from there.
  ValueListenable<PullToAddPhase> get pullPhase => _pullPhase;

  /// The shown pull past the document end along the main axis (logical
  /// px), 0 when [pullPhase] is idle.
  double get pullExtent {
    if (_pullPhase.value == PullToAddPhase.idle || !_valid) return 0;
    return math.max(0, _overscroll(_camera));
  }

  /// Screen position (logical px along the main axis, from the viewport's
  /// top / left) of the document end — where the strip a pull reveals
  /// starts (after the trailing '+ 페이지' room; above the viewport edge
  /// when a short document sits centred).
  double get pullEdge {
    if (!_valid) return 0;
    return (_mainOf(_layout.contentSize.bottomRight(Offset.zero)) -
            _mainOf(_camera.origin)) *
        _camera.scale;
  }

  /// True while a fling, snap or programmatic animation runs.
  bool get isAnimating => _animation != null;

  bool get _valid =>
      _layout.length > 0 && _viewportSize.width > 0 && _viewportSize.height > 0;

  /// Pages meeting the visible doc rect (the nearest one when none does).
  ({int first, int last})? get visibleRange {
    if (!_valid) return null;
    final range = _layout.rangeIntersecting(
      _camera.visibleDocRect(_viewportSize),
    );
    if (range != null) return range;
    final i = _computeCurrentPage();
    return (first: i, last: i);
  }

  /// 6.4.1: visible ±1, at most [ViewportConstants.maxMountedPages] (the ones
  /// nearest the viewport centre).
  ({int first, int last})? get mountedRange {
    final visible = visibleRange;
    if (visible == null) return null;
    final first = math.max(0, visible.first - 1);
    final last = math.min(_layout.length - 1, visible.last + 1);
    const max = ViewportConstants.maxMountedPages;
    if (last - first + 1 <= max) return (first: first, last: last);
    final centre = _mainOf(_camera.visibleDocRect(_viewportSize).center);
    double distance(int i) {
      final r = _layout.rectOf(i);
      final start = _mainStart(r);
      final end = _mainEnd(r);
      if (centre < start) return start - centre;
      if (centre > end) return centre - end;
      return 0;
    }

    var lo = _computeCurrentPage().clamp(first, last);
    var hi = lo;
    while (hi - lo + 1 < max) {
      final canLo = lo > first;
      final canHi = hi < last;
      if (canLo && (!canHi || distance(lo - 1) <= distance(hi + 1))) {
        lo--;
      } else {
        hi++;
      }
    }
    return (first: lo, last: hi);
  }

  // ---- inputs from the widget tree / settings ----

  /// Keeps anchor + zoom: new fit → scale = zoom × fit → anchor restored.
  void updateViewportSize(Size size) {
    if (_disposed || size == _viewportSize) return;
    final anchor = _captureInternal();
    _stopAnimation(scheduleSettle: false);
    _viewportSize = size;
    _relayout(anchor);
  }

  /// Keeps anchor (by page id); sizes from page.size. Always stores the new Page values,
  /// but does no relayout and sends no notification when the id order and sizes are
  /// unchanged — pagesStream also emits when only a Page value such as contentRevision
  /// changes (N-1 v1.1).
  void updatePages(List<core.Page> pages) {
    if (_disposed) return;
    final sameShape = _sameShape(_pages, pages);
    final anchor = sameShape ? null : _captureInternal();
    _pages = List.unmodifiable(pages);
    if (sameShape) return;
    _stopAnimation(scheduleSettle: false);
    // (6.11.7) a held pull ends here: the camera stays where the pull left
    // it (inside the longer document) so the jump to the new page goes on
    // forward from there.
    final held = !_gestureActive && _pullPhase.value == PullToAddPhase.released;
    if (!_gestureActive && _pullPhase.value != PullToAddPhase.idle) {
      _pullToken++;
      _pullRaw = 0;
      _pullPhase.value = PullToAddPhase.idle;
    }
    _layout = _computeLayout();
    if (held && _placed && _valid) {
      final next = _clamp(_camera);
      if (next == _camera) {
        _updateCurrentPage();
        notifyListeners(); // the layout itself changed
      } else {
        _setCamera(next);
      }
      _scheduleSettle();
      return;
    }
    _relayout(anchor);
  }

  /// Keeps current page, zoom → 1 (vertical: the page top at fit width;
  /// horizontal: the page centred at its fit scale, as [jumpToPage]).
  void setAxis(LayoutAxis axis) {
    if (_disposed || axis == _axis) return;
    final index = _placed ? _computeCurrentPage() : 0;
    _stopAnimation(scheduleSettle: false);
    _pullRaw = 0;
    _pullToken++;
    _pullPhase.value = PullToAddPhase.idle;
    _axis = axis;
    _layout = _computeLayout();
    if (!_valid || !_placed) {
      _relayout(null);
      return;
    }
    _fitScale = _fitFor(index);
    _place(
      _vertical
          ? _pageStartCamera(index, scale: _fitScale)
          : _pageCamera(index),
      settle: true,
    );
  }

  /// First display: [initialPageId] (if it is a page of the note) at the top
  /// at fit width / else [anchor] (page id, offset in page, zoom) / else the
  /// first page at zoom 1. An anchor whose page is gone goes to page 0.
  /// (v2, m5-7/04-editor 6.16) With [initialPageId] and [focusRectPt]
  /// (displayed page pt of that page): from that start camera, the rect is
  /// brought into view as [revealPageRect] does (no animation).
  /// Settles at once (no interaction). Before the viewport size and pages are
  /// known it is kept and applied when they arrive.
  void restore(
    ViewportAnchor? anchor, {
    String? initialPageId,
    Rect? focusRectPt,
  }) {
    if (_disposed) return;
    if (!_valid) {
      _pendingRestore = (
        anchor: anchor,
        initialPageId: initialPageId,
        focusRectPt: focusRectPt,
      );
      return;
    }
    _pendingRestore = null;
    _stopAnimation(scheduleSettle: false);
    _gestureActive = false;
    _gestureBase = null;
    _pullRaw = 0;
    _pullAllowed = false;
    _pullToken++;
    _pullPhase.value = PullToAddPhase.idle;
    _placed = true;
    _place(_restoreCamera(anchor, initialPageId, focusRectPt), settle: true);
  }

  /// Whether the first camera has been placed (viewport size and pages
  /// known, [restore] applied).
  bool get isPlaced => _placed && _valid;

  // ---- navigation (called by InteractionHost) ----

  /// Captures base camera, stops animations.
  ///
  /// [allowPullToAdd] (6.11.7): a pan held past the document end may
  /// overscroll (rubber band) and [endGesture] reports a release past the
  /// threshold. Only for a navigation drag on an editable note.
  void beginGesture({bool allowPullToAdd = false}) {
    if (_disposed) return;
    _stopAnimation(scheduleSettle: false);
    _settleTimer?.cancel();
    _settleTimer = null;
    _gestureActive = true;
    // A page add in flight (released): no second pull until it lands.
    _pullAllowed =
        allowPullToAdd && _pullPhase.value != PullToAddPhase.released;
    _pullToken++;
    // Caught during a spring-back: carry on from the shown pull.
    final shown = _valid ? _overscroll(_camera) : 0.0;
    _pullRaw = _pullAllowed && shown > 0
        ? shown / ViewportConstants.pullToAddResistance
        : 0;
    if (_pullRaw == 0) {
      _pullPhase.value = PullToAddPhase.idle;
      // Not carried on: never left past the end.
      if (shown > 0) _setCamera(_clamp(_camera));
    }
    _gestureBase = _baseCamera();
    _gestureScaled = false;
    _pullScaled = false;
    _lastFocal = null;
    _gestureStartPage = _currentPageIndex.value;
    _isInteracting.value = true;
  }

  void updateGesture({
    required Offset baselineFocal,
    required Offset focal,
    required double scaleRatio,
    required bool rebased, // pointer count changed → new base camera
  }) {
    if (_disposed || !_valid) return;
    if (!_gestureActive) beginGesture();
    if (rebased || _gestureBase == null) _gestureBase = _baseCamera();
    final base = _gestureBase!;
    _lastFocal = focal;
    final next = CameraMath.applyGesture(
      base: base,
      baselineFocal: baselineFocal,
      focal: focal,
      scaleRatio: scaleRatio,
      layout: _layout,
      viewport: _viewportSize,
      fitScale: _fitScale,
    );
    if (next.scale != base.scale) _gestureScaled = true;
    // Two fingers never keep an exact spread: only a real pinch stops a pull.
    if ((scaleRatio - 1).abs() > ViewportConstants.pullToAddScaleTolerance) {
      _pullScaled = true;
    }
    _setCamera(
      _pulled(next, base.screenToDoc(baselineFocal) - focal / next.scale),
    );
  }

  /// Pull to add a page (04-editor 6.11.7): [clamped] moved past the document end by
  /// the rubber-banded travel of [unclamped] beyond it (a pinch never pulls).
  ViewportCamera _pulled(ViewportCamera clamped, Offset unclamped) {
    final excess = _pullAllowed && !_pullScaled
        ? (_mainOf(unclamped) - _mainOf(clamped.origin)) * clamped.scale
        : 0.0;
    if (!(excess > 0)) {
      _pullRaw = 0;
      _pullPhase.value = PullToAddPhase.idle;
      return clamped;
    }
    _pullRaw = excess;
    final shown = CameraMath.pullExtent(excess);
    _pullPhase.value = shown >= ViewportConstants.pullToAddThreshold
        ? PullToAddPhase.armed
        : PullToAddPhase.pulling;
    return _withMain(clamped, _mainOf(clamped.origin) + shown / clamped.scale);
  }

  /// Gesture base: the camera, with the undamped pull past the end while
  /// pulling (a rebase keeps the rubber band continuous).
  ViewportCamera _baseCamera() {
    if (_pullRaw <= 0 || !_valid) return _camera;
    final clamped = _clamp(_camera);
    return _withMain(
      _camera,
      _mainOf(clamped.origin) + _pullRaw / _camera.scale,
    );
  }

  ViewportCamera _withMain(ViewportCamera c, double main) => c.copyWith(
    origin: _vertical ? Offset(c.origin.dx, main) : Offset(main, c.origin.dy),
  );

  /// Screen px the camera is past the document end on the main axis
  /// (negative / 0 within the bounds).
  double _overscroll(ViewportCamera c) =>
      (_mainOf(c.origin) - _mainOf(_clamp(c).origin)) * c.scale;

  /// Ends a pull: springs back to the bounds (paged mode at fit: the last
  /// page centred).
  void _springBack() {
    _pullRaw = 0;
    _pullAllowed = false;
    _pullPhase.value = PullToAddPhase.pulling;
    final token = ++_pullToken;
    // Paged mode at fit: back to the last page centred (as a page snap).
    final ViewportCamera target;
    if (!_vertical && zoom <= _pagedSnapMaxZoom) {
      final last = _layout.length - 1;
      _fitScale = _fitFor(last);
      target = _pageCamera(last);
    } else {
      target = _clamp(_camera);
    }
    unawaited(
      animateTo(
        target,
        duration: ViewportConstants.pullSpringBackDuration,
      ).whenComplete(() {
        if (!_disposed && token == _pullToken) {
          _pullPhase.value = PullToAddPhase.idle;
        }
      }),
    );
  }

  /// Fling / zoom snap / page snap.
  ///
  /// Held past the document end (6.11.7): returns true when the pull was at
  /// or past [ViewportConstants.pullToAddThreshold] and the finger was held
  /// (moving toward the end at most
  /// [ViewportConstants.pullToAddMaxReleaseVelocity]) — the camera then
  /// holds there ([PullToAddPhase.released]) and the caller adds the page
  /// and calls [endHeldPull] when done. Otherwise a pull springs back. A
  /// fling never pulls (it stops at the bound), so momentum alone never
  /// returns true.
  bool endGesture(Velocity velocity) {
    if (_disposed || !_gestureActive) return false;
    _gestureActive = false;
    _gestureBase = null;
    final pulling = _pullRaw > 0;
    final towardEnd = -_mainOf(velocity.pixelsPerSecond);
    final armed =
        pulling &&
        _pullPhase.value == PullToAddPhase.armed &&
        towardEnd <= ViewportConstants.pullToAddMaxReleaseVelocity;
    _pullAllowed = false;
    if (!_valid) {
      _pullRaw = 0;
      _pullPhase.value = PullToAddPhase.idle;
      _scheduleSettle();
      return false;
    }
    if (armed) {
      _pullRaw = 0;
      _pullToken++;
      _pullPhase.value = PullToAddPhase.released;
      _scheduleSettle();
      return true;
    }
    if (pulling) {
      _springBack();
      return false;
    }
    if (_axis == LayoutAxis.horizontal && zoom <= _pagedSnapMaxZoom) {
      _pageSnap(velocity);
      return false;
    }
    final z = zoom;
    if (_gestureScaled &&
        z != 1 &&
        (z - 1).abs() <= ViewportConstants.zoomSnapTolerance) {
      final focal = _lastFocal ?? _viewportSize.center(Offset.zero);
      unawaited(
        animateTo(
          _camera.zoomedAround(focal, _fitScale),
          duration: ViewportConstants.snapDuration,
        ),
      );
      return false;
    }
    if (velocity.pixelsPerSecond.distance >= _flingMinVelocity) {
      _startFling(velocity.pixelsPerSecond);
      return false;
    }
    _scheduleSettle();
    return false;
  }

  /// No fling (paged mode still snaps to the nearest page); a pull springs
  /// back without adding a page.
  void cancelGesture() {
    if (_disposed || !_gestureActive) return;
    _gestureActive = false;
    _gestureBase = null;
    if (_pullRaw > 0 && _valid) {
      _springBack();
      return;
    }
    _pullRaw = 0;
    _pullAllowed = false;
    if (_valid && _axis == LayoutAxis.horizontal && zoom <= _pagedSnapMaxZoom) {
      _pageSnap(Velocity.zero);
      return;
    }
    _scheduleSettle();
  }

  /// After a release that [endGesture] reported (6.11.7): springs back if
  /// the camera still holds past the end — the add failed or never ran.
  /// No-op once the new page arrived ([updatePages]) or a gesture took over.
  void endHeldPull() {
    if (_disposed || _gestureActive) return;
    if (_pullPhase.value != PullToAddPhase.released) return;
    if (!_valid) {
      _pullPhase.value = PullToAddPhase.idle;
      return;
    }
    _springBack();
  }

  /// Scrolls by [screenDelta] in the direction of a wheel delta
  /// (PointerScrollEvent.scrollDelta: positive dy shows what is below).
  void panBy(Offset screenDelta) {
    if (_disposed || !_valid || screenDelta == Offset.zero) return;
    _stopAnimation(scheduleSettle: false);
    _setCamera(_clamp(_camera.pannedBy(-screenDelta)));
    _scheduleSettle();
  }

  /// Wheel+ctrl, trackpad: scale × [factor] about [screenFocal].
  void zoomBy(double factor, Offset screenFocal) {
    if (_disposed || !_valid || factor == 1 || !(factor > 0)) return;
    _stopAnimation(scheduleSettle: false);
    final scale = CameraMath.clampScale(_camera.scale * factor, _fitScale);
    _setCamera(_clamp(_camera.zoomedAround(screenFocal, scale)));
    _scheduleSettle();
  }

  /// Called by InteractionHost when a tool interaction starts (6.6.2): stops animations,
  /// ends the settle wait now (settledScale = camera.scale, isInteracting = false), so
  /// the session's viewScale equals InkPageView's layout scale and ancestorScale is 1
  /// (contract 7.2.15 v1.1 viewScale). No-op when already settled.
  void settleNow() {
    if (_disposed) return;
    _stopAnimation(scheduleSettle: false);
    _settleTimer?.cancel();
    _settleTimer = null;
    _dropPull();
    _settledScale.value = _camera.scale;
    _isInteracting.value = false;
  }

  /// A stopped spring-back (6.11.7) must not leave the camera past the end.
  void _dropPull() {
    if (_pullPhase.value == PullToAddPhase.idle || _gestureActive) return;
    _pullToken++;
    _pullRaw = 0;
    _pullPhase.value = PullToAddPhase.idle;
    if (!_valid) return;
    final clamped = _clamp(_camera);
    if (clamped == _camera) return;
    _camera = clamped;
    _updateCurrentPage();
    notifyListeners();
  }

  // ---- programmatic ----

  Future<void> animateTo(
    ViewportCamera target, {
    Duration duration = ViewportConstants.jumpDuration,
    Curve curve = Curves.easeOutCubic,
  }) {
    // A held navigation drag wins over a programmatic move (e.g. the jump
    // after a page add landing mid-drag).
    if (_disposed || !_valid || _gestureActive) return Future<void>.value();
    _stopAnimation(scheduleSettle: false);
    final to = _clamp(target);
    if (to == _camera) {
      _scheduleSettle();
      return Future<void>.value();
    }
    if (duration <= Duration.zero) {
      _setCamera(to);
      _scheduleSettle();
      return Future<void>.value();
    }
    return _startAnimation(
      _TweenAnimation(from: _camera, to: to, duration: duration, curve: curve),
    );
  }

  /// Vertical: page top (rect.top − pageGap/2) at the current zoom.
  /// Horizontal: the page centred at its fit scale.
  Future<void> jumpToPage(int index, {bool animate = true}) {
    if (_disposed || !_valid) return Future<void>.value();
    final i = index.clamp(0, _layout.length - 1);
    final ViewportCamera target;
    if (_axis == LayoutAxis.horizontal) {
      _fitScale = _fitFor(i);
      target = _pageCamera(i);
    } else {
      target = _pageStartCamera(i, scale: _camera.scale);
    }
    return _moveTo(target, animate: animate);
  }

  /// Brings page [index] into view. Without [focusRectPt]: same as jumpToPage(index).
  /// [focusRectPt] (contract 7.2.17 v1.1): displayed page coordinates — pt of the note's
  /// Page.size, origin top-left, y down (same as core.Stroke points); used as is.
  /// With it: keeps the current zoom unless the rect does not fit (then zooms
  /// out to fit it with 24 px margin, never below fit width × minZoom), and pans so the
  /// rect is centred when it is not fully visible (no-op when already fully visible).
  Future<void> revealPageRect(
    int index, {
    Rect? focusRectPt,
    bool animate = true,
  }) {
    if (_disposed || !_valid) return Future<void>.value();
    if (focusRectPt == null) return jumpToPage(index, animate: animate);
    final i = index.clamp(0, _layout.length - 1);
    var base = _camera;
    if (_axis == LayoutAxis.horizontal && i != _computeCurrentPage()) {
      _fitScale = _fitFor(i);
      base = _pageCamera(i);
    }
    final target = _revealCamera(base, i, focusRectPt);
    if (target == _camera) return Future<void>.value();
    return _moveTo(target, animate: animate);
  }

  /// The camera that shows [focusRectPt] of page [i] starting from [base]:
  /// [base] itself when the rect is already fully visible, else the rect
  /// centred at [base]'s zoom (zoomed out when it does not fit — see
  /// [revealPageRect]).
  ViewportCamera _revealCamera(ViewportCamera base, int i, Rect focusRectPt) {
    final docRect = focusRectPt.shift(_layout.rectOf(i).topLeft);
    final visible = base.visibleDocRect(_viewportSize);
    if (_containsRect(visible, docRect)) return base;
    var scale = base.scale;
    final availW = _viewportSize.width - 2 * _revealMargin;
    final availH = _viewportSize.height - 2 * _revealMargin;
    if (docRect.width * scale > availW || docRect.height * scale > availH) {
      final fitW = docRect.width > 0 ? availW / docRect.width : scale;
      final fitH = docRect.height > 0 ? availH / docRect.height : scale;
      scale = math.max(
        math.min(scale, math.min(fitW, fitH)),
        _fitScale * ViewportConstants.minZoom,
      );
    }
    final origin =
        docRect.center -
        Offset(_viewportSize.width, _viewportSize.height) / (2 * scale);
    return ViewportCamera(scale: scale, origin: origin);
  }

  /// No-op if any part of the page is on screen; else [jumpToPage].
  Future<void> ensurePageVisible(int index) {
    if (_disposed || !_valid) return Future<void>.value();
    final i = index.clamp(0, _layout.length - 1);
    final visible = _camera.visibleDocRect(_viewportSize);
    if (visible.overlaps(_layout.rectOf(i))) return Future<void>.value();
    return jumpToPage(i);
  }

  /// Zoom 1 (fit width; paged mode: the current page centred).
  Future<void> zoomToFit() {
    if (_disposed || !_valid) return Future<void>.value();
    if (_axis == LayoutAxis.horizontal) {
      final i = _computeCurrentPage();
      _fitScale = _fitFor(i);
      return animateTo(_pageCamera(i));
    }
    return animateTo(
      _camera.zoomedAround(_viewportSize.center(Offset.zero), _fitScale),
    );
  }

  /// ×/÷ 1.25 about centre (a result within the snap tolerance of 1 becomes 1).
  Future<void> zoomStep({required bool zoomIn}) {
    if (_disposed || !_valid) return Future<void>.value();
    const step = ViewportConstants.zoomStep;
    var scale = CameraMath.clampScale(
      zoomIn ? _camera.scale * step : _camera.scale / step,
      _fitScale,
    );
    if ((scale / _fitScale - 1).abs() <= ViewportConstants.zoomSnapTolerance) {
      scale = _fitScale;
    }
    return animateTo(
      _camera.zoomedAround(_viewportSize.center(Offset.zero), scale),
    );
  }

  /// ±0.9 viewport along the main axis / next page in paged mode.
  Future<void> scrollByViewport(int direction) {
    if (_disposed || !_valid || direction == 0) return Future<void>.value();
    final dir = direction.sign;
    if (_axis == LayoutAxis.horizontal && zoom <= _pagedSnapMaxZoom) {
      return jumpToPage(_computeCurrentPage() + dir);
    }
    final vertical = _axis == LayoutAxis.vertical;
    final extent = vertical ? _viewportSize.height : _viewportSize.width;
    final delta = dir * extent * _scrollViewportFraction;
    return animateTo(
      _camera.pannedBy(vertical ? Offset(0, -delta) : Offset(-delta, 0)),
    );
  }

  void stopAnimation() => _stopAnimation(scheduleSettle: true);

  ViewportAnchor? captureAnchor() {
    final a = _captureInternal();
    if (a == null) return null;
    return ViewportAnchor(
      pageId: a.pageId,
      offsetInPage: a.offsetInPage,
      zoom: a.zoom,
    );
  }

  // ---- mapping ----

  ({int index, String pageId, Offset pagePoint})? hitPage(Offset screen) {
    if (!_valid) return null;
    final doc = _camera.screenToDoc(screen);
    final index = _layout.pageIndexAt(doc);
    if (index == null || index >= _pages.length) return null;
    return (
      index: index,
      pageId: _pages[index].id,
      pagePoint: doc - _layout.rectOf(index).topLeft,
    );
  }

  Offset pageToScreen(int pageIndex, Offset pagePoint) =>
      _camera.docToScreen(_layout.rectOf(pageIndex).topLeft + pagePoint);

  /// Even outside the page.
  Offset screenToPage(int pageIndex, Offset screen) =>
      _camera.screenToDoc(screen) - _layout.rectOf(pageIndex).topLeft;

  Rect pageRectOnScreen(int pageIndex) {
    final r = _layout.rectOf(pageIndex);
    final topLeft = _camera.docToScreen(r.topLeft);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      r.width * _camera.scale,
      r.height * _camera.scale,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    _animation = null;
    _completeAnimation();
    _ticker.dispose();
    _settledScale.dispose();
    _isInteracting.dispose();
    _currentPageIndex.dispose();
    _pullPhase.dispose();
    super.dispose();
  }

  // ---- internals ----

  bool get _vertical => _axis == LayoutAxis.vertical;
  double _mainOf(Offset p) => _vertical ? p.dy : p.dx;
  double _mainStart(Rect r) => _vertical ? r.top : r.left;
  double _mainEnd(Rect r) => _vertical ? r.bottom : r.right;

  static bool _sameShape(List<core.Page> a, List<core.Page> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].size != b[i].size) return false;
    }
    return true;
  }

  PageLayout _computeLayout() => PageLayout.compute(
    pageSizes: [for (final p in _pages) Size(p.size.width, p.size.height)],
    axis: _axis,
  );

  double _fitFor(int index) =>
      CameraMath.fitScale(_layout, _viewportSize, pageIndex: index);

  ViewportCamera _clamp(ViewportCamera c) =>
      CameraMath.clamp(c, _layout, _viewportSize, _fitScale);

  int _computeCurrentPage() {
    if (_layout.length == 0) return 0;
    final centre = _camera.visibleDocRect(_viewportSize).center;
    return _layout.pageIndexAt(centre) ?? _layout.nearestPageIndex(centre);
  }

  ({int index, String pageId, Offset offsetInPage, double zoom})?
  _captureInternal() {
    if (!_placed || !_valid || _pages.length != _layout.length) return null;
    final index = _computeCurrentPage();
    return (
      index: index,
      pageId: _pages[index].id,
      offsetInPage: _camera.origin - _layout.rectOf(index).topLeft,
      zoom: zoom,
    );
  }

  /// After a size, page or axis change: places the first camera, or brings
  /// [anchor] back (by page id, else the same index).
  void _relayout(
    ({int index, String pageId, Offset offsetInPage, double zoom})? anchor,
  ) {
    if (!_valid) {
      notifyListeners();
      return;
    }
    if (!_placed || anchor == null) {
      _placed = true;
      final pending = _pendingRestore;
      _pendingRestore = null;
      _place(
        _restoreCamera(
          pending?.anchor,
          pending?.initialPageId,
          pending?.focusRectPt,
        ),
        settle: true,
      );
      return;
    }
    var index = _pages.indexWhere((p) => p.id == anchor.pageId);
    if (index < 0) index = anchor.index.clamp(0, _layout.length - 1);
    _fitScale = _fitFor(index);
    // Paged mode, not zoomed in: the page stays centred (a rotation or a
    // page-list change never leaves it half off screen).
    final next = !_vertical && anchor.zoom <= _pagedSnapMaxZoom
        ? _pageCamera(index)
        : _clamp(
            ViewportCamera(
              scale: anchor.zoom * _fitScale,
              origin: _layout.rectOf(index).topLeft + anchor.offsetInPage,
            ),
          );
    if (next == _camera) {
      _updateCurrentPage();
      notifyListeners(); // the layout itself changed
    } else {
      _setCamera(next);
    }
    _scheduleSettle();
  }

  ViewportCamera _restoreCamera(
    ViewportAnchor? anchor,
    String? initialPageId, [
    Rect? focusRectPt,
  ]) {
    if (initialPageId != null) {
      final i = _pages.indexWhere((p) => p.id == initialPageId);
      if (i >= 0) {
        _fitScale = _fitFor(i);
        final start = _vertical
            ? _pageStartCamera(i, scale: _fitScale)
            : _pageCamera(i);
        if (focusRectPt == null) return start;
        return _clamp(_revealCamera(start, i, focusRectPt));
      }
    }
    if (anchor != null) {
      final i = _pages.indexWhere((p) => p.id == anchor.pageId);
      if (i >= 0) {
        _fitScale = _fitFor(i);
        return _clamp(
          ViewportCamera(
            scale: anchor.zoom * _fitScale,
            origin: _layout.rectOf(i).topLeft + anchor.offsetInPage,
          ),
        );
      }
    }
    _fitScale = _fitFor(0);
    return _vertical ? _pageStartCamera(0, scale: _fitScale) : _pageCamera(0);
  }

  /// Vertical: page top (rect.top − pageGap/2) at [scale], cross axis kept.
  /// Horizontal: page left likewise.
  ViewportCamera _pageStartCamera(int index, {required double scale}) {
    final r = _layout.rectOf(index);
    const half = ViewportConstants.pageGap / 2;
    final origin = _vertical
        ? Offset(_camera.origin.dx, r.top - half)
        : Offset(r.left - half, _camera.origin.dy);
    return _clamp(ViewportCamera(scale: scale, origin: origin));
  }

  /// Page [index] centred at its fit scale (paged mode).
  ViewportCamera _pageCamera(int index) {
    final scale = _fitFor(index);
    final centre = _layout.rectOf(index).center;
    final origin =
        centre -
        Offset(_viewportSize.width, _viewportSize.height) / (2 * scale);
    return CameraMath.clamp(
      ViewportCamera(scale: scale, origin: origin),
      _layout,
      _viewportSize,
      scale,
    );
  }

  static bool _containsRect(Rect outer, Rect inner) =>
      inner.left >= outer.left &&
      inner.top >= outer.top &&
      inner.right <= outer.right &&
      inner.bottom <= outer.bottom;

  Future<void> _moveTo(ViewportCamera target, {required bool animate}) {
    if (animate) return animateTo(target);
    _stopAnimation(scheduleSettle: false);
    _setCamera(_clamp(target));
    _scheduleSettle();
    return Future<void>.value();
  }

  /// Sets the camera without the interaction state (first display).
  void _place(ViewportCamera camera, {required bool settle}) {
    final changed = camera != _camera;
    _camera = camera;
    if (settle) {
      _settleTimer?.cancel();
      _settleTimer = null;
      _settledScale.value = camera.scale;
      _isInteracting.value = false;
    }
    _updateCurrentPage();
    if (changed || settle) notifyListeners();
  }

  void _setCamera(ViewportCamera camera) {
    if (camera == _camera) return;
    _camera = camera;
    _isInteracting.value = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    _updateCurrentPage();
    notifyListeners();
  }

  void _updateCurrentPage() {
    if (_layout.length == 0 || !_valid) return;
    _currentPageIndex.value = _computeCurrentPage();
  }

  /// Starts the settle wait when no gesture or animation is running.
  void _scheduleSettle() {
    if (_disposed || _gestureActive || _animation != null) return;
    _settleTimer?.cancel();
    _settleTimer = null;
    final needed =
        _isInteracting.value || !_sameScale(_settledScale.value, _camera.scale);
    if (!needed) return;
    _isInteracting.value = true;
    _settleTimer = Timer(ViewportConstants.settleDelay, _settle);
  }

  void _settle() {
    _settleTimer = null;
    if (_disposed || _gestureActive || _animation != null) return;
    if (!_sameScale(_settledScale.value, _camera.scale)) {
      _settledScale.value = _camera.scale;
    }
    _isInteracting.value = false;
  }

  static bool _sameScale(double a, double b) =>
      (a - b).abs() < a.abs() * _settleScaleTolerance;

  // ---- animations ----

  void _pageSnap(Velocity velocity) {
    final vx = _vertical
        ? velocity.pixelsPerSecond.dy
        : velocity.pixelsPerSecond.dx;
    int target;
    if (vx.abs() > ViewportConstants.pageSnapVelocity) {
      // Finger moving left (negative) → next page.
      target = _gestureStartPage + (vx < 0 ? 1 : -1);
    } else {
      target = _computeCurrentPage();
    }
    target = target.clamp(0, _layout.length - 1);
    _fitScale = _fitFor(target);
    unawaited(
      animateTo(
        _pageCamera(target),
        duration: ViewportConstants.pageSnapDuration,
      ),
    );
  }

  void _startFling(Offset velocity) {
    final s = _camera.scale;
    // Content follows the finger: origin×scale moves at −velocity.
    final sx = velocity.dx == 0
        ? null
        : ClampingScrollSimulation(
            position: _camera.origin.dx * s,
            velocity: -velocity.dx,
          );
    final sy = velocity.dy == 0
        ? null
        : ClampingScrollSimulation(
            position: _camera.origin.dy * s,
            velocity: -velocity.dy,
          );
    if (sx == null && sy == null) {
      _scheduleSettle();
      return;
    }
    unawaited(_startAnimation(_FlingAnimation(x: sx, y: sy)));
  }

  Future<void> _startAnimation(_CameraAnimation animation) {
    _animation = animation;
    final done = _animationDone = Completer<void>();
    _isInteracting.value = true;
    _settleTimer?.cancel();
    _settleTimer = null;
    if (_ticker.isActive) _ticker.stop();
    unawaited(_ticker.start());
    return done.future;
  }

  void _onTick(Duration elapsed) {
    final animation = _animation;
    if (animation == null || _disposed) return;
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final done = animation.apply(this, t);
    if (done) _stopAnimation(scheduleSettle: true);
  }

  void _stopAnimation({required bool scheduleSettle}) {
    if (_animation == null) return;
    _animation = null;
    if (_ticker.isActive) _ticker.stop();
    _completeAnimation();
    if (scheduleSettle) _scheduleSettle();
  }

  void _completeAnimation() {
    final done = _animationDone;
    _animationDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }
}

sealed class _CameraAnimation {
  /// Moves the camera to time [t] (s); true when finished.
  bool apply(ViewportController c, double t);
}

/// Zoom/pan between two cameras keeping their common fixed screen point
/// (a pure pan when the scales are equal).
final class _TweenAnimation extends _CameraAnimation {
  _TweenAnimation({
    required this.from,
    required this.to,
    required Duration duration,
    required this.curve,
  }) : _seconds = duration.inMicroseconds / Duration.microsecondsPerSecond {
    final inverseDiff = 1 / from.scale - 1 / to.scale;
    if (inverseDiff.abs() > 1e-12) {
      final fixed = (to.origin - from.origin) / inverseDiff;
      _fixedScreen = fixed;
      _fixedDoc = from.screenToDoc(fixed);
    }
  }

  final ViewportCamera from;
  final ViewportCamera to;
  final Curve curve;
  final double _seconds;
  Offset? _fixedScreen;
  Offset? _fixedDoc;

  @override
  bool apply(ViewportController c, double t) {
    if (t >= _seconds) {
      c._setCamera(to);
      return true;
    }
    final f = curve.transform((t / _seconds).clamp(0.0, 1.0));
    final scale = from.scale + (to.scale - from.scale) * f;
    final fixedScreen = _fixedScreen;
    final Offset origin;
    if (fixedScreen == null) {
      origin = Offset.lerp(from.origin, to.origin, f)!;
    } else {
      origin = _fixedDoc! - fixedScreen / scale;
    }
    c._setCamera(ViewportCamera(scale: scale, origin: origin));
    return false;
  }
}

/// Per-axis ClampingScrollSimulation; an axis that hits a bound stops.
final class _FlingAnimation extends _CameraAnimation {
  _FlingAnimation({required this.x, required this.y});
  ClampingScrollSimulation? x;
  ClampingScrollSimulation? y;

  @override
  bool apply(ViewportController c, double t) {
    final camera = c._camera;
    final s = camera.scale;
    final sx = x;
    final sy = y;
    final wantX = sx == null ? camera.origin.dx : sx.x(t) / s;
    final wantY = sy == null ? camera.origin.dy : sy.x(t) / s;
    final next = c._clamp(
      ViewportCamera(scale: s, origin: Offset(wantX, wantY)),
    );
    const eps = 1e-9;
    if (sx != null && ((next.origin.dx - wantX).abs() > eps || sx.isDone(t))) {
      x = null;
    }
    if (sy != null && ((next.origin.dy - wantY).abs() > eps || sy.isDone(t))) {
      y = null;
    }
    c._setCamera(next);
    return x == null && y == null;
  }
}
