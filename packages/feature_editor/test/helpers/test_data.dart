// test/helpers/test_data.dart — 04-editor 9.1 (E-01): stroke fixtures.
//
// Fixtures are built for page 0 with the placeholder page id [kFixturePageId];
// pumpEditor(strokesByPageIndex: ...) rewrites the page id to the seeded
// note's real page and keeps the stroke ids, so tests can look strokes up by
// `strokeA.id`. Viewport helpers (pageCenterOf, lassoAround, pathThrough)
// join this file with the viewport controller (E-03/E-04).
import 'package:note_core/note_core.dart' as core;

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
