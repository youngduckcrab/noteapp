// lib/src/dev/synthetic_strokes.dart — contract 7.2.15 (03-ink 4.14).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../interop/core_interop.dart' as interop;
import '../tuning.dart';

abstract final class InkDevTools {
  /// Deterministic handwriting-like CORE strokes for load tests (EDITOR developer menu).
  ///
  /// Rules (4.14): style = core.StrokeStyle.defaultsFor(tool); 40–160 points per stroke
  /// (mean 100); start point inside the page with a 24 pt margin; velocity random walk
  /// (letter size ≈ 6–40 pt); widthQ random walk in [0.2, 0.3] (highlighter 0.25);
  /// t at 120 Hz; no tilt / azimuth; stroke i has createdAt = [createdAt] + i; random =
  /// MINSTD([seed]) with arithmetic only (no trigonometry, no bit operations), so VM and
  /// web give the same points. Every point stays on the page. The result can go into
  /// core.AddStrokes as is (version == null).
  static List<core.Stroke> syntheticStrokes({
    required String pageId,
    required core.PageSize pageSize,
    required int count,
    required String Function() newId,
    required core.EpochMillis createdAt,
    int seed = 1,
    core.PenTool tool = core.PenTool.ballpoint,
  }) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'must be >= 0');
    final rng = _Minstd(seed);
    final style = core.StrokeStyle.defaultsFor(tool);
    final fixedQ = tool == core.PenTool.highlighter;
    const margin = InkTuning.syntheticMarginPt;
    final pw = pageSize.width, ph = pageSize.height;
    final usableW = math.max(0.0, pw - 2 * margin);
    final usableH = math.max(0.0, ph - 2 * margin);
    // Upper clamp on CORE's 0.01 pt grid, a little inside the edge, so the
    // quantized Float32 coordinate never lands past the page (A4 595.2756 →
    // 595.27, not 595.28).
    final maxX = _gridInside(pw), maxY = _gridInside(ph);
    const stride = core.StrokePoints.stride;
    final out = <core.Stroke>[];
    for (var i = 0; i < count; i++) {
      final n =
          InkTuning.syntheticMinPoints +
          (rng.next() *
                  (InkTuning.syntheticMaxPoints -
                      InkTuning.syntheticMinPoints +
                      1))
              .floor();
      final size = 6 + rng.next() * 34; // letter size, pt
      final step = size / 40; // mean path ≈ 2.5 letter sizes
      var x = margin + rng.next() * usableW;
      var y = margin + rng.next() * usableH;
      var vx = rng.next() - 0.5, vy = rng.next() - 0.5;
      var q = 0.2 + rng.next() * 0.1;
      final data = Float32List(n * stride);
      for (var k = 0; k < n; k++) {
        final o = k * stride;
        data[o] = x;
        data[o + 1] = y;
        data[o + 2] = fixedQ ? core.kNominalWidthQ : q;
        data[o + 3] = 0;
        data[o + 4] = 0;
        data[o + 5] = k * 1000 / InkTuning.syntheticHz;
        // velocity random walk, normalized to `step` (sqrt is exact on every platform)
        vx = vx * 0.8 + (rng.next() - 0.5);
        vy = vy * 0.8 + (rng.next() - 0.5);
        final len = math.sqrt(vx * vx + vy * vy);
        if (len > 1e-9) {
          x += vx / len * step;
          y += vy / len * step;
        }
        x = x.clamp(0.0, maxX).toDouble();
        y = y.clamp(0.0, maxY).toDouble();
        q = (q + (rng.next() - 0.5) * 0.02).clamp(0.2, 0.3).toDouble();
      }
      out.add(
        interop.strokeFromData(
          data,
          id: newId(),
          pageId: pageId,
          style: style,
          createdAt: createdAt + i,
        ),
      );
    }
    return out;
  }
}

/// The largest 0.01 pt grid value at least 0.005 pt inside [side] (Float32
/// rounding stays below 0.001 pt up to core.PageSize.maxSide).
double _gridInside(double side) =>
    math.max(0.0, ((side - 0.005) * 100).floorToDouble() / 100);

/// MINSTD (Park–Miller): s ← s · 48271 mod (2³¹ − 1). Arithmetic only (6.26).
final class _Minstd {
  _Minstd(int seed) : _s = _normalize(seed);

  static const int _m = 2147483647;
  int _s;

  static int _normalize(int seed) {
    final s = seed % _m;
    return s == 0 ? 1 : s;
  }

  /// In (0, 1).
  double next() {
    _s = (_s * 48271) % _m;
    return _s / _m;
  }
}
