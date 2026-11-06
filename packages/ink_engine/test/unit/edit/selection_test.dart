// T18 (03-ink 6.22, 4.8): InkSelection edits. commitTransform →
// transformStrokes(targetIds = selection in z order, transform) →
// core.TransformElements(scaleStrokeWidth: true), identity → null;
// duplicate → new ids, createdAt = nowMillis() + z rank, moved 16 pt without
// width scaling (recording fields and t kept) → core.AddStrokes; recolor →
// alpha forced to 0xFF → core.RestyleStrokes; delete → core.RemoveStrokes;
// an empty selection throws StateError (commitTransform → null). With the
// CORE fake store the results are what CORE stores.
// (m5-7/03-ink 8.2 T37a, 6.14 — v2) Objects: bounds = strokes ∪ the objects' CORE
// bounds (a rotated one by its AABB); an UnknownObject stays in place (preview,
// commit, duplicate); duplicate ranks strokes and objects together (createdAt =
// base + z rank) and moves the copies without scaling widths or font sizes;
// recolor = shape outline (fill kept), text and math color, images and unknown
// objects left out — images only → an isEmpty edit (nothing pending, toCommand
// StateError); the preview hides the originals once (60 preview moves record the
// base chunk once). With the CORE fake store (M-2): the scale 2 preview draws
// exactly what the commit stores — shape width × 2, text box / formula font size ×
// 2 clamped to [6, 144], an image's frame only — and its pixels are the
// committed page's (< 1 % of the inked pixels differ).
// (T28, 6.4 — C2-38) Calligraphy strokes keep the round-1 matrix preview: the
// 30° rotation preview draws the pixels of the commit (CORE turns the nib angle
// with the stroke — nibAngleDeg 45 → 75), and so does the 2× scale (width and nib
// grow together) — < 1 % of the inked pixels differ.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/cache_pool.dart' show mathRasterCacheOf;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkAnnotationCacheOf, inkPageRenderOf, liveObjectsOf;
import 'package:ink_engine/src/stroke/stroke_builder.dart' show buildStroke;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../../support/pixels.dart';

final _pen = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
    .copyWith(colorArgb: 0xFF0000FF, width: 2);

/// A horizontal stroke x 20 → 120 at [y], t 0, 10, 20 …, with a recording.
core.Stroke _line(
  String id,
  double y, {
  required int createdAt,
  String pageId = 'p1',
  core.StrokeStyle? style,
}) {
  const n = 11;
  final data = Float32List(n * core.StrokePoints.stride);
  for (var i = 0; i < n; i++) {
    data[i * core.StrokePoints.stride] = 20 + i * 10.0;
    data[i * core.StrokePoints.stride + 1] = y;
    data[i * core.StrokePoints.stride + 2] = core.kNominalWidthQ;
    data[i * core.StrokePoints.stride + 5] = i * 10.0;
  }
  return interop.strokeFromData(
    data,
    id: id,
    pageId: pageId,
    style: style ?? _pen,
    createdAt: createdAt,
    recordingId: 'rec-1',
    recordingOffsetMs: 4000,
  );
}

InkPageContent _inkContentOf(core.PageContent c) => InkPageContent.fromCore(
  page: c.page,
  strokes: c.strokes,
  revision: c.revision,
);

void main() {
  // the formula rasters and the font loading need the binding (InkMathRenderer, rootBundle)
  TestWidgetsFlutterBinding.ensureInitialized();

  group('edits (plain controller)', () {
    late InkPageController c;
    setUp(() {
      c =
          createTestPageController(
            services: testInkCoreServices(idPrefix: 'n', startMillis: 9000),
          )..updateContent(
            SyntheticInk.pageContent(
              strokes: [
                _line('top', 100, createdAt: 30),
                _line('low', 140, createdAt: 10),
                _line('mid', 120, createdAt: 20),
                _line('other', 300, createdAt: 40),
              ],
            ),
          );
    });
    tearDown(() => c.dispose());

    test('commitTransform → TransformElements(scaleStrokeWidth: true)', () {
      final sel = c.select({'top', 'low', 'mid'});
      expect(sel.strokeIds.toList(), ['low', 'mid', 'top'], reason: 'z order');
      expect(sel.commitTransform(), isNull, reason: 'identity');
      final m = SelectionGeometry.resize(
        bounds: sel.bounds,
        handle: SelectionHandle.bottomRight,
        delta: const ui.Offset(20, 8),
      );
      sel.setPreviewTransform(m);
      expect(sel.previewTransform, m);
      expect(
        sel.previewBounds,
        SelectionGeometry.transformedBounds(sel.bounds, m),
      );
      final edit = sel.commitTransform()!;
      expect(edit.kind, InkEditKind.transformStrokes);
      expect(edit.targetIds.toList(), ['low', 'mid', 'top']);
      expect(edit.transform, m);
      expect(edit.pageId, 'p1');
      final cmd = edit.toCommand() as core.TransformElements;
      expect(cmd.elementIds, ['low', 'mid', 'top']);
      expect(cmd.transform, m);
      expect(cmd.scaleStrokeWidth, isTrue);
      expect(c.pendingIds, {'low', 'mid', 'top'});
    });

    test('duplicate: new ids, createdAt base + z rank, 16 pt, no width '
        'scaling, recording and t kept', () {
      final sel = c.select({'top', 'mid'});
      final sources = sel.strokes.map((s) => s.source).toList();
      final edit = sel.duplicate();
      expect(edit.kind, InkEditKind.duplicateStrokes);
      expect(edit.added.map((s) => s.id), ['n-000001', 'n-000002']);
      // base = nowMillis() at the call, k = z rank inside the selection
      final base = edit.added.first.createdAt;
      expect(base, greaterThanOrEqualTo(9000));
      expect(edit.added.map((s) => s.createdAt), [base, base + 1]);
      expect(edit.added.map((s) => s.updatedAt), [base, base + 1]);
      for (final (k, copy) in edit.added.indexed) {
        final src = sources[k];
        expect(copy.style, src.style, reason: 'width not scaled');
        expect(copy.recordingId, src.recordingId);
        expect(copy.recordingOffsetMs, src.recordingOffsetMs);
        expect(copy.version, isNull);
        expect(copy.pageId, src.pageId);
        for (var i = 0; i < src.points.length; i++) {
          expect(
            copy.points.x(i),
            closeTo(src.points.x(i) + InkTuning.duplicateOffsetPt, 0.006),
          );
          expect(
            copy.points.y(i),
            closeTo(src.points.y(i) + InkTuning.duplicateOffsetPt, 0.006),
          );
          expect(copy.points.t(i), src.points.t(i));
          expect(copy.points.widthQ(i), src.points.widthQ(i));
        }
      }
      // the copies sit above every existing stroke, in their old order
      expect(edit.added.every((s) => s.createdAt > 40), isTrue);
      final cmd = edit.toCommand() as core.AddStrokes;
      expect(cmd.strokes.map((s) => s.id), ['n-000001', 'n-000002']);
      expect(c.pendingIds, {'n-000001', 'n-000002'});
      // a custom offset
      final moved = c
          .select({'other'})
          .duplicate(offset: const ui.Offset(-5, 7));
      expect(moved.added.single.points.x(0), closeTo(15, 0.006));
      expect(moved.added.single.points.y(0), closeTo(307, 0.006));
    });

    test('recolor forces alpha 0xFF → RestyleStrokes', () {
      final sel = c.select({'mid', 'top'});
      for (final (argb, expected) in const [
        (0x00123456, 0xFF123456),
        (0x80ABCDEF, 0xFFABCDEF),
        (0xFF000000, 0xFF000000),
        (0x12FFFFFF, 0xFFFFFFFF),
      ]) {
        final edit = sel.recolor(argb);
        expect(edit.kind, InkEditKind.recolorStrokes);
        expect(edit.colorArgb, expected);
        expect(edit.targetIds.toList(), ['mid', 'top']);
        final cmd = edit.toCommand() as core.RestyleStrokes;
        expect(cmd.strokeIds, ['mid', 'top']);
        expect(cmd.patch.colorArgb, expected);
      }
    });

    test('delete → RemoveStrokes', () {
      final edit = c.select({'low', 'other'}).delete();
      expect(edit.kind, InkEditKind.deleteStrokes);
      expect(edit.removedIds.toList(), ['low', 'other']);
      final cmd = edit.toCommand() as core.RemoveStrokes;
      expect(cmd.strokeIds, ['low', 'other']);
    });

    test('empty selection: StateError, commitTransform null', () {
      final empty = c.select(const {'nope'});
      expect(empty.isEmpty, isTrue);
      expect(c.selection, isNull);
      expect(empty.bounds, ui.Rect.zero);
      expect(empty.delete, throwsStateError);
      expect(empty.duplicate, throwsStateError);
      expect(() => empty.recolor(0xFF000000), throwsStateError);
      empty.setPreviewTransform(core.Affine2.translation(5, 5));
      expect(empty.previewTransform.isIdentity, isTrue);
      expect(empty.commitTransform(), isNull);
    });

    test('a replaced selection is disposed', () {
      final first = c.select({'top'});
      final second = c.select({'mid'});
      expect(first.isDisposed, isTrue);
      expect(second.isDisposed, isFalse);
      first.setPreviewTransform(core.Affine2.translation(5, 5));
      expect(first.previewTransform.isIdentity, isTrue);
      expect(first.commitTransform(), isNull);
      expect(first.delete, throwsStateError);
      c.clearSelection();
      expect(second.isDisposed, isTrue);
      expect(c.selection, isNull);
    });
  });

  group('with the CORE fake store', () {
    late core.NoteStore store;
    late core.NoteSession session;
    late String pageId;
    late InkPageController controller;
    late StreamSubscription<core.PageContentChange> sub;

    setUp(() async {
      store = core_testing.createFakeNoteStore();
      final note = await store.library.createNote(title: 'T18 selection');
      session = await store.openSession(note.id);
      pageId = session.pages.single.id;
      final loaded = await session.openPage(pageId);
      controller = createTestPageController(
        pageId: pageId,
        services: testInkCoreServices(idPrefix: 'ink', startMillis: 100000),
      )..updateContent(_inkContentOf(loaded));
      sub = session
          .pageChanges(pageId)
          .listen((ch) => controller.updateContent(_inkContentOf(ch.content)));
      session.execute(
        core.AddStrokes(
          pageId: pageId,
          strokes: [
            _line('a', 100, createdAt: 1000, pageId: pageId),
            _line('b', 130, createdAt: 2000, pageId: pageId),
          ],
        ),
      );
      expect(controller.content!.strokes, hasLength(2));
    });

    tearDown(() async {
      await sub.cancel();
      controller.dispose();
      await session.close();
      await store.close();
    });

    test('transform: CORE stores Stroke.transformed; preview resets', () async {
      final sel = controller.select({'a', 'b'});
      final before = {for (final s in sel.strokes) s.id: s.source};
      final m = SelectionGeometry.resize(
        bounds: sel.bounds,
        handle: SelectionHandle.right,
        delta: const ui.Offset(50, 0),
      );
      sel.setPreviewTransform(m);
      session.execute(sel.commitTransform()!.toCommand());
      expect(controller.pendingIds, isEmpty);
      expect(sel.previewTransform.isIdentity, isTrue);
      expect(sel.isDisposed, isFalse);
      for (final id in ['a', 'b']) {
        final now = controller.content!.strokeById(id)!.source;
        final expected = before[id]!.transformed(m);
        expect(now.style.width, SelectionGeometry.transformedWidth(2, m));
        expect(now.style.width, expected.style.width);
        expect(now.points.contentEquals(expected.points), isTrue);
        expect(now.createdAt, before[id]!.createdAt);
      }
      // undo restores the strokes
      await session.undo();
      expect(
        controller.content!
            .strokeById('a')!
            .source
            .points
            .contentEquals(before['a']!.points),
        isTrue,
      );
    });

    test('duplicate / recolor / delete through CORE', () {
      final sel = controller.select({'a', 'b'});
      session.execute(sel.duplicate().toCommand());
      final content = controller.content!;
      expect(content.strokes.map((s) => s.id), [
        'a',
        'b',
        'ink-000001',
        'ink-000002',
      ]);
      expect(controller.pendingIds, isEmpty);

      final sel2 = controller.select({'ink-000001'});
      session.execute(sel2.recolor(0x11FF0000).toCommand());
      expect(
        controller.content!.strokeById('ink-000001')!.style.colorArgb,
        0xFFFF0000,
      );
      session.execute(controller.select({'a'}).delete().toCommand());
      expect(controller.content!.strokeById('a'), isNull);
      expect(controller.selection, isNull, reason: 'its strokes are gone');
      expect(controller.pendingIds, isEmpty);
    });
  });

  group(
    'calligraphy with the CORE fake store (T28 — C2-38: preview = commit)',
    () {
      late core.NoteStore store;
      late core.NoteSession session;
      late String pageId;
      late InkPageController controller;
      late StreamSubscription<core.PageContentChange> sub;

      setUp(() async {
        store = core_testing.createFakeNoteStore();
        final note = await store.library.createNote(title: 'T28 calligraphy');
        session = await store.openSession(note.id);
        pageId = session.pages.single.id;
        final loaded = await session.openPage(pageId);
        controller = createTestPageController(
          pageId: pageId,
          services: testInkCoreServices(idPrefix: 'ink', startMillis: 100000),
        )..updateContent(_inkContentOf(loaded));
        sub = session
            .pageChanges(pageId)
            .listen(
              (ch) => controller.updateContent(_inkContentOf(ch.content)),
            );
      });

      tearDown(() async {
        await sub.cancel();
        controller.dispose();
        await session.close();
        await store.close();
      });

      core.Stroke nibStroke(String id, List<ui.Offset> xy, {double? angle}) {
        var style = core.StrokeStyle.defaultsFor(core.PenTool.calligraphy)
            .copyWith(width: 10, colorArgb: 0xFF101010);
        if (angle != null) style = style.withInkExtras(nibAngleDeg: angle);
        return interop.newCoreStroke(
          buildStroke(
            [
              for (var i = 0; i < xy.length; i++)
                InkSample(
                  position: xy[i],
                  timeUs: i * 8333,
                  kind: InkPointerKind.stylus,
                  pressure: 0.3 + 0.5 * math.sin(i / (xy.length - 1) * math.pi),
                ),
            ],
            style: style,
            viewScale: 1,
          )!,
          id: id,
          pageId: pageId,
          penDownMillis: 1000 + id.codeUnitAt(0),
        );
      }

      final center = const ui.Offset(160, 170);
      for (final (name, m, turn) in [
        (
          'rotate 30°',
          core.Affine2.rotation(
            30 * math.pi / 180,
            originX: center.dx,
            originY: center.dy,
          ),
          30.0,
        ),
        ('scale 2', core.Affine2.scaling(2, 2, originX: 60, originY: 60), 0.0),
      ]) {
        test(
          '$name: the matrix preview pixels = the committed pixels',
          () async {
            session.execute(
              core.AddStrokes(
                pageId: pageId,
                strokes: [
                  nibStroke('a', [
                    for (var i = 0; i <= 80; i++)
                      ui.Offset(
                        70 + 2.5 * i,
                        120 + 30 * math.sin(i / 80 * 2 * math.pi),
                      ),
                  ]),
                  nibStroke('b', [
                    for (var i = 0; i <= 40; i++)
                      ui.Offset(80 + 4.0 * i, 200 + 1.5 * i),
                  ], angle: 0),
                  nibStroke('c', [
                    for (var i = 0; i <= 60; i++)
                      ui.Offset(
                        150 + 40 * math.cos(i / 9),
                        170 + 40 * math.sin(i / 9),
                      ),
                  ], angle: 120),
                ],
              ),
            );
            final before = {
              for (final s in controller.content!.strokes) s.id: s.source,
            };
            final sel = controller.select({'a', 'b', 'c'});
            sel.setPreviewTransform(m);
            final preview = await _pagePixels(controller);
            session.execute(sel.commitTransform()!.toCommand());
            expect(controller.pendingIds, isEmpty);
            final committed = await _pagePixels(controller);
            for (final id in ['a', 'b', 'c']) {
              final now = controller.content!.strokeById(id)!;
              expect(now.profile, same(PenProfile.calligraphy));
              final was = before[id]!.style.nibAngleDeg;
              expect(
                now.style.nibAngleDeg,
                closeTo((was + turn) % 180, 1e-6),
                reason: '$id: CORE turns the nib (C2-38)',
              );
              if (turn == 0) {
                expect(now.style.width, before[id]!.style.width * 2);
              }
            }
            final (inked, differ) = _compare(preview, committed);
            expect(inked, greaterThan(2000), reason: 'the strokes are drawn');
            expect(
              differ / inked,
              lessThan(0.01),
              reason: '$differ of $inked differ',
            );
            // without C2-38 (the nib not turned) the rotated page would differ
            if (turn != 0) {
              final unturned = await renderPixels(600, 700, (canvas) {
                paintPaper(canvas, 0xFFFFFFFF);
                for (final s in controller.content!.strokes) {
                  final keep = s.source.copyWith(style: before[s.id]!.style);
                  final ink = InkStroke.of(keep);
                  canvas.drawPath(
                    OutlineGenerator.outline(ink).toPath(),
                    ui.Paint()..color = const ui.Color(0xFF101010),
                  );
                }
              });
              final (inked2, differ2) = _compare(unturned, committed);
              expect(differ2 / inked2, greaterThan(0.03));
            }
          },
        );
      }
    },
  );

  group('objects (v2, T37a)', () {
    late InkPageController c;
    final shape = core.ShapeObject(
      id: 'sh',
      pageId: 'p1',
      shapeKind: core.ShapeKind.rectangle,
      geometry: core.ShapeGeometry.rectangle(
        const core.PageRect(40, 200, 140, 260),
      ),
      style: const core.ShapeStyle(
        strokeColorArgb: 0xFF112233,
        strokeWidth: 3,
        fillColorArgb: 0xFF00AA00,
      ),
      createdAt: 15,
    );
    final text = core.TextBoxObject(
      id: 'tx',
      pageId: 'p1',
      frame: const core.ElementFrame(
        core.PageRect(200, 200, 300, 240),
        rotation: 0.5,
      ),
      text: 'hi',
      style: const core.TextBoxStyle(fontSizePt: 16),
      createdAt: 25,
    );
    final math = core_testing.PageObjectFixtures.math(
      pageId: 'p1',
      id: 'mx',
      rect: const core.PageRect(320, 200, 400, 240),
      createdAt: 35,
    );
    final image = core_testing.PageObjectFixtures.image(
      pageId: 'p1',
      assetId: 'asset-1',
      id: 'im',
      rect: const core.PageRect(40, 400, 140, 475),
      createdAt: 5,
    );
    final unknown = core_testing.PageObjectFixtures.unknown(
      pageId: 'p1',
      id: 'un',
      rect: const core.PageRect(200, 400, 250, 450),
    );

    setUp(() {
      c =
          createTestPageController(
            services: testInkCoreServices(idPrefix: 'n', startMillis: 9000),
          )..updateContent(
            SyntheticInk.pageContentWith(
              strokes: [
                _line('low', 140, createdAt: 10),
                _line('mid', 120, createdAt: 20),
              ],
              objects: [shape, text, math, image, unknown],
            ),
          );
    });
    tearDown(() => c.dispose());

    test('bounds = strokes ∪ objects (a rotated object by its AABB)', () {
      final sel = c.select({'mid', 'tx', 'im'});
      final strokes = SelectionGeometry.boundsOf(sel.strokes);
      final expected = strokes
          .expandToInclude(interop.rectOf(text.bounds))
          .expandToInclude(interop.rectOf(image.bounds));
      expect(sel.bounds, expected);
      // the turned text box's AABB is wider than its frame rect
      expect(text.bounds.right, greaterThan(text.frame.rect.right));
      expect(c.select({'tx'}).bounds, interop.rectOf(text.bounds));
      expect(c.select({'sh'}).bounds, interop.rectOf(shape.bounds));
    });

    test('an UnknownObject stays in place: preview, commit, duplicate', () {
      final sel = c.select({'un', 'tx'});
      expect(sel.allIds.toList(), ['un', 'tx'], reason: 'z: createdAt 1, 25');
      final m = core.Affine2.translation(30, 40);
      sel.setPreviewTransform(m);
      final live = liveObjectsOf(c);
      expect(live.map((o) => o.id), ['tx'], reason: 'the unknown is not moved');
      final edit = sel.commitTransform()!;
      expect(edit.targetIds, {'tx'});
      expect((edit.toCommand() as core.TransformElements).elementIds, ['tx']);
      c.discardEdit(edit);
      // only unknown objects → nothing to transform
      final only = c.select({'un'})..setPreviewTransform(m);
      expect(only.commitTransform(), isNull);
      expect(liveObjectsOf(c), isEmpty);
      // a duplicate of an unknown object is a copy in place with a new id
      final dup = c.select({'un'}).duplicate();
      final copy = dup.addedObjects.single;
      expect(copy, isA<core.UnknownObject>());
      expect(copy.id, isNot('un'));
      expect(copy.frame.rect, unknown.frame.rect);
    });

    test(
      'duplicate: strokes and objects ranked together, moved, sizes kept',
      () {
        final sel = c.select({'tx', 'low', 'sh', 'mid', 'mx', 'im'});
        // z order: im 5, low 10, sh 15, mid 20, tx 25, mx 35
        expect(sel.allIds.toList(), ['im', 'low', 'sh', 'mid', 'tx', 'mx']);
        final edit = sel.duplicate();
        final base = edit.added.first.createdAt - 1; // 'low' is rank 1
        expect(base, greaterThanOrEqualTo(9000));
        final created = <String, int>{
          for (final s in edit.added) s.id: s.createdAt,
          for (final o in edit.addedObjects) o.id: o.createdAt,
        };
        expect(edit.addedObjects.map((o) => o.createdAt), [
          base,
          base + 2,
          base + 4,
          base + 5,
        ]);
        expect(edit.added.map((s) => s.createdAt), [base + 1, base + 3]);
        expect(created.values.toSet(), hasLength(6), reason: 'one rank each');
        expect(created.keys.toSet().intersection(sel.allIds), isEmpty);
        const d = InkTuning.duplicateOffsetPt;
        final byOriginal = {
          for (final (k, o) in edit.addedObjects.indexed)
            ['im', 'sh', 'tx', 'mx'][k]: o,
        };
        for (final (id, original) in [
          ('im', image as core.PageObject),
          ('sh', shape),
          ('tx', text),
          ('mx', math),
        ]) {
          final copy = byOriginal[id]!;
          expect(copy.pageId, 'p1');
          expect(
            copy.frame.rect.left,
            closeTo(original.frame.rect.left + d, 1e-9),
          );
          expect(
            copy.frame.rect.top,
            closeTo(original.frame.rect.top + d, 1e-9),
          );
          expect(copy.frame.rotation, original.frame.rotation);
        }
        expect((byOriginal['sh']! as core.ShapeObject).style, shape.style);
        expect((byOriginal['tx']! as core.TextBoxObject).style, text.style);
        expect((byOriginal['mx']! as core.MathObject).style, math.style);
        final cmd = edit.toCommand() as core.CompositeCommand;
        expect(cmd.commands.map((x) => x.runtimeType), [
          core.AddStrokes,
          core.AddObjects,
        ]);
        expect(c.pendingIds, containsAll(created.keys));
      },
    );

    test('recolor: shape outline, text, math; images and unknown left out', () {
      final sel = c.select({'mid', 'sh', 'tx', 'mx', 'im', 'un'});
      final edit = sel.recolor(0x33ABCDEF);
      expect(edit.colorArgb, 0xFFABCDEF);
      expect(edit.targetIds, {'mid', 'sh', 'tx', 'mx'});
      final updated = {for (final o in edit.updatedObjects) o.id: o};
      expect(updated.keys, unorderedEquals(['sh', 'tx', 'mx']));
      final sh = updated['sh']! as core.ShapeObject;
      expect(sh.style.strokeColorArgb, 0xFFABCDEF);
      expect(sh.style.fillColorArgb, 0xFF00AA00, reason: 'the fill is kept');
      expect(sh.style.strokeWidth, 3);
      expect(sh.geometry, same(shape.geometry));
      expect(
        (updated['tx']! as core.TextBoxObject).style.colorArgb,
        0xFFABCDEF,
      );
      expect((updated['mx']! as core.MathObject).style.colorArgb, 0xFFABCDEF);
      final cmd = edit.toCommand() as core.CompositeCommand;
      final restyle = cmd.commands[0] as core.RestyleStrokes;
      expect(restyle.strokeIds, ['mid']);
      final update = cmd.commands[1] as core.UpdateObjects;
      expect(
        update.objects.map((o) => o.id),
        unorderedEquals(['sh', 'tx', 'mx']),
      );
      // objects only → one UpdateObjects
      expect(
        c.select({'sh'}).recolor(0xFF000000).toCommand(),
        isA<core.UpdateObjects>(),
      );
      // images and unknown objects only → an empty edit: not pending, StateError
      c.discardPending('sh');
      final before = c.pendingIds;
      final none = c.select({'im', 'un'}).recolor(0xFF000000);
      expect(none.isEmpty, isTrue);
      expect(none.targetIds, isEmpty);
      expect(none.updatedObjects, isEmpty);
      expect(none.toCommand, throwsStateError);
      expect(c.pendingIds, before);
    });

    test('the preview hides the originals once (60 moves, one record)', () {
      final annotation = inkAnnotationCacheOf(c);
      void paint() {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final render = inkPageRenderOf(c);
        for (final layer in InkRenderLayer.values) {
          render.paint(canvas, layer, 1);
        }
        recorder.endRecording().dispose();
      }

      paint();
      final start = annotation.recordCount;
      final sel = c.select({'tx'});
      paint();
      expect(annotation.recordCount, start, reason: 'selecting draws nothing');
      sel.setPreviewTransform(core.Affine2.translation(1, 1));
      paint();
      final once = annotation.recordCount;
      expect(once, greaterThan(start), reason: 'the original leaves its chunk');
      for (var k = 2; k <= 60; k++) {
        sel.setPreviewTransform(core.Affine2.translation(k * 1.0, k * 0.5));
        paint();
        expect(liveObjectsOf(c).single.frame.rect.left, 200 + k * 1.0);
      }
      expect(annotation.recordCount, once);
    });
  });

  group('objects with the CORE fake store (v2.1 M-2: preview = commit)', () {
    late core.NoteStore store;
    late core.NoteSession session;
    late String pageId;
    late InkPageController controller;
    late StreamSubscription<core.PageContentChange> sub;

    InkPageContent inkOf(core.PageContent c) => InkPageContent.fromCore(
      page: c.page,
      strokes: c.strokes,
      objects: c.objects,
      revision: c.revision,
    );

    setUpAll(() async {
      await loadKatexFontsForTest();
      await InkFonts.ensureLoaded();
    });

    setUp(() async {
      store = core_testing.createFakeNoteStore();
      final note = await store.library.createNote(title: 'T37a objects');
      session = await store.openSession(note.id);
      pageId = session.pages.single.id;
      final loaded = await session.openPage(pageId);
      controller = createTestPageController(
        pageId: pageId,
        services: testInkCoreServices(idPrefix: 'ink', startMillis: 100000),
      )..updateContent(inkOf(loaded));
      sub = session
          .pageChanges(pageId)
          .listen((ch) => controller.updateContent(inkOf(ch.content)));
    });

    tearDown(() async {
      await sub.cancel();
      controller.dispose();
      await session.close();
      await store.close();
    });

    List<core.PageObject> objects() => [
      core.ShapeObject(
        id: 'sh',
        pageId: pageId,
        shapeKind: core.ShapeKind.star,
        geometry: core.ShapeGeometry.star(
          const core.PageRect(30, 30, 110, 100),
        ),
        style: const core.ShapeStyle(
          strokeColorArgb: 0xFFAA0000,
          strokeWidth: 2.5,
          fillColorArgb: 0xFFFFCC00,
          dash: core.LineDash.dashed,
        ),
        createdAt: 1,
      ),
      core.TextBoxObject(
        id: 'tx',
        pageId: pageId,
        frame: const core.ElementFrame(core.PageRect(130, 30, 230, 70)),
        text: 'Hello 안녕',
        style: const core.TextBoxStyle(fontSizePt: 14, colorArgb: 0xFF2040A0),
        createdAt: 2,
      ),
      core.TextBoxObject(
        id: 'big',
        pageId: pageId,
        frame: const core.ElementFrame(core.PageRect(30, 300, 130, 330)),
        text: 'B',
        style: const core.TextBoxStyle(fontSizePt: 100),
        createdAt: 3,
      ),
      core_testing.PageObjectFixtures.math(
        pageId: pageId,
        id: 'mx',
        latex: r'\frac{a}{b}+\sqrt{x}',
        rect: const core.PageRect(30, 120, 110, 160),
        createdAt: 4,
      ),
      core_testing.PageObjectFixtures.image(
        pageId: pageId,
        assetId: 'asset-none',
        id: 'im',
        rect: const core.PageRect(130, 120, 210, 180),
        createdAt: 5,
      ),
    ];

    test('scale 2: width, font sizes (clamped) and frames = the commit', () {
      session.execute(core.AddObjects(pageId: pageId, objects: objects()));
      final before = {for (final o in controller.content!.objects) o.id: o};
      final sel = controller.select({'sh', 'tx', 'big', 'mx', 'im'});
      final m = core.Affine2.scaling(2, 2, originX: 30, originY: 30);
      sel.setPreviewTransform(m);
      final preview = {for (final o in liveObjectsOf(controller)) o.id: o};
      expect(preview.keys, unorderedEquals(['sh', 'tx', 'big', 'mx', 'im']));
      session.execute(sel.commitTransform()!.toCommand());
      expect(controller.pendingIds, isEmpty);
      final committed = {for (final o in controller.content!.objects) o.id: o};
      // the drawn value is the stored one (the resolver only stamps updatedAt / version)
      Map<String, Object?> drawn(core.PageObject o) =>
          Map.of(o.toJson())
            ..removeWhere((k, _) => k == 'updatedAt' || k == 'version');
      for (final id in preview.keys) {
        expect(
          drawn(preview[id]!),
          drawn(committed[id]!),
          reason: '$id preview = commit',
        );
      }
      final sh = committed['sh']! as core.ShapeObject;
      expect(sh.style.strokeWidth, 5, reason: '2.5 × 2');
      expect((preview['sh']! as core.ShapeObject).style.strokeWidth, 5);
      expect((committed['tx']! as core.TextBoxObject).style.fontSizePt, 28);
      expect((preview['tx']! as core.TextBoxObject).style.fontSizePt, 28);
      expect(
        (committed['big']! as core.TextBoxObject).style.fontSizePt,
        core.TextBoxStyle.maxFontSize,
        reason: '100 × 2 clamped to 144',
      );
      expect((preview['big']! as core.TextBoxObject).style.fontSizePt, 144);
      final mathBefore = before['mx']! as core.MathObject;
      expect(
        (committed['mx']! as core.MathObject).style.fontSizePt,
        mathBefore.style.fontSizePt * 2,
      );
      expect(
        (preview['mx']! as core.MathObject).style.fontSizePt,
        mathBefore.style.fontSizePt * 2,
      );
      // an image changes its frame only
      final im = committed['im']! as core.ImageObject;
      final imBefore = before['im']! as core.ImageObject;
      expect(im.frame.rect, const core.PageRect(230, 210, 390, 330));
      expect(im.assetId, imBefore.assetId);
      expect(
        (im.pixelWidth, im.pixelHeight),
        (imBefore.pixelWidth, imBefore.pixelHeight),
      );
      expect(drawn(preview['im']!), drawn(im));
    });

    test('the scale 2 preview pixels = the committed pixels (< 1 %)', () async {
      session.execute(core.AddObjects(pageId: pageId, objects: objects()));
      final sel = controller.select({'sh', 'tx', 'mx', 'im'});
      await _settle(controller);
      sel.setPreviewTransform(
        core.Affine2.scaling(2, 2, originX: 30, originY: 30),
      );
      await _settle(controller);
      final preview = await _pagePixels(controller);
      session.execute(sel.commitTransform()!.toCommand());
      expect(controller.pendingIds, isEmpty);
      await _settle(controller);
      final committed = await _pagePixels(controller);
      final (inked, differ) = _compare(preview, committed);
      expect(inked, greaterThan(5000), reason: 'the objects are drawn');
      expect(
        differ / inked,
        lessThan(0.01),
        reason: '$differ of $inked differ',
      );
      // the moved objects are really there (the stars' fill, the text color)
      expect(
        samePixel(committed.at(140, 120), const [255, 204, 0, 255], tol: 40),
        isTrue,
        reason: 'the star fill at its scaled place',
      );
    });
  });
}

void _paintAll(InkPageController c) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

/// Paints and lets the queued formula rasters arrive until nothing is queued and no
/// annotation chunk waits to be recorded (real async — a plain test).
Future<void> _settle(InkPageController c) async {
  final cache = mathRasterCacheOf(c.cachePool);
  final annotation = inkAnnotationCacheOf(c);
  for (var i = 0; i < 100; i++) {
    _paintAll(c);
    for (var k = 0; k < 2000 && cache.stats.queued > 0; k++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await pumpEventQueue();
    _paintAll(c);
    if (annotation.dirtyCount == 0 && cache.stats.queued == 0) return;
  }
  fail('the formula rasters did not settle');
}

/// Every layer over white paper at 1 px per pt, the top left 600 × 700 pt.
Future<Pixels> _pagePixels(InkPageController c) =>
    renderPixels(600, 700, (canvas) {
      paintPaper(canvas, 0xFFFFFFFF);
      final render = inkPageRenderOf(c);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

/// (pixels inked in either, pixels that differ by more than 24 on a channel).
(int, int) _compare(Pixels a, Pixels b) {
  var inked = 0, differ = 0;
  const white = [255, 255, 255, 255];
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final pa = a.at(x, y), pb = b.at(x, y);
      if (samePixel(pa, white, tol: 2) && samePixel(pb, white, tol: 2)) {
        continue;
      }
      inked++;
      if (!samePixel(pa, pb, tol: 24)) differ++;
    }
  }
  return (inked, differ);
}
