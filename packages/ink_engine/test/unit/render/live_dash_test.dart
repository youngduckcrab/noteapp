// m5-7/03-ink T29 (6.5 'live'): while the dashed pen writes, every dash that
// ends on the stable centerline is frozen once (append-only — the dash
// boundaries are arc lengths of the stable points), the open dash and the
// dashes on the raw tail are the tail path; after the pen lifts, the committed
// stroke's dashes are where the frozen ones were (F1 only adds the end point).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/input/pressure_detector.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/sessions.dart';
import 'package:ink_engine/src/stroke/stroke_builder.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

StrokeBuilder _builder({double width = 2, List<double>? dash}) {
  var style = core.StrokeStyle.defaultsFor(core.PenTool.dashed)
      .copyWith(width: width);
  if (dash != null) style = style.withInkExtras(dashPattern: dash);
  return StrokeBuilder(
    style: style,
    viewScale: 1,
    pressure: PressureDetector(
      kind: InkPointerKind.stylus,
      mode: PressureMode.auto,
      prior: PressureCapability.supported,
    ),
  );
}

InkSample _sample(Offset p, int i) => InkSample(
  position: p,
  timeUs: i * 8333,
  kind: InkPointerKind.stylus,
  pressure: 0.3 + 0.5 * math.sin(i / 7), // ignored: the gain is 0
);

/// Feeds [path] one sample at a time and checks the live rules after each.
List<Path> _write(StrokeBuilder b, List<Offset> path) {
  var chunks = <Path>[];
  var frozenBounds = Rect.zero;
  var version = b.live.version;
  for (var i = 0; i < path.length; i++) {
    b.add(_sample(path[i], i));
    final now = liveFrozenChunks(b.live);
    expect(now.length, greaterThanOrEqualTo(chunks.length));
    for (var k = 0; k < chunks.length; k++) {
      expect(identical(now[k], chunks[k]), isTrue, reason: 'dash $k at $i');
    }
    chunks = now;
    final fb = b.live.frozenPath.getBounds();
    if (!frozenBounds.isEmpty) {
      expect(fb.expandToInclude(frozenBounds), fb, reason: 'only grows');
    }
    frozenBounds = fb;
    expect(b.live.version, greaterThan(version));
    version = b.live.version;
  }
  return chunks;
}

/// The committed outline's contours (pieces) as bounds, in order.
List<Rect> _committedPieces(FinishedStroke f) {
  final s = InkStroke.of(
    interop.newCoreStroke(f, id: 'd', pageId: 'p', penDownMillis: 0),
  );
  expect(s.profile, same(PenProfile.dashed));
  final o = OutlineGenerator.outline(s);
  final out = <Rect>[];
  for (final poly in o.polygons) {
    var l = double.infinity, t = double.infinity;
    var r = double.negativeInfinity, bt = double.negativeInfinity;
    for (var i = 0; i < poly.length; i += 2) {
      l = math.min(l, poly[i]);
      r = math.max(r, poly[i]);
      t = math.min(t, poly[i + 1]);
      bt = math.max(bt, poly[i + 1]);
    }
    out.add(Rect.fromLTRB(l, t, r, bt));
  }
  return out;
}

void main() {
  test('a straight line: the finished dashes freeze append-only, one per '
      '[4, 3] period; the committed dashes are the frozen ones', () {
    final b = _builder();
    final path = [for (var i = 0; i <= 150; i++) Offset(40 + 2.0 * i, 300)];
    final chunks = _write(b, path);
    // 300 pt of [8, 6] pt: the dashes the stable points have finished
    expect(chunks.length, greaterThan(18));
    expect(chunks.length, lessThanOrEqualTo(22));
    for (var k = 0; k < chunks.length; k++) {
      final r = chunks[k].getBounds();
      expect(r.width, closeTo(8, 0.1), reason: 'dash $k length');
      expect(r.height, closeTo(2, 0.1), reason: 'dash $k width');
      expect(r.left, closeTo(40 + 14.0 * k, 0.1), reason: 'dash $k start');
    }
    // the open part is drawn too
    expect(b.live.tailPath.getBounds().isEmpty, isFalse);
    final f = b.finish(last: _sample(path.last, path.length))!;
    final committed = _committedPieces(f);
    expect(committed.length, greaterThanOrEqualTo(chunks.length));
    for (var k = 0; k < chunks.length; k++) {
      final live = chunks[k].getBounds();
      expect(committed[k].left, closeTo(live.left, 0.05), reason: 'dash $k');
      expect(committed[k].right, closeTo(live.right, 0.05), reason: 'dash $k');
    }
  });

  test('a gentle arc of 400 samples: append-only, and after the lift the '
      'earlier dashes stay put', () {
    final b = _builder(width: 1.5, dash: const [3, 2]);
    final path = [
      for (var i = 0; i <= 400; i++)
        Offset(
          500 + 250 * math.cos(i / 400 * math.pi),
          500 - 250 * math.sin(i / 400 * math.pi),
        ),
    ];
    final chunks = _write(b, path);
    // the arc is ≈ 785 pt; [4.5, 3] pt → ≈ 104 dashes
    expect(chunks.length, greaterThan(95));
    final f = b.finish(last: _sample(path.last, path.length))!;
    final committed = _committedPieces(f);
    expect(committed.length, greaterThanOrEqualTo(chunks.length));
    for (var k = 0; k < chunks.length; k++) {
      final live = chunks[k].getBounds().center;
      final c = committed[k].center;
      expect((c - live).distance, lessThan(0.1), reason: 'dash $k');
    }
  });

  test(
    'dots ([0, 2]): every finished dot freezes; the tail draws the rest',
    () {
      final b = _builder(width: 2, dash: const [0, 2]);
      final path = [for (var i = 0; i <= 50; i++) Offset(40 + 2.0 * i, 80)];
      final chunks = _write(b, path);
      expect(chunks.length, greaterThan(20));
      for (var k = 0; k < chunks.length; k++) {
        final r = chunks[k].getBounds();
        expect(r.width, closeTo(2, 0.01), reason: 'dot $k');
        expect(r.center.dx, closeTo(40 + 4.0 * k, 0.05), reason: 'dot $k');
      }
    },
  );

  test('a pen-down tap draws the round dot; frozen and open contours always '
      'lie inside an `on` interval of the pattern', () {
    final b = _builder(width: 2);
    b.add(_sample(const Offset(100, 100), 0));
    expect(b.live.tailPath.getBounds().width, closeTo(2, 0.01));
    void inPattern(Path p, String why) {
      for (final m in p.computeMetrics()) {
        final r = m.extractPath(0, m.length).getBounds();
        if (r.width <= 2.01) {
          // a dot (an interval shorter than 2r, D2): its center is inside
          final x = r.center.dx - 100;
          final k = (x / 14).floor();
          expect(x - 14 * k, lessThanOrEqualTo(8 + 0.05), reason: why);
          continue;
        }
        final k = ((r.left - 100) / 14).round();
        // the contour is the capsule [14k, 14k + 8] (or part of it)
        expect(
          r.left - 100,
          greaterThanOrEqualTo(14.0 * k - 0.05),
          reason: why,
        );
        expect(
          r.right - 100,
          lessThanOrEqualTo(14.0 * k + 8 + 0.05),
          reason: why,
        );
      }
    }

    for (var i = 1; i <= 120; i++) {
      b.add(_sample(Offset(100 + 0.5 * i, 100), i));
      inPattern(b.live.frozenPath, 'frozen at $i');
      inPattern(b.live.tailPath, 'tail at $i');
    }
    expect(liveFrozenChunks(b.live).length, greaterThanOrEqualTo(3));
  });

  test('the live session draws dashes through the page controller', () {
    final c = createTestPageController()
      ..updateContent(SyntheticInk.pageContent());
    addTearDown(c.dispose);
    final session = c.beginStroke(
      _sample(const Offset(50, 50), 0),
      style: core.StrokeStyle.defaultsFor(core.PenTool.dashed),
      viewScale: 1,
    );
    for (var i = 1; i <= 80; i++) {
      session.addSample(_sample(Offset(50 + 2.0 * i, 50), i));
    }
    expect(liveFrozenChunks(session.live).length, greaterThan(10));
    final edit = session.end()!;
    final stroke = InkStroke.of(edit.added.single);
    expect(stroke.profile.renderMethod, InkRenderMethod.dashedPolyline);
    expect(OutlineGenerator.outline(stroke).polygons.length, greaterThan(10));
  });
}
