// Outline checksums for the determinism tests (m5-7/03-ink 9.2): fixed nib
// (T28) and dashed (T29) outlines quantized to 0.01 pt, arithmetic only, so the
// value recorded on the VM is also the Chrome value (JS numbers). The VM checks
// are in test/unit/geometry/nib_outline_test.dart and dash_test.dart, the Chrome
// checks in test/web/determinism_test.dart (v2).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';
import 'package:ink_engine/src/pen/pen_profile.dart';

import 'outline_helpers.dart';

/// The checksum of nibChecksumOutlines() recorded on the VM (T28).
const int recordedNibChecksum = 168632678;

/// The checksum of dashedChecksumOutlines() recorded on the VM (T29).
const int recordedDashedChecksum = 165542780;

/// Quantized polygons (and dashed dots) of an outline (0.01 pt), arithmetic
/// only (web-safe). An outline without dots adds its polygons only.
int outlineChecksum(StrokeOutline o) {
  const m = 1000000007;
  var sum = 0;
  void add(double v) => sum = (sum * 31 + (v * 100).round() + m) % m;
  for (final poly in o.polygons) {
    add(poly.length.toDouble());
    for (final v in poly) {
      add(v);
    }
  }
  if (o.dots.isNotEmpty) {
    add(o.dots.length.toDouble());
    add(o.dotRadius);
    for (final d in o.dots) {
      add(d.dx);
      add(d.dy);
    }
  }
  final c = o.dotCenter;
  if (c != null) {
    add(c.dx);
    add(c.dy);
    add(o.dotRadius);
  }
  return sum;
}

/// The checksums of [outlines] folded into one value.
int foldedChecksum(Iterable<StrokeOutline> outlines) {
  var sum = 0;
  for (final o in outlines) {
    sum = (sum * 7 + outlineChecksum(o)) % 1000000007;
  }
  return sum;
}

/// A straight line of [length] pt from [from] in the direction [deg] (clockwise
/// on the screen), a point every 2 pt.
List<ui.Offset> _line(ui.Offset from, double deg, {double length = 100}) {
  final r = deg * math.pi / 180;
  final d = ui.Offset(math.cos(r), math.sin(r));
  return sampleCurve((u) => from + d * (length * u), length: length, step: 2);
}

List<ui.Offset> _sCurve({ui.Offset origin = const ui.Offset(60, 120)}) =>
    sampleCurve(
      (u) => origin + ui.Offset(200 * u, 40 * math.sin(u * 2 * math.pi)),
      length: 260,
      step: 2,
    );

/// The fixed centerlines: straight 0° and 60°, an S curve, a sharp corner, one
/// point.
List<List<ui.Offset>> _shapes() => [
  _line(const ui.Offset(20, 30), 0),
  _line(const ui.Offset(20, 30), 60),
  _sCurve(),
  [
    const ui.Offset(50, 300),
    const ui.Offset(150, 300),
    const ui.Offset(60, 320),
  ],
  [const ui.Offset(400, 400)],
];

/// Nib outlines of a few shapes, angles, aspects and widths (T28).
List<StrokeOutline> nibChecksumOutlines() => [
  for (final (angle, aspect) in [(0.0, 0.25), (45.0, 0.1), (135.0, 0.6)])
    for (final width in [0.5, 2.5, 18.0])
      for (final xy in _shapes())
        OutlineGenerator.nib(
          pointsOf(xy),
          width: width,
          angleDeg: angle,
          aspect: aspect,
        ),
];

/// Dashed outlines (T29): dashes, dots ([0, 2]), a four-step pattern, a dash
/// longer than the centerline, a piece shorter than 2r (a dot), and an invalid
/// pattern (the default [4, 3]) — each over the fixed shapes at three widths.
List<StrokeOutline> dashedChecksumOutlines() => [
  for (final pattern in const [
    [4.0, 3.0],
    [0.0, 2.0],
    [6.0, 2.0, 1.0, 2.0],
    [500.0, 1.0],
    [0.3, 1.5],
    [-1.0, 3.0],
  ])
    for (final width in [0.5, 2.5, 8.0])
      for (final xy in _shapes())
        OutlineGenerator.outlineOf(
          pointsOf(xy),
          width: width,
          profile: PenProfile.dashed,
          dashPattern: pattern,
        ),
];
