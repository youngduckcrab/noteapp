// T18 (03-ink 6.22, 4.8): InkSelection edits. commitTransform →
// transformStrokes(targetIds = selection in z order, transform) →
// core.TransformElements(scaleStrokeWidth: true), identity → null;
// duplicate → new ids, createdAt = nowMillis() + z rank, moved 16 pt without
// width scaling (recording fields and t kept) → core.AddStrokes; recolor →
// alpha forced to 0xFF → core.RestyleStrokes; delete → core.RemoveStrokes;
// an empty selection throws StateError (commitTransform → null). With the
// CORE fake store the results are what CORE stores.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

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
}
