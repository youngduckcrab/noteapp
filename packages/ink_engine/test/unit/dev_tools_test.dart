// T12 (03-ink 8, 4.14, contract 7.2.15): InkDevTools.syntheticStrokes — the
// same seed gives the same point bytes, count / pageId / style =
// defaultsFor(tool), every point on the page, createdAt = base + i,
// version == null so the result goes into core.AddStrokes as is (executed on
// the CORE fake store), highlighter widthQ 0.25.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/synthetic_checksum.dart';

List<core.Stroke> _make({
  core.PageSize size = core.PageSize.a4Portrait,
  int count = 20,
  int seed = 1,
  core.PenTool tool = core.PenTool.ballpoint,
  String pageId = 'p1',
  core.EpochMillis createdAt = 1000,
  String prefix = 'g',
}) => InkDevTools.syntheticStrokes(
  pageId: pageId,
  pageSize: size,
  count: count,
  newId: core.SequentialIdGenerator(prefix: prefix).newId,
  createdAt: createdAt,
  seed: seed,
  tool: tool,
);

void main() {
  test('the same seed gives the same point bytes; another seed does not', () {
    for (final tool in core.PenTool.values) {
      final a = _make(seed: 5, tool: tool), b = _make(seed: 5, tool: tool);
      expect(a, hasLength(b.length));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].points.rawData, b[i].points.rawData, reason: '$tool #$i');
        expect(a[i].points.contentEquals(b[i].points), isTrue);
      }
    }
    final c = _make(seed: 6);
    final a = _make(seed: 5);
    expect(a.first.points.contentEquals(c.first.points), isFalse);
    // seed 0 and negative seeds are normalized, still deterministic
    for (final seed in [0, -3, 2147483647, 1099511627776]) {
      final x = _make(seed: seed, count: 3), y = _make(seed: seed, count: 3);
      for (var i = 0; i < 3; i++) {
        expect(x[i].points.contentEquals(y[i].points), isTrue);
      }
    }
  });

  test('checksum = the recorded value (test/web expects the same)', () {
    expect(syntheticChecksum(), recordedSyntheticChecksum);
  });

  test(
    'count, pageId, ids, style = defaultsFor(tool), createdAt = base + i',
    () {
      for (final tool in core.PenTool.values) {
        final ids = <String>[];
        var n = 0;
        final strokes = InkDevTools.syntheticStrokes(
          pageId: 'page-7',
          pageSize: core.PageSize.letterPortrait,
          count: 12,
          newId: () {
            final id = 'id${n++}';
            ids.add(id);
            return id;
          },
          createdAt: 1700000000000,
          tool: tool,
        );
        expect(strokes, hasLength(12));
        expect(strokes.map((s) => s.id).toList(), ids);
        for (var i = 0; i < strokes.length; i++) {
          final s = strokes[i];
          expect(s.pageId, 'page-7');
          expect(s.style, core.StrokeStyle.defaultsFor(tool));
          expect(s.createdAt, 1700000000000 + i);
          expect(s.version, isNull);
          expect(s.deletedAt, isNull);
          expect(s.points.hasTilt, isFalse);
          expect(s.points.hasAzimuth, isFalse);
        }
      }
      expect(_make(count: 0), isEmpty);
      expect(() => _make(count: -1), throwsArgumentError);
    },
  );

  test('40–160 points per stroke (mean about 100), t at 120 Hz', () {
    final strokes = _make(count: 1000, seed: 9);
    var total = 0;
    for (final s in strokes) {
      final p = s.points;
      expect(p.length, inInclusiveRange(40, 160));
      total += p.length;
      for (var k = 0; k < p.length; k++) {
        // CORE stores t on a 0.1 ms grid
        expect(p.t(k), closeTo(k * 1000 / 120, 0.051));
        expect(p.tilt(k), 0);
        expect(p.azimuth(k), 0);
      }
    }
    expect(total / strokes.length, closeTo(100, 5));
  });

  test('every point stays on the page; strokes start 24 pt inside', () {
    const sizes = [
      core.PageSize.a4Portrait,
      core.PageSize.widescreen16x9,
      core.PageSize(72, 72), // smallest page: the walk keeps hitting the edges
      core.PageSize(100, 3000),
    ];
    for (final size in sizes) {
      final strokes = _make(size: size, count: 600, seed: 21);
      var touchedEdge = false;
      for (final s in strokes) {
        final p = s.points;
        expect(p.x(0), inInclusiveRange(24 - 0.01, size.width - 24 + 0.01));
        expect(p.y(0), inInclusiveRange(24 - 0.01, size.height - 24 + 0.01));
        for (var k = 0; k < p.length; k++) {
          final x = p.x(k), y = p.y(k);
          expect(x >= 0 && x <= size.width, isTrue, reason: '$size x $x');
          expect(y >= 0 && y <= size.height, isTrue, reason: '$size y $y');
          if (x == 0 || y == 0 || x >= size.width - 0.02) touchedEdge = true;
          if (y >= size.height - 0.02) touchedEdge = true;
        }
        final b = s.points.pointBounds;
        // handwriting-like: a few letters long, never a page-wide scribble
        expect(b.right - b.left, lessThanOrEqualTo(160));
        expect(b.bottom - b.top, lessThanOrEqualTo(160));
        expect(
          (b.right - b.left) + (b.bottom - b.top),
          greaterThan(0),
          reason: 'the pen moves',
        );
      }
      if (size.width == 72) expect(touchedEdge, isTrue);
    }
  });

  test('widthQ: random walk in [0.2, 0.3]; highlighter fixed at 0.25', () {
    for (final tool in core.PenTool.values) {
      final strokes = _make(count: 50, seed: 4, tool: tool);
      var varies = false;
      for (final s in strokes) {
        final p = s.points;
        for (var k = 0; k < p.length; k++) {
          if (tool == core.PenTool.highlighter) {
            expect(p.widthQ(k), core.kNominalWidthQ);
          } else {
            expect(p.widthQ(k), inInclusiveRange(0.2 - 1e-6, 0.3 + 1e-6));
            if (p.widthQ(k) != p.widthQ(0)) varies = true;
          }
        }
      }
      expect(varies, tool != core.PenTool.highlighter);
    }
  });

  test('the strokes are valid for core.AddStrokes (CORE fake store)', () async {
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final note = await store.library.createNote(title: 'synthetic');
    final session = await store.openSession(note.id);
    addTearDown(session.close);
    final page = session.pages.single;
    await session.openPage(page.id);
    final strokes = InkDevTools.syntheticStrokes(
      pageId: page.id,
      pageSize: page.size,
      count: 300,
      newId: store.ids.newId,
      createdAt: 100,
      seed: 2,
    );
    session.execute(core.AddStrokes(pageId: page.id, strokes: strokes));
    final content = session.pageIfLoaded(page.id)!;
    expect(content.strokes.map((s) => s.id).toList(), [
      for (final s in strokes) s.id,
    ]);
    for (var i = 0; i < strokes.length; i++) {
      expect(
        content.strokes[i].points.contentEquals(strokes[i].points),
        isTrue,
      );
    }
    // and INK draws them in createdAt (z) order
    final ink = InkPageContent.fromCore(
      page: content.page,
      strokes: content.strokes,
      revision: content.revision,
    );
    expect(ink.strokes.map((s) => s.id).toList(), [
      for (final s in strokes) s.id,
    ]);
  });
}
