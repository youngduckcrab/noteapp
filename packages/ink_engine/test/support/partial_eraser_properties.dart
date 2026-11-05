// T16 (03-ink 6.20 '성질'): random strokes × random partial-eraser paths,
// shared by the VM property test (200 cases) and the Chrome wrapper (50).
// Random numbers are MINSTD with plain arithmetic, so VM and Chrome make the
// same cases; the result checksum is arithmetic on the CORE grid (0.01 pt,
// widthQ 0.001), no bit operations.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/edit/hit_test.dart';
import 'package:ink_engine/src/edit/partial_eraser.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/sessions.dart' show eraserIntervalsOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

/// Checksum of the first 50 cases, recorded on the VM (equal in Chrome).
const int partialEraserChecksum50 = 590911598;

/// MINSTD (Park–Miller), arithmetic only.
final class Minstd {
  Minstd(int seed) : _state = seed % 2147483646 + 1;
  int _state;
  double next() {
    _state = _state * 48271 % 2147483647;
    return _state / 2147483647;
  }

  double range(double lo, double hi) => lo + (hi - lo) * next();
  int below(int n) => (next() * n).floor() % n;
}

const _tools = [
  core.PenTool.ballpoint,
  core.PenTool.fountain,
  core.PenTool.highlighter,
  core.PenTool.pencil,
  core.PenTool.marker,
];

/// One random case: the original stroke and the eraser samples / radius.
typedef PartialCase = ({
  core.Stroke original,
  List<ui.Offset> path,
  double radius,
});

PartialCase partialCase(int k) {
  final rnd = Minstd(1000 + k * 7919);
  final tool = _tools[rnd.below(_tools.length)];
  final width = rnd.range(0.5, tool == core.PenTool.highlighter ? 20 : 8);
  final dot = rnd.next() < 0.05;
  final n = dot ? 1 + rnd.below(3) : 2 + rnd.below(40);
  final hasTilt = rnd.next() < 0.5, hasAzimuth = rnd.next() < 0.3;
  const stride = core.StrokePoints.stride;
  final data = Float32List(n * stride);
  var x = rnd.range(100, 400), y = rnd.range(100, 600);
  var heading = rnd.range(0, 2 * math.pi);
  final turn = rnd.range(-0.4, 0.4);
  var t = 0.0;
  for (var i = 0; i < n; i++) {
    data[i * stride] = x;
    data[i * stride + 1] = y;
    data[i * stride + 2] = rnd.range(0.05, 0.6);
    data[i * stride + 3] = hasTilt ? rnd.range(0, 1.2) : 0;
    data[i * stride + 4] = hasAzimuth ? rnd.range(-3, 3) : 0;
    data[i * stride + 5] = t;
    if (!dot) {
      final step = rnd.next() < 0.1 ? rnd.range(8, 30) : rnd.range(0.5, 4);
      heading += turn + rnd.range(-0.3, 0.3);
      x += step * math.cos(heading);
      y += step * math.sin(heading);
    }
    t += rnd.range(4, 12);
  }
  final recorded = rnd.next() < 0.3;
  final original = interop.strokeFromData(
    data,
    id: 'o$k',
    pageId: 'p1',
    style: core.StrokeStyle.defaultsFor(tool).copyWith(width: width),
    createdAt: 5000 + k,
    hasTilt: hasTilt,
    hasAzimuth: hasAzimuth,
    recordingId: recorded ? 'rec-$k' : null,
    recordingOffsetMs: recorded ? 1200 + k : null,
  );
  // the eraser path starts near a random point of the stroke
  final ink = InkPoints.of(original.points);
  final at = ink.offsetAt(rnd.below(ink.length));
  final samples = 1 + rnd.below(8);
  final path = <ui.Offset>[
    at + ui.Offset(rnd.range(-25, 25), rnd.range(-25, 25)),
  ];
  for (var i = 1; i < samples; i++) {
    path.add(path.last + ui.Offset(rnd.range(-30, 30), rnd.range(-30, 30)));
  }
  return (original: original, path: path, radius: rnd.range(0.5, 12));
}

/// The result of one case: the edit and the erased intervals of the original.
typedef PartialResult = ({InkEdit? edit, List<ParamInterval> erased});

PartialResult runPartialCase(PartialCase c) {
  final controller = createTestPageController();
  try {
    controller.updateContent(SyntheticInk.pageContent(strokes: [c.original]));
    InkSample sample(ui.Offset p, int i) =>
        InkSample(position: p, timeUs: i * 8333, kind: InkPointerKind.stylus);
    final session = controller.beginErase(
      sample(c.path.first, 0),
      spec: EraserSpec(mode: EraserMode.partial, radius: c.radius),
      viewScale: 1,
    );
    for (var i = 1; i < c.path.length; i++) {
      session.addSample(sample(c.path[i], i));
    }
    final erased = eraserIntervalsOf(session, c.original.id);
    return (edit: session.end(), erased: erased);
  } finally {
    controller.dispose();
  }
}

/// Arithmetic checksum of [results] on the CORE grid.
int partialChecksum(Iterable<PartialResult> results) {
  const mod = 1000000007;
  var acc = 7;
  void mix(int v) => acc = (acc * 31 + v % mod + mod) % mod;
  for (final r in results) {
    final edit = r.edit;
    mix(edit == null ? 1 : 2 + edit.added.length);
    if (edit == null) continue;
    for (final f in edit.added) {
      final p = f.points;
      mix(p.length);
      for (var i = 0; i < p.length; i++) {
        mix((p.x(i) * 100).round());
        mix((p.y(i) * 100).round());
        mix((p.widthQ(i) * 1000).round());
        mix((p.t(i) * 10).round());
      }
    }
  }
  return acc;
}

double _arcBetween(InkPoints p, double s0, double s1) {
  final a = p.lerpAt(s0), b = p.lerpAt(s1);
  final i0 = s0.floor() + 1;
  var sum = 0.0;
  var px = a.x, py = a.y;
  for (var k = i0; k < s1; k++) {
    sum += math.sqrt(math.pow(p.x(k) - px, 2) + math.pow(p.y(k) - py, 2));
    px = p.x(k);
    py = p.y(k);
  }
  return sum + math.sqrt(math.pow(b.x - px, 2) + math.pow(b.y - py, 2));
}

/// The 6.20 properties ①–⑤ for cases 0 … [cases − 1]; returns the checksum
/// of the first min(cases, 50).
int checkPartialEraserProperties(int cases) {
  final results = <PartialResult>[];
  var touched = 0, split = 0;
  for (var k = 0; k < cases; k++) {
    final c = partialCase(k);
    final r = runPartialCase(c);
    results.add(r);
    final original = InkStroke.of(c.original);
    final width = c.original.style.width;
    final capsules = [
      (c.path.first, c.path.first),
      for (var i = 1; i < c.path.length; i++) (c.path[i - 1], c.path[i]),
    ];
    // ③ no contact → null (dense-independent: the exact minimum of g)
    final gap = capsules
        .map((cap) => InkHitTest.capsuleGap(original, cap.$1, cap.$2, c.radius))
        .reduce(math.min);
    final edit = r.edit;
    if (gap > 0.01) {
      expect(edit, isNull, reason: 'case $k: gap $gap');
      continue;
    }
    if (gap < -0.01) expect(edit, isNotNull, reason: 'case $k: gap $gap');
    if (edit == null) continue;
    touched++;
    expect(edit.kind, InkEditKind.splitStrokes);
    expect(edit.removedIds, {c.original.id});
    if (edit.added.isNotEmpty) split++;
    final eps = 0.01 + 0.001 * width;
    final tMin = [
      for (var i = 0; i < c.original.points.length; i++) c.original.points.t(i),
    ].reduce(math.min);
    final tMax = [
      for (var i = 0; i < c.original.points.length; i++) c.original.points.t(i),
    ].reduce(math.max);
    var kept = 0.0;
    for (final f in edit.added) {
      // ⑤ fragment fields
      expect(f.style, c.original.style, reason: 'case $k style');
      expect(f.createdAt, c.original.createdAt);
      expect(f.recordingId, c.original.recordingId);
      expect(f.recordingOffsetMs, c.original.recordingOffsetMs);
      expect(f.version, isNull);
      expect(f.pageId, c.original.pageId);
      expect(f.points.hasTilt, c.original.points.hasTilt);
      expect(f.points.hasAzimuth, c.original.points.hasAzimuth);
      final fi = InkStroke.of(f);
      for (var j = 0; j < f.points.length; j++) {
        expect(f.points.t(j), inInclusiveRange(tMin - 1e-3, tMax + 1e-3));
        // ① every kept point stays out of the eraser
        final rj = fi.radiusAt(j);
        for (final (a, b) in capsules) {
          final d = InkHitTest.pointSegmentDistance(
            f.points.x(j),
            f.points.y(j),
            a.dx,
            a.dy,
            b.dx,
            b.dy,
          );
          expect(
            d,
            greaterThanOrEqualTo(c.radius + rj - eps),
            reason: 'case $k fragment ${f.id} point $j',
          );
        }
      }
      kept += InkPoints.of(f.points).arcLength();
    }
    // ② kept + crumbs + erased = original (± 0.02 pt per cut)
    final p = InkPoints.of(c.original.points);
    final last = (p.length - 1).toDouble();
    var erasedLength = 0.0, cuts = 0;
    for (final e in r.erased) {
      erasedLength += _arcBetween(p, e.start, e.end);
      if (e.start > 0) cuts++;
      if (e.end < last) cuts++;
    }
    var crumbs = 0.0;
    final minLength = PartialEraser.minPieceLength(c.original.style);
    if (!original.isDot) {
      for (final keep in PartialEraser.complement(r.erased, last)) {
        final len = _arcBetween(p, keep.start, keep.end);
        if (len < minLength) crumbs += len;
      }
    }
    expect(
      kept + crumbs + erasedLength,
      closeTo(p.arcLength(), 0.02 * math.max(1, cuts)),
      reason: 'case $k length',
    );
  }
  // the random cases really cut strokes
  expect(touched, greaterThan(cases ~/ 4));
  expect(split, greaterThan(cases ~/ 8));
  // ④ same input → same result
  for (var k = 0; k < math.min(cases, 10); k++) {
    expect(
      partialChecksum([runPartialCase(partialCase(k))]),
      partialChecksum([results[k]]),
    );
  }
  return partialChecksum(results.take(50));
}
