// Deterministic workloads for the benchmarks (03-ink 9.1, T22).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

const core.PageSize a4 = core.PageSize.a4Portrait;

/// [count] handwriting-like strokes of exactly [points] points each: cursive
/// loops (letter size 6–40 pt) from a random start inside [area] (default:
/// the A4 page with a 24 pt margin), widthQ random walk in [0.2, 0.3], t at
/// 120 Hz, createdAt = [createdAt] + i. Every point stays inside [area].
List<core.Stroke> handwriting({
  required int count,
  required int points,
  ui.Rect? area,
  int seed = 1,
  core.PenTool tool = core.PenTool.ballpoint,
  String idPrefix = 'b',
  String pageId = 'p1',
  int createdAt = 1000,
}) {
  final rng = math.Random(seed);
  final box = area ?? ui.Rect.fromLTWH(24, 24, a4.width - 48, a4.height - 48);
  final style = core.StrokeStyle.defaultsFor(tool);
  const stride = core.StrokePoints.stride;
  return [
    for (var i = 0; i < count; i++)
      () {
        final size = 6 + rng.nextDouble() * 34;
        final advance = size * (0.005 + rng.nextDouble() * 0.01);
        final extent = points * advance + size * 0.6;
        final x0 =
            box.left +
            size * 0.3 +
            rng.nextDouble() * math.max(0.0, box.width - extent);
        final y0 =
            box.top +
            size * 0.5 +
            rng.nextDouble() * math.max(0.0, box.height - size);
        final omega = 0.15 + rng.nextDouble() * 0.2;
        var q = 0.2 + rng.nextDouble() * 0.1;
        final data = Float32List(points * stride);
        for (var k = 0; k < points; k++) {
          final o = k * stride;
          final x = x0 + k * advance + size * 0.3 * math.cos(k * omega);
          final y = y0 + size * 0.5 * math.sin(k * omega * 1.3);
          data[o] = x.clamp(box.left, box.right).toDouble();
          data[o + 1] = y.clamp(box.top, box.bottom).toDouble();
          q = (q + (rng.nextDouble() - 0.5) * 0.01).clamp(0.2, 0.3).toDouble();
          data[o + 2] = tool == core.PenTool.highlighter ? 0.25 : q;
          data[o + 5] = k * 1000 / 120;
        }
        return interop.strokeFromData(
          data,
          id: '$idPrefix-$i',
          pageId: pageId,
          style: style,
          createdAt: createdAt + i,
        );
      }(),
  ];
}

/// One cursive line of [points] points (loops of about 12 pt, 0.4 pt
/// advance per point), widthQ 0.2–0.3 along it.
InkStroke cursiveStroke(
  int points, {
  core.PenTool tool = core.PenTool.fountain,
}) {
  const stride = core.StrokePoints.stride;
  final data = Float32List(points * stride);
  for (var k = 0; k < points; k++) {
    final o = k * stride;
    data[o] = 40 + k * 0.4 + 6 * math.cos(k * 0.25);
    data[o + 1] = 300 + 9 * math.sin(k * 0.33);
    data[o + 2] = 0.25 + 0.05 * math.sin(k * 0.07);
    data[o + 5] = k * 1000 / 240;
  }
  return InkStroke.of(
    interop.strokeFromData(
      data,
      id: 'cursive-$points',
      pageId: 'p1',
      style: core.StrokeStyle.defaultsFor(tool),
      createdAt: 1000,
    ),
  );
}

/// A CORE stroke through [points] (widthQ 0.25, 120 Hz).
core.Stroke strokeAlong(
  List<ui.Offset> points, {
  required String id,
  core.PenTool tool = core.PenTool.ballpoint,
  int createdAt = 1000,
}) {
  const stride = core.StrokePoints.stride;
  final data = Float32List(points.length * stride);
  for (var k = 0; k < points.length; k++) {
    data[k * stride] = points[k].dx;
    data[k * stride + 1] = points[k].dy;
    data[k * stride + 2] = core.kNominalWidthQ;
    data[k * stride + 5] = k * 1000 / 120;
  }
  return interop.strokeFromData(
    data,
    id: id,
    pageId: 'p1',
    style: core.StrokeStyle.defaultsFor(tool),
    createdAt: createdAt,
  );
}

/// InkDevTools.syntheticStrokes on A4 (40–160 points, mean 100).
List<core.Stroke> synthetic(
  int count, {
  int seed = 1,
  core.PenTool tool = core.PenTool.ballpoint,
  String idPrefix = 's',
  core.PageSize pageSize = a4,
  int createdAt = 1000,
}) {
  var n = 0;
  return InkDevTools.syntheticStrokes(
    pageId: 'p1',
    pageSize: pageSize,
    count: count,
    newId: () => '$idPrefix-${n++}',
    createdAt: createdAt,
    seed: seed,
    tool: tool,
  );
}

/// A mixed page: [count] synthetic strokes, 80% ballpoint, 10% fountain,
/// 10% highlighter (z order = createdAt).
List<core.Stroke> mixedPage(int count, {int seed = 1}) {
  final ink = count * 8 ~/ 10, fountain = count ~/ 10;
  final hl = count - ink - fountain;
  return [
    ...synthetic(ink, seed: seed, idPrefix: 'k'),
    ...synthetic(
      fountain,
      seed: seed + 1,
      tool: core.PenTool.fountain,
      idPrefix: 'f',
      createdAt: 1000 + ink,
    ),
    ...synthetic(
      hl,
      seed: seed + 2,
      tool: core.PenTool.highlighter,
      idPrefix: 'h',
      createdAt: 1000 + ink + fountain,
    ),
  ];
}

/// The A4 page content of [strokes].
InkPageContent pageOf(List<core.Stroke> strokes, {int revision = 1}) =>
    SyntheticInk.pageContent(strokes: strokes, revision: revision);

/// Fresh CORE stroke objects with the same data (InkStroke.of caches per
/// object — B11 must not hit that cache).
List<core.Stroke> freshCopies(List<core.Stroke> strokes) => [
  for (final s in strokes) s.copyWith(),
];

/// Stylus samples of one cursive line: [count] samples at [hz], loops of
/// about 12 pt advancing 0.25 pt per sample, pressure 0.3–0.8.
List<InkSample> cursiveSamples(int count, {double hz = 240}) {
  final dtUs = 1000000 / hz;
  return [
    for (var i = 0; i < count; i++)
      InkSample(
        position: ui.Offset(
          40 + i * 0.25 + 6 * math.cos(i * 0.3),
          300 + 9 * math.sin(i * 0.39),
        ),
        timeUs: (i * dtUs).round(),
        kind: InkPointerKind.stylus,
        pressure: 0.55 + 0.25 * math.sin(i * 0.05),
      ),
  ];
}
