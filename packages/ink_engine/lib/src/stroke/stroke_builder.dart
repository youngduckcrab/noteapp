// lib/src/stroke/stroke_builder.dart — INTERNAL (not exported; INK tests import src/).
// 03-ink 4.4.
//
// Foundation step B3 (03-ink 4.15): samples are kept as they come — no
// smoothing, subdivision, hook removal or taper; every point gets
// widthQ = kNominalWidthQ, t = ms since the first sample. The pipeline of
// 6.3–6.7 replaces the bodies in INK T05 / T06 (signatures unchanged).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:note_core/note_core.dart' as core;

import '../input/ink_sample.dart';
import '../input/predictor.dart';
import '../input/pressure_capability.dart';
import '../input/pressure_detector.dart';
import '../input/pressure_mode.dart';
import '../model/ink_layer.dart';
import '../pen/style_ink.dart';
import '../render/sessions.dart';
import '../tuning.dart';
import 'stroke_meta.dart';

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

  int get pointCount => data.length ~/ core.StrokePoints.stride;
}

final class StrokeBuilder {
  StrokeBuilder({
    required core.StrokeStyle style,
    required this._viewScale,
    required this._pressure,
    this._meta = const InkStrokeMeta(),
    InkPredictor predictor = const NoopPredictor(),
  }) : _style = style.normalized(),
       _live = newLiveStrokeGeometry(
         polyline: style.profile.layer == InkLayer.highlighter,
       );

  final core.StrokeStyle _style;
  final double _viewScale;
  final PressureDetector _pressure;
  final InkStrokeMeta _meta;
  final LiveStrokeGeometry _live;
  final List<InkSample> _samples = [];

  core.StrokeStyle get style => _style;
  double get viewScale => _viewScale;
  int get rawSampleCount => _samples.length;
  int get stablePointCount => _samples.length;
  PressureSource get pressureSource => _pressure.source;
  LiveStrokeGeometry get live => _live;

  /// PointerDown and every PointerMove (including coalesced ones). Pipeline: 6.3–6.7.
  void add(InkSample sample) {
    var s = sample;
    if (_samples.isNotEmpty && s.timeUs < _samples.last.timeUs) {
      // 6.3 (1): time going backwards → previous + 1 µs
      s = s.copyWith(timeUs: _samples.last.timeUs + 1);
    }
    _pressure.observe(s.normalizedPressure);
    _samples.add(s);
    liveAppend(_live, s.position);
  }

  /// Finalizes (6.7 F1–F8). [last] = PointerUp sample (its pressure is ignored). null if empty.
  FinishedStroke? finish({InkSample? last}) {
    if (last != null &&
        (_samples.isEmpty || last.position != _samples.last.position)) {
      add(last.copyWith(pressure: null));
    }
    if (_samples.isEmpty) return null;
    final source = _pressure.finish();
    final n = math.min(_samples.length, core.StrokePoints.maxLength);
    const stride = core.StrokePoints.stride;
    final data = Float32List(n * stride);
    final startUs = _samples.first.timeUs;
    for (var i = 0; i < n; i++) {
      final s = _samples[i];
      final o = i * stride;
      final t = (s.timeUs - startUs) / 1000;
      data[o] = s.position.dx;
      data[o + 1] = s.position.dy;
      data[o + 2] = core.kNominalWidthQ;
      data[o + 3] = 0;
      data[o + 4] = 0;
      data[o + 5] = t.clamp(0, InkTuning.strokeRolloverMs).toDouble();
    }
    return FinishedStroke(
      style: _style,
      data: data,
      hasTilt: false,
      hasAzimuth: false,
      startTimeUs: startUs,
      pressureSource: source,
      meta: _meta,
    );
  }

  /// Positions of the samples so far (page pt).
  Iterable<Offset> get positions => _samples.map((s) => s.position);
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
