// test/helpers/test_data.dart — 04-editor 9.1 (E-01): stroke fixtures.
//
// Fixtures are built for page 0 with the placeholder page id [kFixturePageId];
// pumpEditor(strokesByPageIndex: ...) rewrites the page id to the seeded
// note's real page and keeps the stroke ids, so tests can look strokes up by
// `strokeA.id`. The screen helpers (pageCenterOf, pathThrough, lassoAround)
// turn page points into global positions through the editor's viewport
// (E-08).
import 'dart:ui' show Offset, Rect;

import 'package:note_core/note_core.dart' as core;

import 'pump_editor.dart';

/// Page id the fixtures are made with (replaced when they are seeded).
const String kFixturePageId = 'fixture-page';

/// A4 portrait in pt (CORE PageSize.a4Portrait).
const core.PageSize kA4 = core.PageSize.a4Portrait;

/// A straight stroke from ([x0], [y0]) to ([x1], [y1]) in page pt, with
/// [pointCount] evenly spaced points 8 ms apart and the nominal width channel.
core.Stroke lineStroke({
  required core.ElementId id,
  required double x0,
  required double y0,
  required double x1,
  required double y1,
  core.PageId pageId = kFixturePageId,
  int pointCount = 20,
  core.PenTool tool = core.PenTool.ballpoint,
  core.EpochMillis createdAt = 0,
}) {
  if (pointCount < 2) {
    throw ArgumentError.value(pointCount, 'pointCount', 'must be >= 2');
  }
  final b = core.StrokePointsBuilder(initialCapacity: pointCount);
  for (var i = 0; i < pointCount; i++) {
    final f = i / (pointCount - 1);
    b.add(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, t: i * 8.0);
  }
  return core.Stroke(
    id: id,
    pageId: pageId,
    style: core.StrokeStyle.defaultsFor(tool).normalized(),
    points: b.build(),
    createdAt: createdAt,
  );
}

/// Horizontal ballpoint stroke in the upper left of page 0.
final core.Stroke strokeA = lineStroke(
  id: 'stroke-a',
  x0: 100,
  y0: 150,
  x1: 220,
  y1: 150,
  createdAt: 1,
);

/// Horizontal ballpoint stroke further down page 0 (no overlap with A).
final core.Stroke strokeB = lineStroke(
  id: 'stroke-b',
  x0: 100,
  y0: 400,
  x1: 260,
  y1: 400,
  createdAt: 2,
);

/// Highlighter stroke crossing the middle of page 0.
final core.Stroke highlighterStroke = lineStroke(
  id: 'stroke-h',
  x0: 80,
  y0: 300,
  x1: 400,
  y1: 300,
  tool: core.PenTool.highlighter,
  createdAt: 3,
);

// ---- screen positions (global, for PointerDriver) -----------------------------

/// Global position of the centre of page [pageIndex].
Offset pageCenterOf(EditorTestHandles h, int pageIndex) {
  final size = h.session.pages[pageIndex].size;
  return h.toGlobal(pageIndex, Offset(size.width / 2, size.height / 2));
}

/// Global positions of [pagePoints] (pt) on page [pageIndex].
List<Offset> pathThrough(
  EditorTestHandles h,
  int pageIndex,
  List<Offset> pagePoints,
) => [for (final p in pagePoints) h.toGlobal(pageIndex, p)];

/// A closed lasso path (global) around [pageRect] (pt) on page [pageIndex],
/// [margin] pt outside it, [perSide] points per side.
List<Offset> lassoAround(
  EditorTestHandles h,
  int pageIndex,
  Rect pageRect, {
  double margin = 8,
  int perSide = 4,
}) {
  final r = pageRect.inflate(margin);
  final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  final points = <Offset>[];
  for (var c = 0; c < 4; c++) {
    final a = corners[c];
    final b = corners[(c + 1) % 4];
    for (var i = 0; i < perSide; i++) {
      points.add(Offset.lerp(a, b, i / perSide)!);
    }
  }
  points.add(corners.first);
  return pathThrough(h, pageIndex, points);
}
