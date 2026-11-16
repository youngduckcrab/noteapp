// Hand-drawn shape corpus — m5-7/05-library 6.17.5. A seeded generator of
// strokes that look like a stylus on a tablet (Android S Pen / Pencil), as
// the 6.18 hold hands them to the fitter: the outline, then ~500 ms of the
// pen held still. unit/shape_corpus_test.dart prints the confusion matrix and
// asserts a recall floor per class.
//
// What a hand does that the E-L2 generator (shape_cases.dart) does not:
//  * speed: slow at corners and at both ends, fast on edges — few points
//    when drawn fast (25–60), many when slow (300–700);
//  * corners: rounded (an arc of up to a quarter of the shorter edge);
//  * edges: bowed (±4 % of the edge), a low-frequency wobble;
//  * closing: an overshoot past the start, a crossing hook that leaves the
//    outline, or a small gap; a start at a corner or in the middle of an edge;
//  * ellipses: axis ratio 0.3–0.78 (thin ones 0.1–0.3), any rotation,
//    egg-shaped asymmetry, a
//    second lap a little inside / outside the first;
//  * the hold tail: 0.5 s of samples within a pt or two of the last point
//    (jitter and a slow drift), samples closer than 0.15 pt dropped like INK's
//    centerline (InkTuning.minSampleDistancePx).
// Negatives (must stay ink): scribbles and one-stroke handwriting — cursive
// loops, digits 2 / 3 / 6 / 8 / 9, S, z, ㄹ, a check mark, a zigzag, a
// spiral, a five-point star, an arrow, a wave, an open arc (C / U).
import 'dart:math' as math;
import 'dart:ui' show Offset;

/// The true class of a corpus stroke.
enum CorpusClass {
  line,
  circle,
  ellipse,
  triangle,
  rectangle,
  quad,
  polygon,
  negative,
}

/// The verdict ('none', 'line', 'circle', 'ellipse', 'triangle',
/// 'rectangle', 'polygon' — shape_cases.dart verdictOf) each class should get.
const Map<CorpusClass, String> kCorpusExpected = {
  CorpusClass.line: 'line',
  CorpusClass.circle: 'circle',
  CorpusClass.ellipse: 'ellipse',
  CorpusClass.triangle: 'triangle',
  CorpusClass.rectangle: 'rectangle',
  CorpusClass.quad: 'polygon',
  CorpusClass.polygon: 'polygon',
  CorpusClass.negative: 'none',
};

/// One stroke of the corpus.
final class CorpusStroke {
  const CorpusStroke(this.truth, this.variant, this.points);

  final CorpusClass truth;

  /// What was drawn (e.g. 'triangle/right', 'negative/digit8').
  final String variant;
  final List<Offset> points;
}

/// The seeded generator.
final class HandDrawnCorpus {
  HandDrawnCorpus(int seed) : _rng = math.Random(seed);

  final math.Random _rng;

  double _u(double a, double b) => a + _rng.nextDouble() * (b - a);
  bool _p(double p) => _rng.nextDouble() < p;
  T _pick<T>(List<T> v) => v[_rng.nextInt(v.length)];

  double _gauss() {
    final u1 = math.max(1e-12, _rng.nextDouble()), u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// [perVariant] strokes of every variant, class by class.
  List<CorpusStroke> build({int perVariant = 40}) => [
    for (final v in _variants)
      for (var i = 0; i < perVariant; i++) v.make(this),
  ];

  late final List<_Variant> _variants = [
    // ---- lines
    _Variant(CorpusClass.line, 'line/any', (g) => g._line()),
    _Variant(CorpusClass.line, 'line/axis', (g) => g._line(axis: true)),
    // ---- circles
    _Variant(CorpusClass.circle, 'circle/plain', (g) => g._ellipse(0.9, 1.0)),
    _Variant(
      CorpusClass.circle,
      'circle/overlap',
      (g) => g._ellipse(0.9, 1.0, overlap: true),
    ),
    // ---- ellipses
    _Variant(CorpusClass.ellipse, 'ellipse/flat', (g) => g._ellipse(0.3, 0.5)),
    _Variant(CorpusClass.ellipse, 'ellipse/mid', (g) => g._ellipse(0.5, 0.7)),
    _Variant(
      CorpusClass.ellipse,
      'ellipse/round',
      (g) => g._ellipse(0.7, 0.78),
    ),
    _Variant(
      CorpusClass.ellipse,
      'ellipse/overlap',
      (g) => g._ellipse(0.3, 0.78, overlap: true),
    ),
    _Variant(
      CorpusClass.ellipse,
      'ellipse/egg',
      (g) => g._ellipse(0.35, 0.78, egg: true),
    ),
    _Variant(
      CorpusClass.ellipse,
      'ellipse/fast',
      (g) => g._ellipse(0.3, 0.78, speed: _Speed.fast),
    ),
    _Variant(
      CorpusClass.ellipse,
      'ellipse/small',
      (g) => g._ellipse(0.35, 0.78, aMin: 18, aMax: 35),
    ),
    // ---- triangles
    for (final kind in _TriangleKind.values)
      _Variant(
        CorpusClass.triangle,
        'triangle/${kind.name}',
        (g) => g._polygon(g._triangle(kind)),
      ),
    _Variant(
      CorpusClass.triangle,
      'triangle/rounded',
      (g) => g._polygon(
        g._triangle(g._pick(_TriangleKind.values)),
        roundMin: 0.12,
        roundMax: 0.28,
      ),
    ),
    _Variant(
      CorpusClass.triangle,
      'triangle/cornerStart',
      (g) => g._polygon(
        g._triangle(g._pick(_TriangleKind.values)),
        start: _Start.corner,
        closing: _Closing.cross,
      ),
    ),
    _Variant(
      CorpusClass.triangle,
      'triangle/fast',
      (g) => g._polygon(
        g._triangle(g._pick(_TriangleKind.values)),
        speed: _Speed.fast,
      ),
    ),
    _Variant(
      CorpusClass.triangle,
      'triangle/small',
      (g) => g._polygon(
        g._small(g._triangle(g._pick(_TriangleKind.values)), 36, 70),
      ),
    ),
    _Variant(
      CorpusClass.triangle,
      'triangle/slow',
      (g) => g._polygon(
        g._triangle(g._pick(_TriangleKind.values)),
        speed: _Speed.slow,
      ),
    ),
    // ---- rectangles
    _Variant(
      CorpusClass.rectangle,
      'rectangle/axis',
      (g) => g._polygon(g._rect(rotated: false)),
    ),
    _Variant(
      CorpusClass.rectangle,
      'rectangle/rotated',
      (g) => g._polygon(g._rect(rotated: true)),
    ),
    _Variant(
      CorpusClass.rectangle,
      'rectangle/cornerStart',
      (g) => g._polygon(
        g._rect(rotated: false),
        start: _Start.corner,
        closing: _Closing.cross,
      ),
    ),
    // ---- other quadrilaterals and polygons
    _Variant(
      CorpusClass.rectangle,
      'rectangle/small',
      (g) => g._polygon(g._small(g._rect(rotated: false), 40, 80)),
    ),
    _Variant(CorpusClass.quad, 'quad/any', (g) => g._polygon(g._quad())),
    _Variant(
      CorpusClass.polygon,
      'polygon/pentagon',
      (g) => g._polygon(g._regular(5)),
    ),
    _Variant(
      CorpusClass.polygon,
      'polygon/hexagon',
      (g) => g._polygon(g._regular(6), roundMax: 0.08),
    ),
    // ---- must stay ink
    _Variant(CorpusClass.negative, 'negative/scribble', (g) => g._scribble()),
    for (final h in _Hand.values)
      _Variant(
        CorpusClass.negative,
        'negative/${h.name}',
        (g) => g._handwriting(h),
      ),
    // ---- (review fixes) appended so the strokes above stay the same.
    // Circles are 0.83–1.0 and ellipses ≤ 0.78: the band in between is a
    // sloppy circle or a round ellipse — no one can tell, so no variant
    // asks (circleMinAxisRatio 0.82 sits in it). Loose rests drift 3–7 pt
    // with up to 2 pt of tremor (InkTuning.shapeHoldRadiusPx is 8 px).
    _Variant(CorpusClass.circle, 'circle/sloppy', (g) => g._ellipse(0.83, 0.9)),
    _Variant(
      CorpusClass.circle,
      'circle/shaky',
      (g) => g._ellipse(0.9, 1.0, ringJitter: g._u(0.02, 0.05)),
    ),
    _Variant(
      CorpusClass.ellipse,
      'ellipse/thin',
      (g) => g._ellipse(0.1, 0.3, aMin: 80, aMax: 200),
    ),
    _Variant(
      CorpusClass.rectangle,
      'rectangle/thin',
      // A box round a heading: its long edges bow ±1.2 % (≤ 4 pt), not the
      // ±4 % of the other outlines (12 pt on a 30 pt high box is a lens).
      (g) => g._polygon(
        g._rect(rotated: g._p(0.5), aspectMin: 0.08, aspectMax: 0.25),
        bowMax: 0.012,
      ),
    ),
    for (final c in [
      CorpusClass.line,
      CorpusClass.circle,
      CorpusClass.ellipse,
      CorpusClass.triangle,
      CorpusClass.rectangle,
    ])
      _Variant(c, '${c.name}/shakyHold', (g) {
        g._shakyHold = true;
        try {
          return switch (c) {
            CorpusClass.line => g._line(),
            CorpusClass.circle => g._ellipse(0.9, 1.0),
            CorpusClass.ellipse => g._ellipse(0.3, 0.75),
            CorpusClass.triangle => g._polygon(
              g._triangle(g._pick(_TriangleKind.values)),
            ),
            _ => g._polygon(g._rect(rotated: g._p(0.5))),
          };
        } finally {
          g._shakyHold = false;
        }
      }),
    for (final c in [
      CorpusClass.circle,
      CorpusClass.ellipse,
      CorpusClass.triangle,
      CorpusClass.rectangle,
    ])
      _Variant(c, '${c.name}/smallShakyHold', (g) {
        g._shakyHold = true;
        try {
          return switch (c) {
            CorpusClass.circle => g._ellipse(0.9, 1.0, aMin: 18, aMax: 30),
            CorpusClass.ellipse => g._ellipse(0.35, 0.7, aMin: 22, aMax: 35),
            CorpusClass.triangle => g._polygon(
              g._small(g._triangle(g._pick(_TriangleKind.values)), 40, 70),
            ),
            _ => g._polygon(g._small(g._rect(rotated: false), 40, 70)),
          };
        } finally {
          g._shakyHold = false;
        }
      }),
  ];

  /// (review fixes) the hold as loose as InkTuning.shapeHoldRadiusPx (8 px)
  /// lets it: a drift of 3–7 pt and a tremor of up to 2 pt.
  bool _shakyHold = false;

  // ---------------------------------------------------------------- outlines

  List<Offset> _triangle(_TriangleKind kind) {
    final s = _u(80, 320);
    final List<Offset> v;
    switch (kind) {
      case _TriangleKind.equilateral:
        v = [
          for (final d in [-90.0, 30, 150])
            Offset.fromDirection((d + _u(-6, 6)) * math.pi / 180, s / 2),
        ];
      case _TriangleKind.right:
        final w = s, h = s * _u(0.5, 1.2);
        v = [Offset.zero, Offset(0, h), Offset(w, h)];
      case _TriangleKind.obtuse:
        final w = s, h = s * _u(0.25, 0.45);
        v = [Offset(w * _u(-0.35, -0.1), 0), Offset(0, h), Offset(w, h)];
      case _TriangleKind.tall:
        final w = s * _u(0.35, 0.55);
        v = [Offset(w / 2 + _u(-0.1, 0.1) * w, 0), Offset(0, s), Offset(w, s)];
      case _TriangleKind.flat:
        final h = s * _u(0.28, 0.42);
        v = [Offset(s * _u(0.3, 0.7), 0), Offset(0, h), Offset(s, h)];
    }
    return _place(v, _u(0, 2 * math.pi));
  }

  List<Offset> _rect({
    required bool rotated,
    double aspectMin = 0.3,
    double aspectMax = 1.0,
  }) {
    final w = _u(80, 320), h = w * _u(aspectMin, aspectMax);
    final v = _p(0.5)
        ? [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)]
        : [Offset.zero, Offset(h, 0), Offset(h, w), Offset(0, w)];
    return _place(
      v,
      rotated ? _u(12, 78) * math.pi / 180 : _u(-4, 4) * math.pi / 180,
    );
  }

  List<Offset> _quad() {
    final w = _u(100, 300), h = w * _u(0.45, 0.9);
    final List<Offset> v;
    switch (_rng.nextInt(3)) {
      // Every angle at least 22° away from 90° (nearer is a rectangle).
      case 0: // parallelogram
        final k = h * math.tan(_u(22, 38) * math.pi / 180);
        v = [Offset(k, 0), Offset(w + k, 0), Offset(w, h), Offset(0, h)];
      case 1: // trapezoid
        final k = h * math.tan(_u(22, 32) * math.pi / 180);
        v = [
          Offset(k, 0),
          Offset(w + k, 0),
          Offset(w + 2 * k, h),
          Offset(0, h),
        ];
      default: // rhombus (a kite of 50–68° or 112–130° at the top)
        final half = w / 2 * (_p(0.5) ? _u(0.45, 0.66) : _u(1.5, 2.2));
        v = [
          Offset(w / 2, 0),
          Offset(w, half),
          Offset(w / 2, 2 * half),
          Offset(0, half),
        ];
    }
    return _place(v, _u(-0.15, 0.15));
  }

  List<Offset> _regular(int n) {
    final s = _u(100, 300), rot = _u(0, 2 * math.pi);
    return _place([
      for (var k = 0; k < n; k++)
        Offset.fromDirection(
          rot + 2 * math.pi * k / n + _u(-0.06, 0.06),
          s / 2,
        ),
    ], 0);
  }

  /// [v] scaled about its centroid so its largest extent is in [lo, hi] pt.
  List<Offset> _small(List<Offset> v, double lo, double hi) {
    var size = 0.0;
    for (final p in v) {
      for (final q in v) {
        size = math.max(size, (p - q).distance);
      }
    }
    final k = _u(lo, hi) / size;
    return [
      for (final p in v)
        const Offset(500, 500) + (p - const Offset(500, 500)) * k,
    ];
  }

  /// [v] centred on (500, 500) and turned by [rot].
  List<Offset> _place(List<Offset> v, double rot) {
    var cx = 0.0, cy = 0.0;
    for (final p in v) {
      cx += p.dx / v.length;
      cy += p.dy / v.length;
    }
    final c = math.cos(rot), s = math.sin(rot);
    return [
      for (final p in v)
        Offset(
          500 + (p.dx - cx) * c - (p.dy - cy) * s,
          500 + (p.dx - cx) * s + (p.dy - cy) * c,
        ),
    ];
  }

  // ------------------------------------------------------------ the strokes

  List<Offset> _line({bool axis = false}) {
    final len = _u(60, 420);
    final ang = axis
        ? _pick([0.0, 90.0, 180.0, 270.0]) * math.pi / 180 + _u(-0.05, 0.05)
        : _u(0, 2 * math.pi);
    final bow = _u(-0.025, 0.025) * len;
    final a = Offset(500, 500), d = Offset.fromDirection(ang, len);
    final n = Offset(-d.dy, d.dx) / len;
    final path = [
      for (var i = 0; i <= 200; i++)
        a + d * (i / 200) + n * (bow * math.sin(math.pi * i / 200)),
    ];
    // Sometimes a small hook at the end (the pen settles on the point).
    if (_p(0.3)) {
      final hook = Offset.fromDirection(_u(0, 2 * math.pi), _u(1, 4));
      for (var i = 1; i <= 6; i++) {
        path.add(path.last + hook / 6);
      }
    }
    return _hand(path, corners: const [], size: len, speed: _speedOf());
  }

  /// An ellipse with axis ratio in [rMin, rMax] (a circle when ≥ 0.9).
  List<Offset> _ellipse(
    double rMin,
    double rMax, {
    bool overlap = false,
    bool egg = false,
    _Speed? speed,
    double aMin = 45,
    double aMax = 170,
    double ringJitter = 0,
  }) {
    final a = _u(aMin, aMax), b = a * _u(rMin, rMax);
    final rot = _u(0, math.pi);
    final start = _u(0, 2 * math.pi);
    final dir = _p(0.5) ? 1.0 : -1.0;
    // Overshoot past the start / a gap (fractions of a lap).
    final laps = overlap ? 1 + _u(0.06, 0.22) : 1 + _u(-0.05, 0.08);
    final spiral = _u(-0.04, 0.04); // the second lap inside / outside
    final eggK = egg ? _u(0.08, 0.18) : _u(0, 0.04);
    final c = math.cos(rot), s = math.sin(rot);
    // An unsteady hand: the radius off by ±ringJitter at 40 points round
    // the lap, straight between them.
    final jitter = ringJitter > 0
        ? [for (var k = 0; k < 40; k++) _u(-ringJitter, ringJitter)]
        : const <double>[];
    double ring(double t) {
      if (jitter.isEmpty) return 1;
      final x = (t % 1) * 40, k = x.floor() % 40, f = x - x.floor();
      final w = f;
      return 1 + jitter[k] * (1 - w) + jitter[(k + 1) % 40] * w;
    }

    const n = 400;
    final path = <Offset>[
      for (var i = 0; i <= n; i++)
        () {
          final t = laps * i / n;
          final th = start + dir * 2 * math.pi * t;
          final grow = (1 + spiral * t) * ring(t);
          final x = a * math.cos(th) * grow;
          final y = b * math.sin(th) * grow * (1 + eggK * math.cos(th));
          return Offset(500 + x * c - y * s, 500 + x * s + y * c);
        }(),
    ];
    return _hand(
      path,
      corners: const [],
      size: 2 * a,
      speed: speed ?? _speedOf(),
    );
  }

  _Speed _speedOf() => _pick(_Speed.values);

  /// A closed polygon outline through [v], as a hand draws it.
  List<Offset> _polygon(
    List<Offset> v, {
    double roundMin = 0,
    double roundMax = 0.14,
    double bowMax = 0.04,
    _Start? start,
    _Closing? closing,
    _Speed? speed,
  }) {
    final n = v.length;
    if (_p(0.5)) v = v.reversed.toList();
    var size = 0.0;
    for (final p in v) {
      for (final q in v) {
        size = math.max(size, (p - q).distance);
      }
    }
    // Rounded corners: each corner cut back by d along both edges.
    final cut = <double>[
      for (var i = 0; i < n; i++)
        _u(roundMin, roundMax) *
            math.min(
              (v[i] - v[(i - 1 + n) % n]).distance,
              (v[(i + 1) % n] - v[i]).distance,
            ),
    ];
    final bows = [for (var i = 0; i < n; i++) _u(-bowMax, bowMax)];
    final loop = <Offset>[];
    final cornerIdx = <int>[];
    for (var i = 0; i < n; i++) {
      final p = v[i], q = v[(i + 1) % n], r = v[(i + 2) % n];
      final e = q - p, len = e.distance, dir = e / len;
      final nrm = Offset(-dir.dy, dir.dx);
      final from = p + dir * cut[i], to = q - dir * cut[(i + 1) % n];
      const m = 60;
      for (var k = 0; k < m; k++) {
        final t = k / m;
        loop.add(
          Offset.lerp(from, to, t)! +
              nrm * (bows[i] * len * math.sin(math.pi * t)),
        );
      }
      // The corner at q: a quadratic Bézier from `to` round q.
      final out = q + (r - q) / (r - q).distance * cut[(i + 1) % n];
      const mc = 16;
      cornerIdx.add(loop.length + mc ~/ 2);
      for (var k = 0; k < mc; k++) {
        final t = k / mc;
        loop.add(
          to * ((1 - t) * (1 - t)) + q * (2 * (1 - t) * t) + out * (t * t),
        );
      }
    }
    final total = loop.length;
    final startAt = switch (start ?? (_p(0.4) ? _Start.corner : _Start.edge)) {
      _Start.corner => cornerIdx[_rng.nextInt(n)],
      _Start.edge => _rng.nextInt(total),
    };
    final _Closing close = closing ?? _pick(_Closing.values);
    final extra = switch (close) {
      _Closing.exact => _u(-0.01, 0.02),
      _Closing.overshoot => _u(0.03, 0.12),
      _Closing.gap => -_u(0.02, 0.06),
      _Closing.cross => _u(0.01, 0.06),
    };
    final count = (total * (1 + extra)).round();
    final path = [for (var i = 0; i <= count; i++) loop[(startAt + i) % total]];
    // The pen drifts off the first edge on the overshoot / crosses it.
    if (close == _Closing.overshoot || close == _Closing.cross) {
      final over = count - total;
      if (over > 1) {
        final drift = Offset.fromDirection(
          _u(0, 2 * math.pi),
          _u(0.01, 0.04) * size,
        );
        for (var i = total; i <= count; i++) {
          path[i] += drift * ((i - total) / over);
        }
      }
      if (close == _Closing.cross) {
        // A short flick away from the outline.
        final last = path.last, prev = path[path.length - 4];
        final along = (last - prev) / math.max(1e-9, (last - prev).distance);
        final turn = _u(25, 70) * (_p(0.5) ? 1 : -1) * math.pi / 180;
        final flick =
            Offset(
              along.dx * math.cos(turn) - along.dy * math.sin(turn),
              along.dx * math.sin(turn) + along.dy * math.cos(turn),
            ) *
            (_u(0.02, 0.06) * size);
        for (var i = 1; i <= 8; i++) {
          path.add(last + flick * (i / 8));
        }
      }
    }
    final corners = [
      for (final c in cornerIdx) ((c - startAt) % total + total) % total,
    ];
    return _hand(
      path,
      corners: corners,
      size: size,
      speed: speed ?? _speedOf(),
    );
  }

  // ------------------------------------------------------------- negatives

  List<Offset> _scribble() {
    final s = _u(80, 300);
    final raw = [
      for (var i = 0; i <= 60; i++)
        Offset(
          500 + s / 2 * math.sin(i * 0.37) + _u(-s / 6, s / 6),
          500 + s / 3 * math.cos(i * 0.21) + _u(-s / 6, s / 6),
        ),
    ];
    final dense = <Offset>[];
    for (var i = 1; i < raw.length; i++) {
      for (var k = 0; k < 8; k++) {
        dense.add(Offset.lerp(raw[i - 1], raw[i], k / 8)!);
      }
    }
    dense.add(raw.last);
    return _hand(dense, corners: const [], size: s, speed: _speedOf());
  }

  List<Offset> _handwriting(_Hand h) {
    final s = _u(40, 160); // letter height (pt)
    List<Offset> curve(int n, Offset Function(double t) f) => [
      for (var i = 0; i <= n; i++) f(i / n),
    ];
    final List<Offset> path;
    switch (h) {
      case _Hand.cursiveE:
        final k = 3 + _rng.nextInt(3);
        path = curve(80 * k, (t) {
          final th = 2 * math.pi * k * t;
          return Offset(
            s * 0.9 * k * t - 0.3 * s * math.sin(th),
            -0.4 * s * (1 - math.cos(th)) / 2,
          );
        });
      case _Hand.cursiveL:
        final k = 2 + _rng.nextInt(3);
        path = curve(80 * k, (t) {
          final th = 2 * math.pi * k * t;
          return Offset(
            s * 0.6 * k * t - 0.2 * s * math.sin(th),
            -s * (1 - math.cos(th)) / 2,
          );
        });
      case _Hand.digit2:
        path = [
          ...curve(
            60,
            (t) =>
                Offset.fromDirection(math.pi * (1.1 + 1.25 * t), s * 0.3) +
                Offset(0, -s * 0.2),
          ),
          ...curve(
            30,
            (t) => Offset.lerp(
              Offset(s * 0.22, -s * 0.05),
              Offset(-s * 0.3, s * 0.5),
              t,
            )!,
          ),
          ...curve(
            30,
            (t) => Offset.lerp(
              Offset(-s * 0.3, s * 0.5),
              Offset(s * 0.35, s * 0.5),
              t,
            )!,
          ),
        ];
      case _Hand.digit3:
        path = [
          ...curve(
            60,
            (t) =>
                Offset.fromDirection(math.pi * (-0.9 + 1.4 * t), s * 0.25) +
                Offset(0, -s * 0.25),
          ),
          ...curve(
            60,
            (t) =>
                Offset.fromDirection(math.pi * (-0.5 + 1.4 * t), s * 0.27) +
                Offset(0, s * 0.25),
          ),
        ];
      case _Hand.digit6:
        path = [
          ...curve(
            40,
            (t) => Offset(
              s * 0.25 * (1 - t) - s * 0.25 * math.sin(math.pi * t * 0.5),
              -s * 0.5 + s * 0.6 * t,
            ),
          ),
          ...curve(
            80,
            (t) =>
                Offset.fromDirection(math.pi * (1 + 2.1 * t), s * 0.25) +
                Offset(0, s * 0.3),
          ),
        ];
      case _Hand.digit8:
        final laps = _u(1.0, 1.06);
        path = curve(240, (t) {
          final th = 2 * math.pi * t * laps;
          return Offset(s * 0.28 * math.sin(2 * th), s * 0.5 * math.sin(th));
        });
      case _Hand.digit9:
        path = [
          ...curve(
            80,
            (t) =>
                Offset.fromDirection(math.pi * (0.1 - 2.1 * t), s * 0.25) +
                Offset(0, -s * 0.3),
          ),
          ...curve(
            40,
            (t) => Offset.lerp(
              Offset(s * 0.25, -s * 0.3),
              Offset(s * 0.15, s * 0.55),
              t,
            )!,
          ),
        ];
      case _Hand.letterS:
        path = [
          ...curve(
            60,
            (t) =>
                Offset.fromDirection(math.pi * (-0.2 - 1.3 * t), s * 0.25) +
                Offset(0, -s * 0.25),
          ),
          ...curve(
            60,
            (t) =>
                Offset.fromDirection(math.pi * (-0.5 + 1.3 * t), s * 0.25) +
                Offset(0, s * 0.25),
          ),
        ];
      case _Hand.letterZ:
        path = _polyline([
          Offset.zero,
          Offset(s, 0),
          Offset(0, s),
          Offset(s, s),
        ]);
      case _Hand.rieul: // ㄹ
        path = _polyline([
          Offset.zero,
          Offset(s, 0),
          Offset(s, s * 0.45),
          Offset(0, s * 0.45),
          Offset(0, s * 0.9),
          Offset(s, s * 0.9),
        ]);
      case _Hand.check:
        path = _polyline([
          Offset.zero,
          Offset(s * 0.35, s * 0.4),
          Offset(s, -s * 0.6),
        ]);
      case _Hand.zigzag:
        path = _polyline([
          for (var i = 0; i < 6; i++)
            Offset(s * 0.4 * i, i.isEven ? 0 : s * 0.7),
        ]);
      case _Hand.spiral:
        final turns = _u(1.8, 2.6);
        path = curve(
          300,
          (t) => Offset.fromDirection(
            2 * math.pi * turns * t,
            s * (0.15 + 0.5 * t),
          ),
        );
      case _Hand.star:
        path = _polyline([
          for (var k = 0; k <= 5; k++)
            Offset.fromDirection(-math.pi / 2 + 4 * math.pi * k / 5, s / 2),
        ]);
      case _Hand.arrow:
        final head = s * 0.25;
        path = _polyline([
          Offset(-s, 0),
          Offset.zero,
          Offset(-head, -head * 0.8),
          Offset.zero,
          Offset(-head, head * 0.8),
        ]);
      case _Hand.wave:
        path = curve(
          200,
          (t) => Offset(s * 2.5 * t, s * 0.2 * math.sin(2 * math.pi * 3 * t)),
        );
      case _Hand.openArc:
        final span = _u(1.2, 1.55) * math.pi;
        final st = _u(0, 2 * math.pi);
        path = curve(120, (t) => Offset.fromDirection(st + span * t, s * 0.5));
      case _Hand.loopExit: // 'ℓ'-like loop with a long exit
        path = [
          ...curve(
            80,
            (t) => Offset.fromDirection(
              math.pi * 0.5 + 2 * math.pi * t * 0.85,
              s * 0.3,
            ),
          ),
          ...curve(
            30,
            (t) => Offset.lerp(
              Offset.fromDirection(math.pi * 0.5 + 2 * math.pi * 0.85, s * 0.3),
              Offset(s * 1.2, s * 0.6),
              t,
            )!,
          ),
        ];
      case _Hand
          .letterA: // cursive a: the bowl, back up, the down stroke, a tail
        path = [
          ...curve(
            80,
            (t) =>
                Offset.fromDirection(-0.2 - 2 * math.pi * 0.95 * t, s * 0.25),
          ),
          ...curve(
            30,
            (t) => Offset.lerp(
              Offset.fromDirection(-0.2 - 2 * math.pi * 0.95, s * 0.25),
              Offset(s * 0.25, s * 0.25),
              t,
            )!,
          ),
          ...curve(
            20,
            (t) => Offset.lerp(
              Offset(s * 0.25, s * 0.25),
              Offset(s * 0.45, s * 0.12),
              t,
            )!,
          ),
        ];
      case _Hand.letterD: // d: the bowl, then up the tall stem and back down
        path = [
          ...curve(
            80,
            (t) =>
                Offset.fromDirection(-0.3 - 2 * math.pi * 0.95 * t, s * 0.22),
          ),
          ...curve(
            30,
            (t) => Offset.lerp(
              Offset(s * 0.22, 0),
              Offset(s * 0.22, -s * 0.8),
              t,
            )!,
          ),
          ...curve(
            30,
            (t) => Offset.lerp(
              Offset(s * 0.22, -s * 0.8),
              Offset(s * 0.26, s * 0.25),
              t,
            )!,
          ),
        ];
      case _Hand.letterG: // g: the bowl and a descender loop
        path = [
          ...curve(
            80,
            (t) =>
                Offset.fromDirection(-0.3 - 2 * math.pi * 0.95 * t, s * 0.22),
          ),
          ...curve(
            60,
            (t) => Offset(
              s * 0.22 - s * 0.3 * math.sin(math.pi * t),
              s * 0.8 * math.sin(math.pi * t * 0.6),
            ),
          ),
        ];
      case _Hand.letterB: // B in one stroke: the stem, two bumps
        path = [
          ...curve(30, (t) => Offset(0, s * (1 - t))),
          ...curve(
            50,
            (t) => Offset(
              s * 0.4 * math.sin(math.pi * t),
              s * 0.25 * (1 - math.cos(math.pi * t)),
            ),
          ),
          ...curve(
            50,
            (t) => Offset(
              s * 0.5 * math.sin(math.pi * t),
              s * 0.5 + s * 0.25 * (1 - math.cos(math.pi * t)),
            ),
          ),
        ];
      case _Hand.ampersand:
        path = curve(200, (t) {
          final th = 2 * math.pi * 1.15 * t;
          return Offset(
            s * 0.35 * math.sin(2 * th) + s * 0.3 * t,
            s * 0.5 * math.sin(th),
          );
        });
      case _Hand.infinity:
        path = curve(240, (t) {
          final th = 2 * math.pi * t * 1.03;
          return Offset(s * 0.8 * math.sin(th), s * 0.25 * math.sin(2 * th));
        });
      case _Hand.closedZigzag: // a jagged cloud / hatched ring
        final teeth = 10 + _rng.nextInt(12);
        final depth = _u(0.18, 0.35);
        path = curve(teeth * 16, (t) {
          final th = 2 * math.pi * 1.02 * t;
          final saw = ((t * teeth) % 1) < 0.5 ? 1.0 : -1.0;
          return Offset.fromDirection(th, s * 0.5 * (1 + depth * saw));
        });
      case _Hand.doubleLoop: // a circle gone round twice (shading a dot)
        final laps = _u(1.8, 2.4);
        path = curve(
          300,
          (t) => Offset.fromDirection(
            2 * math.pi * laps * t,
            s * 0.4 * (1 + 0.05 * t),
          ),
        );
    }
    final rot = _u(-0.25, 0.25), c = math.cos(rot), sn = math.sin(rot);
    final placed = [
      for (final p in path)
        Offset(500 + p.dx * c - p.dy * sn, 500 + p.dx * sn + p.dy * c),
    ];
    return _hand(placed, corners: const [], size: s, speed: _speedOf());
  }

  List<Offset> _polyline(List<Offset> v) => [
    for (var i = 1; i < v.length; i++)
      for (var k = 0; k < 40; k++) Offset.lerp(v[i - 1], v[i], k / 40)!,
    v.last,
  ];

  // --------------------------------------------------------- the hand model

  /// [path] (dense, evenly-ish spaced) as stylus samples: a speed profile
  /// (slow at [corners] — indices into [path] — and at both ends), wobble,
  /// jitter, then the hold tail. [size] scales wobble and jitter.
  List<Offset> _hand(
    List<Offset> path, {
    required List<int> corners,
    required double size,
    required _Speed speed,
  }) {
    final hz = _pick([120.0, 240.0]);
    final seconds = switch (speed) {
      _Speed.fast => _u(0.2, 0.45),
      _Speed.normal => _u(0.6, 1.2),
      _Speed.slow => _u(1.5, 3.0),
    };
    // Arc length.
    final s = <double>[0];
    for (var i = 1; i < path.length; i++) {
      s.add(s.last + (path[i] - path[i - 1]).distance);
    }
    final total = s.last;
    if (!(total > 0)) return path;
    final slowR = 0.12 * size;
    double speedAt(int i) {
      var f = 1.0;
      for (final c in corners) {
        final d = (s[i] - s[c.clamp(0, path.length - 1)]).abs();
        f = math.min(f, 0.25 + 0.75 * math.min(1, d / slowR));
      }
      final ends = math.min(s[i], total - s[i]);
      return f * (0.35 + 0.65 * math.min(1, ends / slowR));
    }

    // Time per path step ∝ length / speed.
    final t = <double>[0];
    for (var i = 1; i < path.length; i++) {
      t.add(t.last + (s[i] - s[i - 1]) / speedAt(i));
    }
    final count = math.max(12, (seconds * hz).round());
    final wobA = _u(0.003, 0.015) * size, wobF = _u(1, 4), wobP = _u(0, 6.28);
    final jit = math.min(0.6, _u(0.0015, 0.004) * size);
    final out = <Offset>[];
    var j = 0;
    for (var k = 0; k <= count; k++) {
      final target = t.last * k / count;
      while (j < t.length - 2 && t[j + 1] < target) {
        j++;
      }
      final span = t[j + 1] - t[j];
      final f = span > 0 ? ((target - t[j]) / span).clamp(0.0, 1.0) : 0.0;
      final p = Offset.lerp(path[j], path[j + 1], f)!;
      final u = s[j] / total;
      final w = wobA * math.sin(wobF * 2 * math.pi * u + wobP);
      out.add(p + Offset(w + _gauss() * jit, w * 0.7 + _gauss() * jit));
    }
    // The hold: 0.5 s of the pen resting (tremor + a slow drift).
    final holdN = (0.5 * hz).round();
    final drift = Offset.fromDirection(
      _u(0, 2 * math.pi),
      _shakyHold ? _u(3, 7) : _u(0, 2),
    );
    final tremor = _shakyHold ? _u(0.8, 2) : _u(0.15, 0.8);
    final end = out.last;
    for (var k = 1; k <= holdN; k++) {
      out.add(end + drift * (k / holdN) + Offset(_gauss(), _gauss()) * tremor);
    }
    // INK drops samples closer than 0.15 pt (minSampleDistancePx at 1×).
    final kept = <Offset>[out.first];
    for (final p in out.skip(1)) {
      if ((p - kept.last).distance >= 0.15) kept.add(p);
    }
    return kept;
  }
}

enum _TriangleKind { equilateral, right, obtuse, tall, flat }

enum _Start { corner, edge }

enum _Closing { exact, overshoot, gap, cross }

enum _Speed { fast, normal, slow }

enum _Hand {
  cursiveE,
  cursiveL,
  digit2,
  digit3,
  digit6,
  digit8,
  digit9,
  letterS,
  letterZ,
  rieul,
  check,
  zigzag,
  spiral,
  star,
  arrow,
  wave,
  openArc,
  loopExit,
  letterA,
  letterD,
  letterG,
  letterB,
  ampersand,
  infinity,
  closedZigzag,
  doubleLoop,
}

final class _Variant {
  _Variant(this.truth, this.name, this._make);

  final CorpusClass truth;
  final String name;
  final List<Offset> Function(HandDrawnCorpus g) _make;

  CorpusStroke make(HandDrawnCorpus g) => CorpusStroke(truth, name, _make(g));
}
