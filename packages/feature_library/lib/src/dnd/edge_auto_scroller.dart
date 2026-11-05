// lib/src/dnd/edge_auto_scroller.dart — 05-library 6.10.4: scrolls a list
// while a drag pointer is near (or past) its top / bottom edge.
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;
import 'package:material_ui/material_ui.dart'
    show Offset, Rect, ScrollController;

import '../ui/layout/library_metrics.dart';

final class EdgeAutoScroller {
  EdgeAutoScroller({
    required this.controller,
    required TickerProvider vsync,
    this.zone = LibraryMetrics.dragAutoScrollZone,
    this.maxSpeed = LibraryMetrics.dragAutoScrollMaxSpeed,
  }) {
    _ticker = vsync.createTicker(_tick);
  }

  final ScrollController controller;

  /// Px from the viewport edge.
  final double zone;

  /// Px/s.
  final double maxSpeed;

  late final Ticker _ticker;
  double _velocity = 0;
  Duration _last = Duration.zero;

  /// Current speed (px/s, negative = up); 0 when stopped.
  double get velocity => _velocity;
  bool get isScrolling => _ticker.isActive;

  /// [viewport] = global rect of the scroll view. Starts/updates/stops the
  /// ticker.
  void update(Offset globalPointer, Rect viewport) {
    final v = velocityFor(
      globalPointer.dy,
      viewport,
      zone: zone,
      maxSpeed: maxSpeed,
    );
    if (v == 0 || !_canScroll(v)) {
      stop();
      return;
    }
    _velocity = v;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void stop() {
    _velocity = 0;
    if (_ticker.isActive) _ticker.stop();
  }

  void dispose() => _ticker.dispose();

  bool _canScroll(double v) {
    if (!controller.hasClients) return false;
    final p = controller.position;
    if (!p.hasContentDimensions || !p.hasPixels) return false;
    return v < 0 ? p.pixels > p.minScrollExtent : p.pixels < p.maxScrollExtent;
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    if (!_canScroll(_velocity)) {
      stop();
      return;
    }
    final p = controller.position;
    final next = (p.pixels + _velocity * dt).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (next != p.pixels) controller.jumpTo(next);
    if (!_canScroll(_velocity)) stop();
  }

  /// Pure speed function (unit-tested): negative = up. Inside the viewport,
  /// d = distance to the nearer edge: d < zone → maxSpeed × (zone − d) / zone
  /// toward that edge, else 0. Above / below the viewport → ∓maxSpeed.
  static double velocityFor(
    double pointerY,
    Rect viewport, {
    double zone = LibraryMetrics.dragAutoScrollZone,
    double maxSpeed = LibraryMetrics.dragAutoScrollMaxSpeed,
  }) {
    if (pointerY < viewport.top) return -maxSpeed;
    if (pointerY > viewport.bottom) return maxSpeed;
    final toTop = pointerY - viewport.top;
    final toBottom = viewport.bottom - pointerY;
    if (toTop <= toBottom) {
      return toTop < zone ? -maxSpeed * (zone - toTop) / zone : 0;
    }
    return toBottom < zone ? maxSpeed * (zone - toBottom) / zone : 0;
  }
}
