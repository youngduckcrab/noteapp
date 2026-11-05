// lib/src/stroke/stroke_builder.dart — INTERNAL (not exported; INK tests import src/).
// 03-ink 4.4, pipeline 6.3–6.7.
//
// add(sample), per accepted sample:
//   6.3  time going backwards → previous + 1 µs; a duplicate (closer than
//        0.15 screen px and < 4 ms later) only updates the pressure
//   6.4  PressureDetector.observe (pending / real / simulated)
//   6.5  simulated pressure + smoothed screen speed (raw positions)
//   6.6  real pressure smoothing; One Euro filter → the stable (filtered) point
//   6.7  K1–K4 width factor of the point
// Live geometry (6.12 R5): the stable points with the start taper (K5 on the
// arc length so far) + a raw tail to the last raw position. Fill pens freeze
// every liveChunkPoints points into frozenPath (append-only; frozen only once
// the pressure source is decided, so the pending → real recompute of 6.4
// rule 6 never touches a frozen chunk); the open chunk + tail is tailPath.
// The highlighter keeps a centerline polyline (alwaysStraight: start →
// current position, axis snapped).
//
// finish(): F1 raw end point → F3 hooks → F4 dot → F6 straightening
// (highlighter) → F2 subdivision → F5 taper → F8 interleaved data (K6
// widthQ) → F7 simplification. F3 runs before F2 so its "≤ 4 points" counts
// samples.
//
// Rollover (6.7 F8): a sample more than strokeRolloverMs after the first
// sample of the current part ends that part at the previous sample b (no end
// taper / hook) and starts the next part at b (same filter / pressure state,
// no start taper / hook, t from b, createdAt + ⌊t_b⌋). The finished parts
// wait in [rolledOver]; the live geometry runs on across parts.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:note_core/note_core.dart' as core;

import '../input/ink_sample.dart';
import '../input/one_euro_filter.dart';
import '../input/predictor.dart';
import '../input/pressure_capability.dart';
import '../input/pressure_detector.dart';
import '../input/pressure_mode.dart';
import '../input/simulated_pressure.dart';
import '../model/ink_layer.dart';
import '../model/ink_points.dart';
import '../pen/style_ink.dart';
import '../render/sessions.dart';
import '../tuning.dart';
import 'centerline.dart';
import 'simplify.dart';
import 'straighten.dart';
import 'stroke_meta.dart';
import 'taper.dart';
import 'width_factor.dart';

/// Finalized stroke data, before CORE quantization (6.7 F8).
final class FinishedStroke {
  FinishedStroke({
    required this.style,
    required this.data,
    required this.hasTilt,
    required this.hasAzimuth,
    required this.startTimeUs,
    required this.pressureSource,
    required this.meta,
    this.createdAtOffsetMs = 0,
  });

  /// normalized
  final core.StrokeStyle style;

  /// interleaved stride 6 [x, y, widthQ, tilt, azimuth, t], t = ms since pen down
  final Float32List data;
  final bool hasTilt;
  final bool hasAzimuth;

  /// first sample's timeUs
  final int startTimeUs;
  final PressureSource pressureSource;
  final InkStrokeMeta meta;

  /// createdAt − pen-down millis: 0, or Σ⌊t_b⌋ for a part after a rollover
  /// (6.7 F8); meta.recordingOffsetMs already includes it.
  final int createdAtOffsetMs;

  int get pointCount => data.length ~/ core.StrokePoints.stride;
}

/// Per stable point inputs kept for the pending → real recompute (6.4 rule 6).
final class _PointInput {
  _PointInput(this.simulated, this.speed, this.tilt);
  final double simulated;
  final double speed;
  final double tilt;
}

/// One pressure value fed to the real-pressure smoother while pending;
/// [point] = index of the stable point it produced (null: a merged duplicate
/// or a point of an earlier part).
final class _PressureEvent {
  _PressureEvent(this.pressure, this.timeUs, this.point);
  final double? pressure;
  final int timeUs;
  final int? point;
}

final class StrokeBuilder {
  StrokeBuilder({
    required core.StrokeStyle style,
    required double viewScale,
    required PressureDetector pressure,
    InkStrokeMeta meta = const InkStrokeMeta(),
    InkPredictor predictor = const NoopPredictor(),
  }) : this._(style.normalized(), viewScale, pressure, meta, predictor);

  StrokeBuilder._(
    this._style,
    this._viewScale,
    this._pressure,
    this._meta,
    this._predictor,
  ) : _highlighter = _style.profile.layer == InkLayer.highlighter,
      _filter = OneEuroFilter(
        smoothing: _style.smoothing,
        viewScale: _viewScale,
      ),
      _sim = SimulatedPressure(viewScale: _viewScale),
      _live = newLiveStrokeGeometry(_style),
      _recording = _pressure.source == PressureSource.pending;

  final core.StrokeStyle _style;
  final double _viewScale;
  final PressureDetector _pressure;
  final InkPredictor _predictor;
  final bool _highlighter;
  final OneEuroFilter _filter;
  final SimulatedPressure _sim;
  final RealPressureSmoother _real = RealPressureSmoother();
  final LiveStrokeGeometry _live;

  // --- the current part (a new one after each rollover) ---
  InkStrokeMeta _meta;
  int _createdAtOffsetMs = 0;
  int _partStartUs = 0;
  bool _continuation = false;
  List<InkSample> _raw = [];
  List<CenterPoint> _pts = [];
  List<_PointInput> _inputs = [];
  int _partLiveStart = 0;

  // --- whole session ---
  final List<FinishedStroke> _rolledOver = [];
  final List<_PressureEvent> _events = [];
  bool _recording;
  int _rawCount = 0;
  int? _lastTimeUs;
  Offset? _firstPosition;

  // live centerline (session wide): positions, factors (K1–K4), arc length
  final List<double> _liveX = [];
  final List<double> _liveY = [];
  final List<double> _liveF = [];
  final List<double> _liveS = [];
  int _frozenChunks = 0;
  double _minX = double.infinity, _minY = double.infinity;
  double _maxX = double.negativeInfinity, _maxY = double.negativeInfinity;
  double _maxRadius = 0;

  core.StrokeStyle get style => _style;
  double get viewScale => _viewScale;

  /// Accepted samples so far (duplicates merged away), all parts.
  int get rawSampleCount => _rawCount;

  /// Stable (filtered) points so far, all parts.
  int get stablePointCount => _liveX.length;
  PressureSource get pressureSource => _pressure.source;
  LiveStrokeGeometry get live => _live;

  /// Parts finished by a rollover (6.7 F8), oldest first; the part still
  /// being drawn comes from finish().
  List<FinishedStroke> get rolledOver => UnmodifiableListView(_rolledOver);

  // --- add ---------------------------------------------------------------------

  /// PointerDown and every PointerMove (including coalesced ones). Pipeline: 6.3–6.7.
  void add(InkSample sample) {
    var s = sample;
    final lastUs = _lastTimeUs;
    if (lastUs != null && s.timeUs < lastUs) {
      // 6.3 (1): time going backwards → previous + 1 µs
      s = s.copyWith(timeUs: lastUs + 1);
    }
    _lastTimeUs = s.timeUs;
    final pn = s.normalizedPressure;
    if (_raw.isNotEmpty && isDuplicateSample(_raw.last, s, _viewScale)) {
      _merge(s, pn);
      return;
    }
    if (_raw.isNotEmpty &&
        (s.timeUs - _partStartUs) / 1000 > InkTuning.strokeRolloverMs) {
      _rollover();
    }
    if (_raw.isEmpty) _partStartUs = s.timeUs;
    _firstPosition ??= s.position;
    final changed = _pressure.observe(pn);
    final realValue = pn != null ? _real.add(pn, s.timeUs) : _real.value;
    final simulated = _sim.add(s.position, s.timeUs);
    final speed = _sim.smoothedSpeed ?? 0;
    final filtered = _filter.filter(s.position, s.timeUs);
    final tilt = _isStylus(s.kind) ? s.tilt : 0.0;
    final input = _PointInput(simulated, speed, tilt);
    final point = CenterPoint(
      filtered.dx,
      filtered.dy,
      factor: _factorOf(input, realValue),
      tilt: tilt,
      azimuth: normalizeAngle(s.orientation),
      t: (s.timeUs - _partStartUs) / 1000,
    );
    if (_recording) {
      _events.add(_PressureEvent(pn, s.timeUs, _pts.length));
    }
    _raw.add(s);
    _pts.add(point);
    _inputs.add(input);
    _rawCount++;
    _liveAdd(point);
    if (changed) _decided();
    _updateLive();
  }

  /// 6.3 (2): a duplicate keeps the previous position; only the pressure is updated.
  void _merge(InkSample s, double? pn) {
    final prev = _raw.last;
    if (s.pressure != null) {
      _raw[_raw.length - 1] = InkSample(
        position: prev.position,
        timeUs: prev.timeUs,
        kind: prev.kind,
        pressure: s.pressure,
        pressureMin: s.pressureMin,
        pressureMax: s.pressureMax,
        tilt: prev.tilt,
        orientation: prev.orientation,
      );
    }
    final changed = _pressure.observe(pn);
    if (pn != null) _real.add(pn, s.timeUs);
    if (_recording) _events.add(_PressureEvent(pn, s.timeUs, null));
    if (changed) {
      _decided();
      _updateLive();
    }
  }

  /// K1–K4 with the current source (pending / simulated → simulated pressure).
  double _factorOf(_PointInput input, double? realValue) {
    final real = _pressure.source == PressureSource.real;
    return widthFactor(
      style: _style,
      pressure: real
          ? bakedPressure(_style, realValue ?? 0.5, real: true)
          : input.simulated,
      realPressure: real,
      speed: input.speed,
      tilt: input.tilt,
    );
  }

  /// The detector decided. pending → real: every point of the current part is
  /// recomputed with real pressure, replaying the smoother from the start
  /// (6.4 rule 6). No chunk is frozen yet (freezing waits for the decision).
  void _decided() {
    if (!_recording) return;
    _recording = false;
    if (_pressure.source == PressureSource.real) {
      final smoother = RealPressureSmoother();
      for (final e in _events) {
        final p = e.pressure;
        final v = p != null ? smoother.add(p, e.timeUs) : smoother.value;
        final j = e.point;
        if (j == null) continue;
        final f = _factorOf(_inputs[j], v);
        _pts[j].factor = f;
        _liveF[_partLiveStart + j] = f;
      }
      _resetBounds();
    }
    _events.clear();
  }

  // --- rollover (6.7 F8) -----------------------------------------------------------

  void _rollover() {
    final b = _raw.last;
    final last = _pts.last;
    final joint = CenterPoint(
      b.position.dx,
      b.position.dy,
      factor: last.factor,
      tilt: last.tilt,
      azimuth: last.azimuth,
      t: 0,
    );
    final jointInput = _inputs.last;
    _rolledOver.add(_finishPart(end: false));
    final tb = ((b.timeUs - _partStartUs) / 1000).floor();
    _createdAtOffsetMs += tb;
    final offset = _meta.recordingOffsetMs;
    _meta = InkStrokeMeta(
      recordingId: _meta.recordingId,
      recordingOffsetMs: offset == null ? null : offset + tb,
    );
    _partStartUs = b.timeUs;
    _continuation = true;
    _raw = [b];
    _pts = [joint];
    _inputs = [jointInput];
    // the live point of b stays as it is (filtered); the parts join at raw b
    _partLiveStart = _liveX.length - 1;
    if (_recording) {
      // events of the finished part no longer point at stable points
      final kept = [
        for (final e in _events) _PressureEvent(e.pressure, e.timeUs, null),
      ];
      _events
        ..clear()
        ..addAll(kept);
    }
  }

  // --- finish ------------------------------------------------------------------

  /// Finalizes (6.7 F1–F8). [last] = PointerUp sample (its pressure is ignored). null if empty.
  FinishedStroke? finish({InkSample? last}) {
    if (last != null && (_raw.isEmpty || last.position != _raw.last.position)) {
      add(
        InkSample(
          position: last.position,
          timeUs: last.timeUs,
          kind: last.kind,
          tilt: last.tilt,
          orientation: last.orientation,
        ),
      );
    }
    if (_raw.isEmpty) return null;
    _pressure.finish();
    return _finishPart(end: true);
  }

  FinishedStroke _finishPart({required bool end}) {
    final start = !_continuation;
    final width = _style.width;
    final source = _pressure.source == PressureSource.pending
        ? PressureSource.simulated
        : _pressure.source;

    // F1: the last raw position is the end point (no filter lag)
    final rawLast = _raw.last;
    final pts = [for (final p in _pts) p.copy()];
    final tail = pts.last;
    if (rawLast.position != tail.position) {
      pts.add(
        CenterPoint(
          rawLast.position.dx,
          rawLast.position.dy,
          factor: tail.factor,
          tilt: tail.tilt,
          azimuth: tail.azimuth,
          t: (rawLast.timeUs - _partStartUs) / 1000,
        ),
      );
    }
    // F3
    var line = removeHooks(pts, width: width, start: start, end: end);
    if (isDotStroke(line, width)) {
      // F4: mean sample position, the widest factor, t = 0
      line = [
        dotOf([
          for (var i = 0; i < _raw.length; i++)
            CenterPoint(
              _raw[i].position.dx,
              _raw[i].position.dy,
              factor: _pts[i].factor,
              tilt: _pts[i].tilt,
              azimuth: _pts[i].azimuth,
            ),
        ]),
      ];
    } else {
      var straight = false;
      if (_highlighter) {
        // F6
        final s = straighten(
          line,
          mode: _style.highlighterStraightening,
          width: width,
        );
        straight = !identical(s, line);
        line = s;
      }
      // F2
      if (!straight) line = subdivide(line, maxSegmentFor(width));
      // F5
      applyTaper(
        line,
        profile: _style.profile,
        width: width,
        start: start,
        end: end,
      );
    }

    // F8
    var hasTilt = false, hasAzimuth = false;
    for (final s in _raw) {
      if (_isStylus(s.kind) && s.tilt.abs() > InkTuning.tiltPresentRad) {
        hasTilt = true;
      }
      if (s.orientation.abs() > InkTuning.azimuthPresentRad) {
        hasAzimuth = true;
      }
    }
    const stride = core.StrokePoints.stride;
    final data = Float32List(line.length * stride);
    for (var i = 0; i < line.length; i++) {
      final p = line[i];
      final o = i * stride;
      data[o] = p.x;
      data[o + 1] = p.y;
      data[o + 2] = widthQForFactor(p.factor, highlighter: _highlighter);
      data[o + 3] = hasTilt ? p.tilt : 0;
      data[o + 4] = hasAzimuth ? p.azimuth : 0;
      data[o + 5] = p.t
          .clamp(0, InkTuning.strokeRolloverMs.toDouble())
          .toDouble();
    }
    return FinishedStroke(
      style: _style,
      // F7
      data: simplifyStrokeData(data),
      hasTilt: hasTilt,
      hasAzimuth: hasAzimuth,
      startTimeUs: _partStartUs,
      pressureSource: source,
      meta: _meta,
      createdAtOffsetMs: _createdAtOffsetMs,
    );
  }

  // --- live geometry (6.12 R5) ---------------------------------------------------

  void _liveAdd(CenterPoint p) {
    final n = _liveX.length;
    var s = 0.0;
    if (n > 0) {
      final dx = p.x - _liveX[n - 1], dy = p.y - _liveY[n - 1];
      s = _liveS[n - 1] + math.sqrt(dx * dx + dy * dy);
    }
    _liveX.add(p.x);
    _liveY.add(p.y);
    _liveF.add(p.factor);
    _liveS.add(s);
    liveAddStable(_live, Offset(p.x, p.y), tiltK: tiltK(p.tilt));
    _include(p.x, p.y, _liveWidthQ(n));
  }

  /// widthQ of live point [i]: K6 of f × the live start taper (K5 on the arc
  /// length so far, Ls = taperStart · width; the end taper waits for finish).
  double _liveWidthQ(int i) {
    if (_highlighter) return core.kNominalWidthQ;
    final profile = _style.profile;
    var f = _liveF[i];
    if (profile.taperStart > 0) {
      final ts = startTaper(_liveS[i], profile.taperStart * _style.width);
      f *= profile.taperMinFactor + (1 - profile.taperMinFactor) * ts;
    }
    return widthQForFactor(f, highlighter: false);
  }

  void _include(double x, double y, double widthQ) {
    if (x < _minX) _minX = x;
    if (x > _maxX) _maxX = x;
    if (y < _minY) _minY = y;
    if (y > _maxY) _maxY = y;
    final r = _highlighter
        ? _style.width / 2 * math.sqrt2
        : math.max(InkTuning.minRadiusPt, 2 * _style.width * widthQ);
    if (r > _maxRadius) _maxRadius = r;
  }

  void _resetBounds() {
    _minX = _minY = double.infinity;
    _maxX = _maxY = double.negativeInfinity;
    _maxRadius = 0;
    for (var i = 0; i < _liveX.length; i++) {
      _include(_liveX[i], _liveY[i], _liveWidthQ(i));
    }
  }

  Rect _bounds() => Rect.fromLTRB(
    _minX - _maxRadius,
    _minY - _maxRadius,
    _maxX + _maxRadius,
    _maxY + _maxRadius,
  );

  void _updateLive() {
    final n = _liveX.length;
    if (n == 0) return;
    final rawLast = _raw.last.position;
    final tail = <Offset>[];
    final dx = rawLast.dx - _liveX[n - 1], dy = rawLast.dy - _liveY[n - 1];
    if (math.sqrt(dx * dx + dy * dy) > InkTuning.rawTailMinDistancePt) {
      tail.add(rawLast);
    }
    for (final p in _predictor.predict(
      UnmodifiableListView(_raw),
      nowUs: _raw.last.timeUs,
    )) {
      tail.add(p.position);
    }
    final q = _liveWidthQ(n - 1);
    for (final t in tail) {
      _include(t.dx, t.dy, q);
    }

    if (_highlighter) {
      final straight =
          _style.highlighterStraightening ==
              HighlighterStraightening.alwaysStraight
          ? straightLine(_firstPosition!, rawLast)
          : null;
      if (straight != null) {
        _include(straight.$2.dx, straight.$2.dy, q);
      }
      liveSetOpen(
        _live,
        tail: tail,
        open: null,
        straight: straight,
        bounds: _bounds(),
      );
      return;
    }

    // freeze complete chunks once the pressure source is decided
    const chunk = InkTuning.liveChunkPoints;
    if (_pressure.source != PressureSource.pending) {
      while (n >= (_frozenChunks + 1) * chunk + 1) {
        final from = _frozenChunks * chunk;
        liveFreezeChunk(
          _live,
          _livePointsData(from, from + chunk + 1, const []),
        );
        _frozenChunks++;
      }
    }
    liveSetOpen(
      _live,
      tail: tail,
      open: _livePointsData(math.min(_frozenChunks * chunk, n - 1), n, tail),
      straight: null,
      bounds: _bounds(),
    );
  }

  /// Live points [from, to) + [tail] as interleaved InkPoints (widthQ = live).
  InkPoints _livePointsData(int from, int to, List<Offset> tail) {
    const stride = core.StrokePoints.stride;
    final data = Float32List((to - from + tail.length) * stride);
    var o = 0;
    for (var i = from; i < to; i++) {
      data[o] = _liveX[i];
      data[o + 1] = _liveY[i];
      data[o + 2] = _liveWidthQ(i);
      o += stride;
    }
    final q = _liveWidthQ(to - 1);
    for (final t in tail) {
      data[o] = t.dx;
      data[o + 1] = t.dy;
      data[o + 2] = q;
      o += stride;
    }
    return InkPoints.fromRaw(data);
  }

  static bool _isStylus(InkPointerKind kind) =>
      kind == InkPointerKind.stylus || kind == InkPointerKind.invertedStylus;
}

/// Offline equivalent of add(...) for every sample followed by finish(). Deterministic.
FinishedStroke? buildStroke(
  List<InkSample> samples, {
  required core.StrokeStyle style,
  required double viewScale,
  PressureMode mode = PressureMode.auto,
  PressureCapability prior = PressureCapability.unknown,
}) {
  if (samples.isEmpty) return null;
  final builder = StrokeBuilder(
    style: style,
    viewScale: viewScale,
    pressure: PressureDetector(
      kind: samples.first.kind,
      mode: mode,
      prior: prior,
    ),
  );
  for (final s in samples) {
    builder.add(s);
  }
  return builder.finish();
}
