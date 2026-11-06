// lib/src/render/laser_trail.dart — INTERNAL (m5-7/03-ink 6.6, T30).
//
// The laser pen (transientTrail): a fading trail on the overlay layer, never
// stored (K-9). Every trail point carries the InkClock time (µs) at which the
// session received it — never InkSample.timeUs (review S-8: the native event
// clock is not InkClock's).
//
//  * while the pen is down, a point older than laserFadeMs fades out over the
//    next laserFadeMs (a long circle never fills the screen);
//  * from the pen lift on, the whole remaining trail fades to 0 over
//    laserFadeMs, then the trail is removed;
//  * at most InkTuning.laserMaxTrails trails: a new one removes the oldest.
//
// Drawing: the centerline as a polyline, round caps and joins, twice — a glow
// (width × laserGlowWidthFactor, opacity laserGlowOpacity) under the core
// (opacity 1) — in InkTuning.laserArgb (CP-INK-7: never style.colorArgb). The
// opacity is grouped into InkTuning.laserFadeSteps levels: one path per run of
// segments with the same level (a bounded number of draw calls).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

import '../tuning.dart';

/// One laser trail: its points (page pt) with their InkClock times.
@internal
final class LaserTrail {
  LaserTrail._(this.width, this.fadeUs, this.startUs);

  /// style.width (pt) and style.laserFadeMs × 1000 (µs).
  final double width;
  final int fadeUs;

  /// InkClock µs of the pen down.
  final int startUs;

  final List<double> _xs = [], _ys = [];
  final List<int> _ts = [];

  /// The raw tail (+ predicted samples) after the stable points while written: the
  /// time of the last update.
  List<ui.Offset> _tail = const [];
  int _tailUs = 0;

  /// Stable points received so far (the session appends the new ones).
  int _received = 0;

  /// InkClock µs of the pen lift; null while written.
  int? endUs;

  bool get isWritten => endUs == null;

  /// The points drawn now (stable points + tail).
  int get length => _xs.length + _tail.length;

  /// Opacity of point [i] at [nowUs] (before the level grouping), in [0, 1].
  double opacityAt(int i, int nowUs) {
    final t = i < _ts.length ? _ts[i] : _tailUs;
    return _pointOpacity(t, nowUs) * _liftFactor(nowUs);
  }

  /// While written: 1 up to fadeUs old, then down to 0 at 2 · fadeUs.
  double _pointOpacity(int t, int nowUs) {
    final age = nowUs - t;
    if (age <= fadeUs) return 1;
    return (1 - (age - fadeUs) / fadeUs).clamp(0.0, 1.0);
  }

  /// After the lift: from 1 down to 0 over fadeUs.
  double _liftFactor(int nowUs) {
    final end = endUs;
    if (end == null) return 1;
    return (1 - (nowUs - end) / fadeUs).clamp(0.0, 1.0);
  }

  ui.Offset _pointAt(int i) =>
      i < _xs.length ? ui.Offset(_xs[i], _ys[i]) : _tail[i - _xs.length];

  /// Gone for good: lifted at least fadeUs ago.
  bool isGone(int nowUs) {
    final end = endUs;
    return end != null && nowUs - end >= fadeUs;
  }

  /// Drops the leading points that are fully faded (opacity 0 now and later).
  void _dropFaded(int nowUs) {
    var k = 0;
    // keep one faded point before the first visible one (its segment fades out)
    while (k + 1 < _ts.length && _pointOpacity(_ts[k + 1], nowUs) <= 0) {
      k++;
    }
    if (k == 0) return;
    // (_received counts the session's stable points taken, not the points kept)
    _xs.removeRange(0, k);
    _ys.removeRange(0, k);
    _ts.removeRange(0, k);
  }
}

/// The laser trails of one page controller (6.6-2).
@internal
final class LaserTrails {
  LaserTrails({this.maxTrails = InkTuning.laserMaxTrails});

  final int maxTrails;
  final List<LaserTrail> _trails = [];

  List<LaserTrail> get trails => List.unmodifiable(_trails);
  bool get isEmpty => _trails.isEmpty;

  /// A new trail (a laser pen down at [nowUs]); the oldest goes when there would be
  /// more than [maxTrails].
  LaserTrail start({
    required double width,
    required int fadeMs,
    required int nowUs,
  }) {
    final t = LaserTrail._(width, fadeMs * 1000, nowUs);
    _trails.add(t);
    while (_trails.length > maxTrails) {
      _trails.removeAt(0);
    }
    return t;
  }

  /// The session's points now: [stable] is the append-only stable centerline (the new
  /// entries get [nowUs]), [tail] the raw tail after it.
  void update(
    LaserTrail t,
    List<ui.Offset> stable,
    List<ui.Offset> tail,
    int nowUs,
  ) {
    for (var i = t._received; i < stable.length; i++) {
      t._xs.add(stable[i].dx);
      t._ys.add(stable[i].dy);
      t._ts.add(nowUs);
    }
    t
      .._received = stable.length
      .._tail = List.of(tail)
      .._tailUs = nowUs;
  }

  /// The pen lifted at [nowUs]: the tail becomes points of that time, the fade starts.
  void finish(LaserTrail t, int nowUs) {
    for (final p in t._tail) {
      t._xs.add(p.dx);
      t._ys.add(p.dy);
      t._ts.add(nowUs);
    }
    t
      .._tail = const []
      ..endUs = nowUs;
  }

  /// Cancel: the trail disappears at once.
  void remove(LaserTrail t) => _trails.remove(t);

  /// Removes the trails that are gone and the faded heads; true while something is
  /// left to draw.
  bool prune(int nowUs) {
    _trails.removeWhere((t) => t.isGone(nowUs));
    for (final t in _trails) {
      t._dropFaded(nowUs);
    }
    return _trails.isNotEmpty;
  }

  /// Prunes, then draws every trail at [nowUs]; true while something is left.
  bool paint(ui.Canvas canvas, int nowUs) {
    if (!prune(nowUs)) return false;
    for (final t in _trails) {
      _paintTrail(canvas, t, nowUs);
    }
    return true;
  }
}

/// The opacity level of [opacity]: ⌈opacity · laserFadeSteps⌉ / laserFadeSteps (0 → 0).
@internal
double laserLevelOf(double opacity) {
  if (!(opacity > 0)) return 0;
  const steps = InkTuning.laserFadeSteps;
  return math.min(steps, (opacity * steps).ceil()) / steps;
}

void _paintTrail(ui.Canvas canvas, LaserTrail t, int nowUs) {
  final n = t.length;
  if (n == 0) return;
  // runs of segments with one level (the level of the older end)
  final runs = <(double, ui.Path)>[];
  if (n == 1) {
    final level = laserLevelOf(t.opacityAt(0, nowUs));
    if (level <= 0) return;
    final p = t._pointAt(0);
    runs.add((
      level,
      ui.Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx, p.dy),
    ));
  }
  double? runLevel;
  ui.Path? path;
  for (var i = 0; i + 1 < n; i++) {
    final level = laserLevelOf(t.opacityAt(i, nowUs));
    if (level <= 0) {
      runLevel = null;
      path = null;
      continue;
    }
    final a = t._pointAt(i), b = t._pointAt(i + 1);
    if (level != runLevel || path == null) {
      path = ui.Path()..moveTo(a.dx, a.dy);
      runLevel = level;
      runs.add((level, path));
    }
    path.lineTo(b.dx, b.dy);
  }
  paintLaserRuns(canvas, runs, t.width);
}

/// Draws [runs] (level, centerline path) as the laser: every glow first, then every
/// core (6.6-3).
@internal
void paintLaserRuns(
  ui.Canvas canvas,
  List<(double, ui.Path)> runs,
  double width,
) {
  final color = const ui.Color(InkTuning.laserArgb);
  final glow = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeWidth = width * InkTuning.laserGlowWidthFactor
    ..isAntiAlias = true;
  for (final (level, path) in runs) {
    glow.color = color.withValues(alpha: InkTuning.laserGlowOpacity * level);
    canvas.drawPath(path, glow);
  }
  final core = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round
    ..strokeWidth = width
    ..isAntiAlias = true;
  for (final (level, path) in runs) {
    core.color = color.withValues(alpha: level);
    canvas.drawPath(path, core);
  }
}

/// The still laser of the pen preview (6.2 'pen preview'): [points] at full opacity,
/// no fade, no timer.
@internal
void paintLaserStill(ui.Canvas canvas, List<ui.Offset> points, double width) {
  if (points.isEmpty) return;
  final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) path.lineTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  paintLaserRuns(canvas, [(1.0, path)], width);
}
