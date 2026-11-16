// R2-B3 smoke (m5-7/03-ink 8.1 T25, 4.13): the CORE fake store + objects of every
// kind (PageObjectFixtures) drawn by a real InkPageView — pixels in each L-1
// layer (an upper layer's color where they overlap), lasso of strokes + objects →
// one TransformElements → pending empty after updateContent, delete →
// RemoveElements, duplicate / recolor → Composite, the eraser removes shapes only,
// hidden → no pixels, previews (also over a hidden id) → pixels with the content
// unchanged, laser end() == null (K-9 — since m5-7 T30 its trail fades out
// over laserFadeMs after the lift), tape state, hitTestTape by bounds,
// hitTestRecorded, hitTestObject order (since T37a the shape rule of 6.14: the
// outline, not the frame).
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf, repaintInkLayer;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../support/page_view.dart';
import '../support/pixels.dart';

const _green = 0xFF00AA00;
const _red = 0xFFDD0000;
const _blue = 0xFF0000FF;

/// One note page of the CORE fake store wired to a controller like EDITOR does.
final class _Harness {
  _Harness._(this.store, this.session, this.pageId, this.controller);

  final core.NoteStore store;
  final core.NoteSession session;
  final String pageId;
  final InkPageController controller;
  late final StreamSubscription<core.PageContentChange> _sub;

  static Future<_Harness> open(WidgetTester tester) async {
    final h = (await tester.runAsync(() async {
      final store = createFakeNoteStore();
      final note = await store.library.createNote(title: 'B3 v2');
      final session = await store.openSession(note.id);
      final pageId = session.pages.single.id;
      final loaded = await session.openPage(pageId);
      final controller = createTestPageController(
        pageId: pageId,
        services: testInkCoreServices(idPrefix: 'ink'),
      )..updateContent(_inkOf(loaded));
      return _Harness._(store, session, pageId, controller);
    }))!;
    h._listen();
    addTearDown(() => tester.runAsync(h._close));
    return h;
  }

  /// EDITOR's wiring: every page change feeds the controller.
  void _listen() {
    _sub = session
        .pageChanges(pageId)
        .listen((c) => controller.updateContent(_inkOf(c.content)));
  }

  Future<void> _close() async {
    await _sub.cancel();
    controller.dispose();
    await session.close();
    await store.close();
  }

  static InkPageContent _inkOf(core.PageContent c) => InkPageContent.fromCore(
    page: c.page,
    strokes: c.strokes,
    objects: c.objects,
    revision: c.revision,
  );

  InkPageContent get content => controller.content!;

  void run(core.EditCommand command) => session.execute(command);

  /// Executes [edit] like EDITOR: toCommand → execute; the pending display ends.
  void commit(InkEdit edit) {
    run(edit.toCommand());
    expect(controller.pendingIds, isEmpty, reason: 'pending resolved');
  }

  core.Stroke line(
    String id,
    Offset a,
    Offset b, {
    core.PenTool tool = core.PenTool.ballpoint,
    int color = _blue,
    double width = 4,
    int createdAt = 10,
    String? recordingId,
  }) {
    final pts = segment(a, b);
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
      style: core.StrokeStyle.defaultsFor(tool)
          .copyWith(colorArgb: color, width: width),
      createdAt: createdAt,
      recordingId: recordingId,
      recordingOffsetMs: recordingId == null ? null : 100,
    );
  }
}

Future<Pixels> _pump(WidgetTester tester, _Harness h) async {
  await pumpPageView(
    tester,
    h.controller,
    width: h.content.pageSize.width, // viewScale 1: page pt = logical px
    surface: const Size(620, 860),
  );
  await tester.pump();
  return capturePixels(tester);
}

bool _isPaper(List<int> p) => samePixel(p, const [255, 255, 255, 255], tol: 2);

int _inkedIn(Pixels p, Rect r) {
  var n = 0;
  for (var y = r.top.ceil(); y < r.bottom.floor(); y++) {
    for (var x = r.left.ceil(); x < r.right.floor(); x++) {
      if (!_isPaper(p.at(x, y))) n++;
    }
  }
  return n;
}

void main() {
  testWidgets('every object kind draws in its L-1 layer', (tester) async {
    final h = await _Harness.open(tester);
    final image = PageObjectFixtures.image(
      pageId: h.pageId,
      assetId: 'asset-none',
      id: 'img',
      rect: const core.PageRect(50, 50, 250, 130),
      createdAt: 1,
    );
    final shape = core.ShapeObject(
      id: 'sh',
      pageId: h.pageId,
      shapeKind: core.ShapeKind.rectangle,
      geometry: core.ShapeGeometry.rectangle(
        const core.PageRect(80, 180, 220, 230),
      ),
      style: const core.ShapeStyle(strokeColorArgb: _red, strokeWidth: 4),
      createdAt: 5,
    );
    final box = core.TextBoxObject(
      id: 'bg',
      pageId: h.pageId,
      frame: const core.ElementFrame(core.PageRect(150, 90, 250, 160)),
      text: '',
      style: const core.TextBoxStyle(backgroundArgb: _green),
      createdAt: 6,
    );
    final text = PageObjectFixtures.textBox(
      pageId: h.pageId,
      id: 'tx',
      text: 'hello 안녕',
      rect: const core.PageRect(300, 400, 500, 440),
      createdAt: 7,
    );
    final math = PageObjectFixtures.math(
      pageId: h.pageId,
      id: 'mx',
      rect: const core.PageRect(300, 300, 400, 350),
      createdAt: 8,
    );
    final unknown = PageObjectFixtures.unknown(
      pageId: h.pageId,
      id: 'un',
      rect: const core.PageRect(400, 100, 450, 150),
    );
    h
      ..run(
        core.AddObjects(
          pageId: h.pageId,
          objects: [image, shape, box, text, math, unknown],
        ),
      )
      ..run(
        core.AddStrokes(
          pageId: h.pageId,
          strokes: [
            h.line(
              'hl',
              const Offset(60, 100),
              const Offset(240, 100),
              tool: core.PenTool.highlighter,
              color: 0xFFFFE600,
              width: 12,
              createdAt: 2,
            ),
            h.line(
              'ink',
              const Offset(60, 150),
              const Offset(240, 150),
              createdAt: 3,
            ),
          ],
        ),
      );
    expect(h.content.objects, hasLength(6));
    final px = await _pump(tester, h);

    // underlay: the image placeholder (a paper-contrast gray, darker than the paper)
    final img = px.at(60, 60);
    expect(img[0], lessThan(250));
    expect((img[0] - img[2]).abs(), lessThanOrEqualTo(2));
    // highlighter over the image (multiply: blue channel drops)
    final hl = px.at(100, 100);
    expect(hl[2], lessThan(hl[0] - 40));
    // ink stroke
    final ink = px.at(100, 150);
    expect(ink[2], greaterThan(ink[0] + 100));
    // annotation above highlighter and ink: the text box background
    expect(samePixel(px.at(200, 100), const [0, 170, 0, 255], tol: 2), isTrue);
    expect(samePixel(px.at(200, 150), const [0, 170, 0, 255], tol: 2), isTrue);
    // shape outline (ink layer)
    final edge = px.at(80, 205);
    expect(edge[0], greaterThan(180));
    expect(edge[1], lessThan(90));
    expect(_isPaper(px.at(150, 205)), isTrue, reason: 'no fill in R2-B3');
    // formula: drawn in its frame (its raster — the light box before it
    // arrives; (math resize fix) a pixel probe at the fraction bar is not
    // stable across raster buckets, so count the frame's ink);
    // unknown object: hatched box; text: glyphs
    expect(
      _inkedIn(px, const Rect.fromLTWH(301, 301, 98, 48)),
      greaterThan(20),
    );
    expect(
      _inkedIn(px, const Rect.fromLTWH(401, 101, 48, 48)),
      greaterThan(100),
    );
    expect(
      _inkedIn(px, const Rect.fromLTWH(300, 400, 200, 40)),
      greaterThan(20),
    );
    // nothing outside the frames (K-6)
    expect(_inkedIn(px, const Rect.fromLTWH(455, 160, 100, 100)), 0);

    // hitTestObject: annotation → ink → underlay
    expect(h.controller.hitTestObject(const Offset(200, 120))?.id, 'bg');
    expect(h.controller.hitTestObject(const Offset(100, 60))?.id, 'img');
    // (m5-7 T37a, 6.14) a shape takes the tap on its outline; the inside of an
    // unfilled shape falls through to what is below (here nothing)
    expect(h.controller.hitTestObject(const Offset(150, 181))?.id, 'sh');
    expect(h.controller.hitTestObject(const Offset(150, 205)), isNull);
    expect(h.controller.hitTestObject(const Offset(425, 125))?.id, 'un');
    expect(h.controller.hitTestObject(const Offset(560, 800)), isNull);
  });

  testWidgets(
    'lasso → move → one TransformElements; duplicate, recolor, delete',
    (tester) async {
      final h = await _Harness.open(tester);
      final shape = PageObjectFixtures.shape(
        pageId: h.pageId,
        id: 'sh',
        rect: const core.PageRect(80, 180, 220, 230),
        createdAt: 5,
      );
      final far = PageObjectFixtures.textBox(
        pageId: h.pageId,
        id: 'far',
        rect: const core.PageRect(300, 600, 500, 640),
        createdAt: 6,
      );
      h
        ..run(core.AddObjects(pageId: h.pageId, objects: [shape, far]))
        ..run(
          core.AddStrokes(
            pageId: h.pageId,
            strokes: [
              h.line('ink', const Offset(60, 150), const Offset(240, 150)),
            ],
          ),
        );
      await _pump(tester, h);
      final lasso = h.controller.beginLasso(
        const Offset(55, 140),
        viewScale: 1,
      );
      for (final p in const [
        Offset(245, 140),
        Offset(245, 240),
        Offset(55, 240),
        Offset(55, 141),
      ]) {
        lasso.addPoint(p);
      }
      final sel = lasso.end()!;
      expect(sel.strokeIds, {'ink'});
      expect(sel.objectIds, {'sh'});
      expect(sel.allIds, ['sh', 'ink']); // z order: the shape is older
      expect(sel.objects, [same(h.content.objects.first)]);
      expect(sel.bounds.top, lessThanOrEqualTo(148));
      expect(sel.bounds.bottom, greaterThanOrEqualTo(230));

      // live preview: the shape moves on screen, the content does not
      sel.setPreviewTransform(core.Affine2.translation(0, 300));
      var px = await _pump(tester, h);
      expect(_isPaper(px.at(80, 205)), isTrue, reason: 'original place hidden');
      expect(_isPaper(px.at(80, 505)), isFalse, reason: 'preview drawn');
      final edit = sel.commitTransform()!;
      expect(edit.kind, InkEditKind.transformStrokes);
      expect(edit.targetIds, {'ink', 'sh'});
      final cmd = edit.toCommand();
      expect(
        cmd,
        isA<core.TransformElements>().having(
          (c) => c.elementIds,
          'elementIds',
          ['sh', 'ink'],
        ),
      );
      h.commit(edit);
      final moved = h.content.objects.firstWhere((o) => o.id == 'sh');
      expect(moved.bounds.top, closeTo(shape.bounds.top + 300, 1e-6));
      px = await _pump(tester, h);
      expect(_isPaper(px.at(80, 505)), isFalse);

      // duplicate → Composite[AddStrokes, AddObjects]
      final dup = h.controller.select({'ink', 'sh'}).duplicate();
      final dupCmd = dup.toCommand();
      expect(dupCmd, isA<core.CompositeCommand>());
      expect(
        (dupCmd as core.CompositeCommand).commands.map((c) => c.runtimeType),
        [core.AddStrokes, core.AddObjects],
      );
      h.commit(dup);
      expect(h.content.strokes, hasLength(2));
      expect(h.content.objects, hasLength(3));

      // recolor → Composite[RestyleStrokes, UpdateObjects]
      final recolor = h.controller.select({'ink', 'sh', 'far'}).recolor(_green);
      final recolorCmd = recolor.toCommand() as core.CompositeCommand;
      expect(recolorCmd.commands.map((c) => c.runtimeType), [
        core.RestyleStrokes,
        core.UpdateObjects,
      ]);
      h.commit(recolor);
      final recolored = h.content.objects.firstWhere((o) => o.id == 'sh');
      expect((recolored as core.ShapeObject).style.strokeColorArgb, _green);
      final recoloredText = h.content.objects.firstWhere((o) => o.id == 'far');
      expect((recoloredText as core.TextBoxObject).style.colorArgb, _green);

      // delete → RemoveElements
      final del = h.controller.select({'ink', 'sh'}).delete();
      expect(del.removedObjectIds, {'sh'});
      expect(del.toCommand(), isA<core.RemoveElements>());
      h.commit(del);
      expect(h.content.strokes.map((s) => s.id), isNot(contains('ink')));
      expect(h.content.objects.map((o) => o.id), isNot(contains('sh')));
    },
  );

  testWidgets('the eraser removes shapes whole and never text boxes', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    final shape = PageObjectFixtures.shape(
      pageId: h.pageId,
      id: 'sh',
      rect: const core.PageRect(100, 100, 200, 160),
    );
    final text = PageObjectFixtures.textBox(
      pageId: h.pageId,
      id: 'tx',
      rect: const core.PageRect(100, 200, 300, 240),
    );
    h.run(core.AddObjects(pageId: h.pageId, objects: [shape, text]));
    await _pump(tester, h);
    for (final mode in EraserMode.values) {
      if (h.content.objects.length < 2) {
        h.run(
          core.AddObjects(
            pageId: h.pageId,
            objects: [
              PageObjectFixtures.shape(
                pageId: h.pageId,
                id: 'sh2',
                rect: const core.PageRect(100, 100, 200, 160),
              ),
            ],
          ),
        );
      }
      final e = h.controller.beginErase(
        SyntheticInk.line(const Offset(150, 90), const Offset(150, 260)).first,
        spec: EraserSpec(mode: mode, radius: 6),
        viewScale: 1,
      );
      for (final s in SyntheticInk.line(
        const Offset(150, 90),
        const Offset(150, 260),
      )) {
        e.addSample(s);
      }
      final edit = e.end()!;
      expect(edit.removedObjectIds, hasLength(1), reason: mode.name);
      expect(edit.removedObjectIds.single, startsWith('sh'));
      expect(edit.toCommand(), isA<core.RemoveElements>(), reason: mode.name);
      h.commit(edit);
      expect(h.content.objects.map((o) => o.id), ['tx'], reason: mode.name);
    }
    // highlighterOnly never erases shapes; eraseShapes: false neither
    h.run(
      core.AddObjects(
        pageId: h.pageId,
        objects: [
          PageObjectFixtures.shape(
            pageId: h.pageId,
            id: 'sh3',
            rect: const core.PageRect(100, 100, 200, 160),
          ),
        ],
      ),
    );
    for (final spec in const [
      EraserSpec(
        mode: EraserMode.stroke,
        radius: 6,
        filter: core.StrokeFilter.highlighterOnly,
      ),
      EraserSpec(mode: EraserMode.stroke, radius: 6, eraseShapes: false),
    ]) {
      final e = h.controller.beginErase(
        SyntheticInk.line(const Offset(150, 90), const Offset(150, 260)).first,
        spec: spec,
        viewScale: 1,
      );
      expect(e.end(), isNull);
    }
  });

  testWidgets('hidden objects are not drawn; previews are, even over a hidden '
      'id; the content never changes', (tester) async {
    final h = await _Harness.open(tester);
    final text = core.TextBoxObject(
      id: 'tx',
      pageId: h.pageId,
      frame: const core.ElementFrame(core.PageRect(100, 100, 300, 140)),
      text: '',
      style: const core.TextBoxStyle(backgroundArgb: _green),
      createdAt: 1,
    );
    h.run(core.AddObjects(pageId: h.pageId, objects: [text]));
    final before = h.content;
    var px = await _pump(tester, h);
    expect(_isPaper(px.at(200, 120)), isFalse);

    h.controller.setHiddenObjectIds({'tx'});
    px = await _pump(tester, h);
    expect(_isPaper(px.at(200, 120)), isTrue);
    // selection still sees a hidden object
    expect(h.controller.hitTestObject(const Offset(200, 120))?.id, 'tx');
    expect(h.controller.select({'tx'}).objectIds, {'tx'});
    h.controller.clearSelection();

    // a preview with the hidden id is drawn (preview > hidden), moved
    final draft = text.copyWith(
      frame: const core.ElementFrame(core.PageRect(100, 300, 300, 340)),
    );
    h.controller.setPreviewObjects([draft]);
    px = await _pump(tester, h);
    expect(_isPaper(px.at(200, 320)), isFalse);
    expect(_isPaper(px.at(200, 120)), isTrue, reason: 'committed one replaced');
    // a preview with a new id is drawn in its layer too
    final placed = PageObjectFixtures.shape(
      pageId: h.pageId,
      id: 'new-shape',
      rect: const core.PageRect(350, 500, 450, 560),
    );
    h.controller.setPreviewObjects([draft, placed]);
    px = await _pump(tester, h);
    expect(_isPaper(px.at(350, 530)), isFalse);
    expect(identical(h.controller.content, before), isTrue);
    expect(h.controller.hitTestObject(const Offset(400, 530)), isNull);

    h.controller
      ..setPreviewObjects(const [])
      ..setHiddenObjectIds(const {});
    px = await _pump(tester, h);
    expect(_isPaper(px.at(200, 120)), isFalse);
    expect(_isPaper(px.at(350, 530)), isTrue);
  });

  testWidgets(
    'laser end() == null; tape state and hit tests; hitTestRecorded',
    (tester) async {
      final h = await _Harness.open(tester);
      h.run(
        core.AddStrokes(
          pageId: h.pageId,
          strokes: [
            h.line(
              'tape',
              const Offset(100, 100),
              const Offset(300, 100),
              tool: core.PenTool.tape,
              width: 14,
              createdAt: 1,
            ),
            h.line(
              'rec',
              const Offset(100, 300),
              const Offset(300, 300),
              createdAt: 2,
              recordingId: 'r1',
            ),
            h.line(
              'plain',
              const Offset(100, 400),
              const Offset(300, 400),
              createdAt: 3,
            ),
          ],
        ),
      );
      await _pump(tester, h);
      final before = h.content;

      // laser (K-9): drawn while written, no edit, nothing pending, content unchanged
      final samples = SyntheticInk.line(
        const Offset(50, 600),
        const Offset(400, 650),
      );
      final laser = h.controller.beginStroke(
        samples.first,
        style: core.StrokeStyle.defaultsFor(core.PenTool.laser),
        viewScale: 1,
      )..addSamples(samples.skip(1));
      final writing = await _pump(tester, h);
      expect(
        _inkedIn(writing, const Rect.fromLTWH(40, 590, 380, 80)),
        greaterThan(50),
      );
      expect(laser.end(samples.last), isNull);
      expect(h.controller.pendingIds, isEmpty);
      expect(identical(h.controller.content, before), isTrue);
      // (m5-7 T30) the trail fades out over laserFadeMs after the lift, then is gone
      final lifted = await _pump(tester, h);
      expect(
        _inkedIn(lifted, const Rect.fromLTWH(40, 590, 380, 80)),
        greaterThan(50),
      );
      (h.controller.clock as FakeInkClock).advanceMs(
        core.StrokeStyle.defaultsFor(core.PenTool.laser).laserFadeMs + 1.0,
      );
      repaintInkLayer(h.controller, InkRenderLayer.overlay);
      final after = await _pump(tester, h);
      expect(_inkedIn(after, const Rect.fromLTWH(40, 590, 380, 80)), 0);

      // tape state (per controller, never stored)
      expect(h.controller.isTapeRevealed('tape'), isFalse);
      h.controller.toggleTape('tape');
      expect(h.controller.isTapeRevealed('tape'), isTrue);
      h.controller.toggleTape('tape');
      expect(h.controller.isTapeRevealed('tape'), isFalse);
      h.controller.toggleTape('plain'); // not a tape → ignored
      expect(h.controller.isTapeRevealed('plain'), isFalse);
      h.controller.setAllTapesRevealed(true);
      expect(h.controller.isTapeRevealed('tape'), isTrue);
      // a tape that arrives later starts covered
      h.run(
        core.AddStrokes(
          pageId: h.pageId,
          strokes: [
            h.line(
              'tape2',
              const Offset(100, 200),
              const Offset(300, 200),
              tool: core.PenTool.tape,
              width: 14,
              createdAt: 4,
            ),
          ],
        ),
      );
      expect(h.controller.isTapeRevealed('tape2'), isFalse);
      expect(h.controller.isTapeRevealed('tape'), isTrue);
      h.controller.setAllTapesRevealed(false);
      expect(h.controller.isTapeRevealed('tape'), isFalse);
      // an erased tape leaves the revealed set
      h.controller.toggleTape('tape');
      h.run(core.RemoveStrokes(pageId: h.pageId, strokeIds: const ['tape']));
      expect(h.controller.isTapeRevealed('tape'), isFalse);

      // hitTestTape: bounds
      expect(h.controller.hitTestTape(const Offset(200, 200))?.id, 'tape2');
      expect(h.controller.hitTestTape(const Offset(200, 205))?.id, 'tape2');
      expect(h.controller.hitTestTape(const Offset(200, 240)), isNull);
      expect(h.controller.hitTestTape(const Offset(200, 400)), isNull);

      // hitTestRecorded
      expect(h.controller.hitTestRecorded(const Offset(200, 303))?.id, 'rec');
      expect(
        h.controller
            .hitTestRecorded(const Offset(200, 303), recordingId: 'r1')
            ?.id,
        'rec',
      );
      expect(
        h.controller.hitTestRecorded(const Offset(200, 303), recordingId: 'r2'),
        isNull,
      );
      expect(h.controller.hitTestRecorded(const Offset(200, 400)), isNull);
      expect(h.controller.hitTestRecorded(const Offset(200, 320)), isNull);
    },
  );

  test('the renderer never throws: a bad object is skipped', () async {
    final c = createTestPageController();
    addTearDown(c.dispose);
    final weird = core.ShapeObject(
      id: 'w',
      pageId: 'p1',
      shapeKind: core.ShapeKind.line,
      geometry: core.ShapeGeometry.line(
        const core.PagePoint(10, 10),
        const core.PagePoint(10, 10),
      ),
      style: const core.ShapeStyle(
        strokeColorArgb: _red,
        strokeWidth: double.nan,
        strokeOpacity: double.nan,
      ),
      createdAt: 1,
    );
    c.updateContent(SyntheticInk.pageContentWith(objects: [weird]));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    for (final layer in InkRenderLayer.values) {
      paintLayerForTest(c, canvas, layer);
    }
    recorder.endRecording().dispose();
  });
}

/// Paints [layer] of [c] (the view's painter does the same).
void paintLayerForTest(
  InkPageController c,
  ui.Canvas canvas,
  InkRenderLayer layer,
) => inkPageRenderOf(c).paint(canvas, layer, 1);
