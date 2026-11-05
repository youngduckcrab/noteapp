// T15 (03-ink 6.19): the stroke eraser. The capsule from one sample to the
// next fills the gap, so samples 50 pt apart still erase every stroke in
// between; contact is exact ink (not bounds); core.StrokeFilter picks the
// tools; nothing touched → null; one gesture = one InkEdit = one
// core.RemoveStrokes = one undo step.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../../support/pixels.dart';

final _pen = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
final _hl = core.StrokeStyle.defaultsFor(core.PenTool.highlighter);

InkSample _at(double x, double y, [int i = 0]) => InkSample(
  position: ui.Offset(x, y),
  timeUs: i * 8333,
  kind: InkPointerKind.stylus,
);

/// One eraser gesture through [points] (the first one is the pen-down).
InkEdit? _erase(
  InkPageController c,
  List<ui.Offset> points, {
  double radius = 2,
  EraserMode mode = EraserMode.stroke,
  core.StrokeFilter filter = core.StrokeFilter.all,
  bool lastInEnd = false,
}) {
  final s = c.beginErase(
    _at(points.first.dx, points.first.dy),
    spec: EraserSpec(mode: mode, radius: radius, filter: filter),
    viewScale: 1,
  );
  final rest = points.skip(1).toList();
  final last = lastInEnd && rest.isNotEmpty ? rest.removeLast() : null;
  for (var i = 0; i < rest.length; i++) {
    s.addSample(_at(rest[i].dx, rest[i].dy, i + 1));
  }
  return s.end(last == null ? null : _at(last.dx, last.dy, points.length));
}

void main() {
  late InkPageController c;
  setUp(() => c = createTestPageController());
  tearDown(() => c.dispose());

  InkPageContent load(List<core.Stroke> strokes) {
    final content = SyntheticInk.pageContent(strokes: strokes);
    c.updateContent(content);
    return content;
  }

  test('samples 50 pt apart erase every stroke in between', () {
    // 40 short vertical strokes at x = 12, 24, …, 480 around y = 300
    load([
      for (var k = 1; k <= 40; k++)
        strokeThrough(
          segment(ui.Offset(12.0 * k, 290), ui.Offset(12.0 * k, 310)),
          _pen,
          id: 'v$k',
          createdAt: 1000 + k * 10,
        ),
    ]);
    // samples at x = 0, 50, …, 500 — most strokes lie between two samples
    final edit = _erase(c, [
      for (var x = 0.0; x <= 500; x += 50) ui.Offset(x, 300),
    ]);
    expect(edit, isNotNull);
    expect(edit!.kind, InkEditKind.eraseStrokes);
    expect(edit.removedIds, {for (var k = 1; k <= 40; k++) 'v$k'});
    // z order
    expect(edit.removedIds.toList(), [for (var k = 1; k <= 40; k++) 'v$k']);
  });

  test('contact is exact ink: inside the bounds, away from the ink → kept', () {
    load([
      strokeThrough(
        [const ui.Offset(100, 100), const ui.Offset(300, 300)],
        _pen,
        id: 'diag',
      ),
    ]);
    // passes through the bounds' top-right corner region, ~50 pt from the ink
    expect(
      _erase(c, [const ui.Offset(240, 110), const ui.Offset(290, 110)]),
      isNull,
    );
    expect(c.pendingIds, isEmpty);
    // crossing the ink between two samples far from it
    final edit = _erase(c, [
      const ui.Offset(150, 250),
      const ui.Offset(250, 150),
    ]);
    expect(edit?.removedIds, {'diag'});
  });

  test('the pen-down disc alone erases; end(last) adds the last segment', () {
    load([
      strokeThrough(
        segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
        _pen,
        id: 'a',
      ),
      strokeThrough(
        segment(const ui.Offset(50, 400), const ui.Offset(150, 400)),
        _pen,
        id: 'b',
      ),
    ]);
    expect(_erase(c, [const ui.Offset(100, 52)])?.removedIds, {'a'});
    c.discardEdit(
      InkEdit(
        pageId: c.pageId,
        kind: InkEditKind.eraseStrokes,
        removedIds: const {'a'},
      ),
    );
    // the last sample only reaches 'b' through end(last)
    final edit = _erase(c, [
      const ui.Offset(300, 300),
      const ui.Offset(100, 300),
      const ui.Offset(100, 450),
    ], lastInEnd: true);
    expect(edit?.removedIds, {'b'});
  });

  test('radius: the eraser reaches exactly R + r from the centerline', () {
    // ballpoint 1.6 at nominal widthQ → r = 0.8; eraser R = 5 → reach 5.8
    load([
      strokeThrough(
        segment(const ui.Offset(50, 100), const ui.Offset(250, 100)),
        _pen,
        id: 'line',
      ),
    ]);
    expect(
      _erase(c, [
        const ui.Offset(60, 105.85),
        const ui.Offset(240, 105.85),
      ], radius: 5),
      isNull,
    );
    expect(
      _erase(c, [
        const ui.Offset(60, 105.75),
        const ui.Offset(240, 105.75),
      ], radius: 5)?.removedIds,
      {'line'},
    );
  });

  group('core.StrokeFilter', () {
    // a pen line crossing a highlighter line
    void loadCross() => load([
      strokeThrough(
        segment(const ui.Offset(100, 200), const ui.Offset(300, 200)),
        _hl,
        id: 'hl',
        createdAt: 1000,
      ),
      strokeThrough(
        segment(const ui.Offset(200, 100), const ui.Offset(200, 300)),
        _pen,
        id: 'pen',
        createdAt: 2000,
      ),
    ]);
    const through = [ui.Offset(190, 190), ui.Offset(210, 210)];

    test('all → both', () {
      loadCross();
      expect(_erase(c, through)?.removedIds, {'hl', 'pen'});
    });

    test('highlighterOnly → the highlighter only', () {
      loadCross();
      final edit = _erase(
        c,
        through,
        filter: core.StrokeFilter.highlighterOnly,
      );
      expect(edit?.removedIds, {'hl'});
    });

    test('exceptHighlighter → everything but the highlighter', () {
      loadCross();
      final edit = _erase(
        c,
        through,
        filter: core.StrokeFilter.exceptHighlighter,
      );
      expect(edit?.removedIds, {'pen'});
    });

    test('a filter that excludes everything touched → null', () {
      load([
        strokeThrough(
          segment(const ui.Offset(100, 200), const ui.Offset(300, 200)),
          _pen,
          id: 'pen',
        ),
      ]);
      expect(
        _erase(c, through, filter: core.StrokeFilter.highlighterOnly),
        isNull,
      );
    });
  });

  test('nothing touched → null, no pending display, no command', () {
    load([
      strokeThrough(
        segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
        _pen,
        id: 'a',
      ),
    ]);
    final s = c.beginErase(
      _at(400, 400),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 10),
      viewScale: 1,
    );
    for (var i = 1; i < 20; i++) {
      s.addSample(_at(400 + i * 5.0, 400, i));
    }
    expect(s.touchedStrokeIds, isEmpty);
    expect(s.end(), isNull);
    expect(c.pendingIds, isEmpty);
    expect(c.activeSession, isNull);
    // no content at all
    final empty = createTestPageController();
    addTearDown(empty.dispose);
    expect(_erase(empty, [const ui.Offset(10, 10)]), isNull);
  });

  test('touchedStrokeIds grows during the gesture (hidden preview)', () {
    load([
      for (var k = 0; k < 5; k++)
        strokeThrough(
          segment(ui.Offset(50.0 + 40 * k, 80), ui.Offset(50.0 + 40 * k, 120)),
          _pen,
          id: 'k$k',
        ),
    ]);
    final s = c.beginErase(
      _at(30, 100),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 2),
      viewScale: 1,
    );
    final seen = <int>[];
    for (var i = 1; i <= 10; i++) {
      s.addSample(_at(30 + i * 20.0, 100, i));
      seen.add(s.touchedStrokeIds.length);
    }
    expect(seen, [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
    // a stroke already touched is not touched twice (back and forth)
    s.addSample(_at(30, 100, 11));
    expect(s.touchedStrokeIds.length, 5);
    expect(s.end()!.removedIds.length, 5);
  });

  test('strokes hidden by a pending erase are not erased again', () {
    load([
      strokeThrough(
        segment(const ui.Offset(50, 50), const ui.Offset(150, 50)),
        _pen,
        id: 'a',
      ),
    ]);
    final first = _erase(c, [const ui.Offset(100, 50)]);
    expect(first?.removedIds, {'a'});
    expect(_erase(c, [const ui.Offset(100, 50)]), isNull);
  });

  test('one gesture → one InkEdit → one core.RemoveStrokes (z order)', () {
    load([
      for (var k = 0; k < 6; k++)
        strokeThrough(
          segment(ui.Offset(50, 50.0 + 30 * k), ui.Offset(250, 50.0 + 30 * k)),
          _pen,
          id: 'h$k',
          createdAt: 5000 - k * 100, // later rows are lower in z
        ),
    ]);
    // a zig-zag over every row, 30 samples
    final edit = _erase(c, [
      for (var i = 0; i < 30; i++) ui.Offset(i.isEven ? 60 : 240, 40 + i * 6.5),
    ]);
    expect(edit, isNotNull);
    final command = edit!.toCommand();
    expect(command, isA<core.RemoveStrokes>());
    final remove = command as core.RemoveStrokes;
    expect(remove.pageId, c.pageId);
    expect(remove.strokeIds, ['h5', 'h4', 'h3', 'h2', 'h1', 'h0']);
  });

  group('with the CORE fake store', () {
    late core.NoteStore store;
    late core.NoteSession session;
    late StreamSubscription<core.PageContentChange> sub;
    late InkPageController controller;
    late String pageId;

    InkPageContent inkContentOf(core.PageContent p) => InkPageContent.fromCore(
      page: p.page,
      strokes: p.strokes,
      revision: p.revision,
    );

    core.Stroke line(String id, double y, int createdAt) {
      final pts = segment(ui.Offset(20, y), ui.Offset(220, y));
      const stride = core.StrokePoints.stride;
      final data = Float32List(pts.length * stride);
      for (var i = 0; i < pts.length; i++) {
        data[i * stride] = pts[i].dx;
        data[i * stride + 1] = pts[i].dy;
        data[i * stride + 2] = core.kNominalWidthQ;
        data[i * stride + 5] = i * 10.0;
      }
      return interop.strokeFromData(
        data,
        id: id,
        pageId: pageId,
        style: _pen,
        createdAt: createdAt,
      );
    }

    setUp(() async {
      store = core_testing.createFakeNoteStore();
      final note = await store.library.createNote(title: 'T15 eraser');
      session = await store.openSession(note.id);
      pageId = session.pages.single.id;
      final loaded = await session.openPage(pageId);
      controller = createTestPageController(
        pageId: pageId,
        services: testInkCoreServices(idPrefix: 'ink'),
      )..updateContent(inkContentOf(loaded));
      sub = session
          .pageChanges(pageId)
          .listen((ch) => controller.updateContent(inkContentOf(ch.content)));
      session.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [
            for (var k = 0; k < 5; k++) line('r$k', 100.0 + 40 * k, k + 1),
          ],
        ),
      );
      await session.flush();
    });

    tearDown(() async {
      await sub.cancel();
      controller.dispose();
      await session.close();
      await store.close();
    });

    test('one fast scrub = one command = one undo step', () async {
      final undoBefore = session.history.undoDepth;
      // fast vertical pass: 3 samples 120 pt apart cross rows 0–4
      final edit = _erase(controller, const [
        ui.Offset(100, 80),
        ui.Offset(100, 200),
        ui.Offset(100, 320),
      ]);
      expect(edit?.removedIds, {'r0', 'r1', 'r2', 'r3', 'r4'});
      session.execute(edit!.toCommand());
      expect(controller.pendingIds, isEmpty);
      expect(controller.content!.strokes, isEmpty);
      expect(session.history.undoDepth, undoBefore + 1);
      await session.undo();
      expect(
        [for (final s in controller.content!.strokes) s.id],
        ['r0', 'r1', 'r2', 'r3', 'r4'],
      );
    });
  });
}
