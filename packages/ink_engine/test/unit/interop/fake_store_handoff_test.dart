// T09 (03-ink 8, contract 7.2.15 '커밋 인계' / '커밋 실패' v1.1, CORE N-1/N-2/N-4):
// with the CORE fake store (createFakeNoteStore), execute(edit.toCommand())
// runs the pageChanges listener's updateContent before it returns, so the
// pending display is gone in the same call — for all 7 edit kinds. A failed
// commit (trashed note → ReadOnlyNoteException) is undone by ONE
// discardEdit(edit): erased / split originals reappear, transform and recolor
// previews end, a new stroke disappears.
// (m5-7/03-ink 8.2 T37b, 6.16 — v2) Objects the same way: transform, recolor,
// delete, duplicate, stroke eraser and partial eraser edits with shapes / text
// boxes → toCommand → execute → the pending display is gone before execute
// returns; the pending transform display is drawn as PageObject.transformed(m,
// scaleWidth: true) — its pixels are the committed page's (shape width × 2
// included: no jump); discardEdit restores objects at once (moved, recolored,
// erased); a partial-eraser gesture over a stroke and a shape is one undo
// step that brings the original stroke and the shape back together.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf, liveObjectsOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../../support/pixels.dart';

const _blue = 0xFF0000FF;
const _red = 0xFFFF0000;
const _white = [255, 255, 255, 255];
const _bluePx = [0, 0, 255, 255];
const _redPx = [255, 0, 0, 255];

final _style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
    .copyWith(colorArgb: _blue, width: 4);

InkPageContent _inkContentOf(core.PageContent c) => InkPageContent.fromCore(
  page: c.page,
  strokes: c.strokes,
  objects: c.objects,
  revision: c.revision,
);

/// A horizontal blue stroke from x 20 to 120 at [y].
core.Stroke _line(String id, String pageId, double y, int createdAt) {
  final pts = segment(ui.Offset(20, y), ui.Offset(120, y));
  final data = Float32List(pts.length * core.StrokePoints.stride);
  for (var i = 0; i < pts.length; i++) {
    data[i * core.StrokePoints.stride] = pts[i].dx;
    data[i * core.StrokePoints.stride + 1] = pts[i].dy;
    data[i * core.StrokePoints.stride + 2] = core.kNominalWidthQ;
    data[i * core.StrokePoints.stride + 5] = i * 10.0;
  }
  return interop.strokeFromData(
    data,
    id: id,
    pageId: pageId,
    style: _style,
    createdAt: createdAt,
  );
}

/// What the listener saw for one pageChanges event.
typedef _Seen = ({bool insideExecute, Set<String> pendingAfterUpdate});

void main() {
  // the text box glyphs need the binding (InkFonts reads rootBundle)
  TestWidgetsFlutterBinding.ensureInitialized();
  late core.NoteStore store;
  late core.Note note;
  late core.NoteSession session;
  late String pageId;
  late InkPageController controller;
  late StreamSubscription<core.PageContentChange> sub;
  final seen = <_Seen>[];
  final listenerErrors = <Object>[];
  var insideExecute = false;

  setUp(() async {
    seen.clear();
    listenerErrors.clear();
    store = core_testing.createFakeNoteStore();
    note = await store.library.createNote(title: 'T09 hand-off');
    session = await store.openSession(note.id);
    pageId = session.pages.single.id;
    final loaded = await session.openPage(pageId);
    controller = createTestPageController(
      pageId: pageId,
      services: testInkCoreServices(idPrefix: 'ink'),
    )..updateContent(_inkContentOf(loaded));
    // EDITOR's wiring (contract 7.2.15 '커밋 인계'): the listener only feeds
    // INK; it never calls CORE back (N-2 would throw StateError).
    sub = session.pageChanges(pageId).listen((c) {
      try {
        controller.updateContent(_inkContentOf(c.content));
        seen.add((
          insideExecute: insideExecute,
          pendingAfterUpdate: controller.pendingIds,
        ));
      } on Object catch (e) {
        listenerErrors.add(e);
      }
    });
    // three committed strokes: y = 100 (a), 200 (b), 300 (c)
    session.execute(
      core.AddStrokes(
        pageId: pageId,
        strokes: [
          _line('a', pageId, 100, 1),
          _line('b', pageId, 200, 2),
          _line('c', pageId, 300, 3),
        ],
      ),
    );
    expect(controller.content!.strokes.map((s) => s.id), ['a', 'b', 'c']);
    seen.clear();
  });

  tearDown(() async {
    await sub.cancel();
    controller.dispose();
    await session.close();
    await store.close();
  });

  /// Executes [edit] like EDITOR and checks the hand-off happened inside.
  void commit(InkEdit edit) {
    expect(controller.pendingIds, isNotEmpty, reason: 'pending before');
    insideExecute = true;
    try {
      session.execute(edit.toCommand());
    } finally {
      insideExecute = false;
    }
    expect(listenerErrors, isEmpty, reason: 'no N-2 StateError in listener');
    expect(seen, isNotEmpty, reason: 'pageChanges fired');
    expect(seen.last.insideExecute, isTrue, reason: 'N-1: same call');
    expect(
      seen.last.pendingAfterUpdate,
      isEmpty,
      reason: 'pending cleared before execute returned',
    );
    expect(controller.pendingIds, isEmpty);
    expect(controller.renderStats.pendingCommits, 0);
  }

  List<String> ids() => [for (final s in controller.content!.strokes) s.id];

  InkEdit erase(EraserMode mode, double y) {
    final samples = SyntheticInk.line(
      ui.Offset(60, y - 10),
      ui.Offset(60, y + 10),
      samples: 6,
    );
    final s = controller.beginErase(
      samples.first,
      spec: EraserSpec(mode: mode, radius: 2),
      viewScale: 1,
    );
    for (final x in samples.skip(1)) {
      s.addSample(x);
    }
    return s.end()!;
  }

  InkEdit draw(double y) {
    final samples = SyntheticInk.line(
      ui.Offset(20, y),
      ui.Offset(140, y),
      samples: 24,
    );
    final s = controller.beginStroke(samples.first, style: _style, viewScale: 1)
      ..addSamples(samples.skip(1));
    return s.end(samples.last)!;
  }

  group(
    'execute → updateContent → pendingIds empty before it returns (N-1)',
    () {
      test('addStroke', () {
        final edit = draw(360);
        expect(edit.kind, InkEditKind.addStroke);
        final id = edit.added.single.id;
        expect(controller.pendingIds, {id});
        commit(edit);
        expect(ids(), contains(id));
        expect(controller.content!.strokeById(id)!.source.version, isNotNull);
      });

      test('eraseStrokes', () {
        final edit = erase(EraserMode.stroke, 100);
        expect(edit.kind, InkEditKind.eraseStrokes);
        expect(controller.pendingIds, {'a'});
        commit(edit);
        expect(ids(), ['b', 'c']);
      });

      test('splitStrokes', () {
        // T16: a vertical pass through the middle of 'b' → two pieces
        final edit = erase(EraserMode.partial, 200);
        expect(edit.kind, InkEditKind.splitStrokes);
        expect(edit.added, hasLength(2));
        final pieceIds = {for (final s in edit.added) s.id};
        expect(controller.pendingIds, {'b', ...pieceIds});
        commit(edit);
        expect(ids(), isNot(contains('b')));
        expect(ids(), containsAll(pieceIds));
      });

      test('transformStrokes', () {
        final sel = controller.select({'b'});
        final m = core.Affine2.translation(0, 30);
        sel.setPreviewTransform(m);
        final edit = sel.commitTransform()!;
        expect(edit.kind, InkEditKind.transformStrokes);
        expect(controller.pendingIds, {'b'});
        commit(edit);
        expect(sel.previewTransform, core.Affine2.identity);
        final b = controller.content!.strokeById('b')!;
        expect(b.bounds.center.dy, closeTo(230, 0.05));
        expect(b.source.points.y(0), closeTo(230, 0.01));
      });

      test('recolorStrokes', () {
        final edit = controller.select({'a', 'c'}).recolor(_red);
        expect(edit.kind, InkEditKind.recolorStrokes);
        expect(controller.pendingIds, {'a', 'c'});
        commit(edit);
        expect(controller.content!.strokeById('a')!.style.colorArgb, _red);
        expect(controller.content!.strokeById('c')!.style.colorArgb, _red);
        expect(controller.content!.strokeById('b')!.style.colorArgb, _blue);
      });

      test('deleteStrokes', () {
        final edit = controller.select({'c', 'a'}).delete();
        expect(edit.kind, InkEditKind.deleteStrokes);
        commit(edit);
        expect(ids(), ['b']);
      });

      test('duplicateStrokes', () {
        final edit = controller.select({'a', 'b'}).duplicate();
        expect(edit.kind, InkEditKind.duplicateStrokes);
        expect(controller.pendingIds, edit.added.map((s) => s.id).toSet());
        commit(edit);
        expect(ids(), ['a', 'b', 'c', ...edit.added.map((s) => s.id)]);
        final copy = controller.content!.strokeById(edit.added.first.id)!;
        expect(copy.bounds.center.dy, closeTo(116, 0.05));
      });

      test('CORE takes SplitStrokes with pieces made by fragmentOf', () {
        final a = controller.content!.strokeById('a')!.source;
        final raw = a.points.rawData;
        const stride = core.StrokePoints.stride;
        final left = interop.fragmentOf(
          a,
          Float32List.fromList(raw.sublist(0, 10 * stride)),
          id: 'a-left',
        );
        final right = interop.fragmentOf(
          a,
          Float32List.fromList(raw.sublist(30 * stride)),
          id: 'a-right',
        );
        session.execute(
          InkEdit(
            pageId: pageId,
            kind: InkEditKind.splitStrokes,
            removedIds: {'a'},
            added: [left, right],
          ).toCommand(),
        );
        expect(listenerErrors, isEmpty);
        expect(ids(), ['a-left', 'a-right', 'b', 'c']);
        final stored = controller.content!.strokeById('a-right')!.source;
        expect(stored.createdAt, a.createdAt);
        expect(stored.points.t(0), a.points.t(30));
      });
    },
  );

  group('failed commit: ONE discardEdit(edit) undoes the display (v1.1)', () {
    Future<Pixels> paint() => renderPixels(160, 400, (canvas) {
      paintPaper(canvas, core.PaperColors.white);
      final render = inkPageRenderOf(controller);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

    Future<void> trashNote() async {
      await store.library.trashItems([core.NoteRef(note.id)]);
      await store.flush();
      expect(session.isReadOnly, isTrue, reason: 'N-4');
    }

    /// execute throws ReadOnlyNoteException; nothing reaches the listener.
    void failCommit(InkEdit edit) {
      seen.clear();
      expect(
        () => session.execute(edit.toCommand()),
        throwsA(isA<core.ReadOnlyNoteException>()),
      );
      expect(seen, isEmpty);
      expect(controller.pendingIds, isNotEmpty, reason: 'still pending');
      controller.discardEdit(edit);
      expect(controller.pendingIds, isEmpty);
      expect(controller.renderStats.pendingCommits, 0);
    }

    test('eraseStrokes: the erased stroke reappears', () async {
      await trashNote();
      expect((await paint()).at(60, 100), _bluePx);
      final edit = erase(EraserMode.stroke, 100);
      expect((await paint()).at(60, 100), _white, reason: 'hidden (pending)');
      failCommit(edit);
      expect((await paint()).at(60, 100), _bluePx);
      expect(ids(), ['a', 'b', 'c']);
    });

    test('splitStrokes: the split original reappears', () async {
      await trashNote();
      final edit = erase(EraserMode.partial, 200);
      expect(edit.kind, InkEditKind.splitStrokes);
      expect((await paint()).at(60, 200), _white);
      failCommit(edit);
      expect((await paint()).at(60, 200), _bluePx);
    });

    test('transformStrokes: the preview ends at the original place', () async {
      await trashNote();
      final sel = controller.select({'b'});
      sel.setPreviewTransform(core.Affine2.translation(0, 30));
      final edit = sel.commitTransform()!;
      var px = await paint();
      expect(px.at(60, 200), _white);
      expect(px.at(60, 230), _bluePx);
      failCommit(edit);
      expect(sel.previewTransform, core.Affine2.identity);
      px = await paint();
      expect(px.at(60, 200), _bluePx);
      expect(px.at(60, 230), _white);
    });

    test('recolorStrokes: the preview color ends', () async {
      await trashNote();
      final edit = controller.select({'c'}).recolor(_red);
      expect((await paint()).at(60, 300), _redPx);
      failCommit(edit);
      expect((await paint()).at(60, 300), _bluePx);
    });

    test('addStroke: the new stroke disappears', () async {
      await trashNote();
      final edit = draw(360);
      expect((await paint()).at(80, 360), _bluePx, reason: 'pending stroke');
      failCommit(edit);
      expect((await paint()).at(80, 360), _white);
      expect(ids(), ['a', 'b', 'c']);
    });

    test('a second discardEdit of the same edit is a no-op', () async {
      await trashNote();
      final edit = erase(EraserMode.stroke, 300);
      failCommit(edit);
      controller.discardEdit(edit);
      expect(controller.pendingIds, isEmpty);
      expect((await paint()).at(60, 300), _bluePx);
    });
  });

  group('objects (v2, T37b)', () {
    setUpAll(InkFonts.ensureLoaded);

    // a filled rectangle (w 3), a text box and a horizontal line shape just below 'b'
    setUp(() {
      session.execute(
        core.AddObjects(
          pageId: pageId,
          objects: [
            core.ShapeObject(
              id: 'sh',
              pageId: pageId,
              shapeKind: core.ShapeKind.rectangle,
              geometry: core.ShapeGeometry.rectangle(
                const core.PageRect(150, 50, 230, 110),
              ),
              style: const core.ShapeStyle(
                strokeColorArgb: 0xFF006600,
                strokeWidth: 3,
                fillColorArgb: 0xFFFFCC00,
              ),
              createdAt: 4,
            ),
            core.TextBoxObject(
              id: 'tx',
              pageId: pageId,
              frame: const core.ElementFrame(core.PageRect(150, 140, 260, 180)),
              text: 'Ink 잉크',
              style: const core.TextBoxStyle(fontSizePt: 16, colorArgb: _red),
              createdAt: 5,
            ),
            core.ShapeObject(
              id: 'ln',
              pageId: pageId,
              shapeKind: core.ShapeKind.line,
              geometry: core.ShapeGeometry.line(
                const core.PagePoint(20, 212),
                const core.PagePoint(120, 212),
              ),
              style: const core.ShapeStyle(strokeColorArgb: 0xFF006600),
              createdAt: 6,
            ),
          ],
        ),
      );
      seen.clear();
    });

    List<String> objectIds() => [
      for (final o in controller.content!.objects) o.id,
    ];

    Future<Pixels> paint() => renderPixels(400, 420, (canvas) {
      paintPaper(canvas, core.PaperColors.white);
      final render = inkPageRenderOf(controller);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

    (int, int) compare(Pixels a, Pixels b) {
      var inked = 0, differ = 0;
      for (var y = 0; y < a.height; y++) {
        for (var x = 0; x < a.width; x++) {
          final pa = a.at(x, y), pb = b.at(x, y);
          if (samePixel(pa, _white, tol: 2) && samePixel(pb, _white, tol: 2)) {
            continue;
          }
          inked++;
          if (!samePixel(pa, pb, tol: 24)) differ++;
        }
      }
      return (inked, differ);
    }

    test('every object edit: pending empty before execute returns', () {
      // transform
      final sel = controller.select({'sh', 'tx'})
        ..setPreviewTransform(core.Affine2.translation(20, 0));
      final moved = sel.commitTransform()!;
      expect(controller.pendingIds, {'sh', 'tx'});
      commit(moved);
      expect(controller.content!.objects.first.frame.rect.left, 170);
      // recolor (shape outline + text)
      final recolor = controller.select({'sh', 'tx'}).recolor(_blue);
      commit(recolor);
      final sh = controller.content!.objects.firstWhere((o) => o.id == 'sh');
      expect((sh as core.ShapeObject).style.strokeColorArgb, _blue);
      // duplicate (strokes + objects)
      final dup = controller.select({'a', 'sh', 'tx'}).duplicate();
      commit(dup);
      expect(objectIds(), hasLength(5));
      // delete (a stroke + an object)
      final del = controller.select({'c', 'tx'}).delete();
      expect(del.toCommand(), isA<core.RemoveElements>());
      commit(del);
      expect(ids(), isNot(contains('c')));
      expect(objectIds(), isNot(contains('tx')));
      // stroke eraser over a shape and a stroke
      final s = controller.beginErase(
        SyntheticInk.line(
          const ui.Offset(60, 190),
          const ui.Offset(60, 220),
        ).first,
        spec: const EraserSpec(mode: EraserMode.stroke, radius: 2),
        viewScale: 1,
      );
      for (final x in SyntheticInk.line(
        const ui.Offset(60, 190),
        const ui.Offset(60, 220),
        samples: 6,
      ).skip(1)) {
        s.addSample(x);
      }
      final erased = s.end()!;
      expect(erased.removedIds, {'b', 'ln'});
      commit(erased);
      expect(ids(), isNot(contains('b')));
      expect(objectIds(), isNot(contains('ln')));
    });

    test(
      'the pending transform display = the committed pixels (width × 2)',
      () async {
        final before = await paint();
        final sel = controller.select({'sh', 'tx'});
        final m = core.Affine2.scaling(2, 2, originX: 150, originY: 50);
        sel.setPreviewTransform(m);
        final edit = sel.commitTransform()!;
        // pending (not executed yet): drawn as transformed(m, scaleWidth: true)
        final live = {for (final o in liveObjectsOf(controller)) o.id: o};
        expect((live['sh']! as core.ShapeObject).style.strokeWidth, 6);
        expect((live['tx']! as core.TextBoxObject).style.fontSizePt, 32);
        final pending = await paint();
        expect(compare(before, pending).$2, greaterThan(1000), reason: 'moved');
        commit(edit);
        final committed = await paint();
        final sh = controller.content!.objects.firstWhere((o) => o.id == 'sh');
        expect((sh as core.ShapeObject).style.strokeWidth, 6);
        final (inked, differ) = compare(pending, committed);
        expect(inked, greaterThan(8000));
        expect(differ / inked, lessThan(0.01), reason: '$differ of $inked');
      },
    );

    test('discardEdit restores objects at once', () async {
      final before = await paint();
      Future<void> same(String what) async {
        final (inked, differ) = compare(before, await paint());
        expect(inked, greaterThan(1000));
        expect(differ, 0, reason: what);
      }

      final sel = controller.select({'sh', 'tx'})
        ..setPreviewTransform(core.Affine2.translation(40, 200));
      final moved = sel.commitTransform()!;
      expect(compare(before, await paint()).$2, greaterThan(1000));
      controller.discardEdit(moved);
      expect(liveObjectsOf(controller), isEmpty);
      await same('transform');
      final recolor = controller.select({'sh', 'tx'}).recolor(_blue);
      expect(compare(before, await paint()).$2, greaterThan(100));
      controller.discardEdit(recolor);
      await same('recolor');
      final deleted = controller.select({'sh'}).delete();
      expect(controller.hitTestObject(const ui.Offset(190, 80)), isNull);
      controller.discardEdit(deleted);
      expect(controller.hitTestObject(const ui.Offset(190, 80))?.id, 'sh');
      await same('delete');
      expect(controller.pendingIds, isEmpty);
    });

    test(
      'partial eraser over a stroke and a shape: one undo brings both back',
      () async {
        final undoBefore = session.history.undoDepth;
        final samples = SyntheticInk.line(
          const ui.Offset(60, 190),
          const ui.Offset(60, 225),
          samples: 8,
        );
        final s = controller.beginErase(
          samples.first,
          spec: const EraserSpec(mode: EraserMode.partial, radius: 2),
          viewScale: 1,
        );
        for (final x in samples.skip(1)) {
          s.addSample(x);
        }
        final edit = s.end()!;
        expect(edit.kind, InkEditKind.splitStrokes);
        expect(edit.removedObjectIds, {'ln'});
        expect(edit.toCommand(), isA<core.CompositeCommand>());
        final pieces = {for (final p in edit.added) p.id};
        expect(pieces, hasLength(2));
        commit(edit);
        expect(ids(), isNot(contains('b')));
        expect(ids(), containsAll(pieces));
        expect(objectIds(), isNot(contains('ln')));
        expect(session.history.undoDepth, undoBefore + 1);
        await session.undo();
        expect(ids(), ['a', 'b', 'c']);
        expect(objectIds(), ['sh', 'tx', 'ln']);
      },
    );
  });
}
