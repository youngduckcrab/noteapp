// T09 (03-ink 8, 4.6 table = contract 7.2.15 table): InkEdit.toCommand for the
// six rows, isEmpty → StateError, recolor alpha 0xFF, removedIds / targetIds in
// z order, and the invariants of the edits the sessions return.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

/// A horizontal ballpoint stroke at [y] with exactly [createdAt].
core.Stroke _s(String id, int createdAt, {double y = 50}) {
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
    pageId: 'p1',
    style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
    createdAt: createdAt,
  );
}

void main() {
  final a = _s('a', 1, y: 40);
  final b = _s('b', 2, y: 60);
  final m = core.Affine2.translation(5, -3);

  group('toCommand: the 4.6 table', () {
    test('addStroke → AddStrokes(pageId, added)', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.addStroke,
        added: [a, b],
      ).toCommand();
      expect(
        cmd,
        isA<core.AddStrokes>().having((c) => c.pageId, 'pageId', 'p1').having(
          (c) => c.strokes,
          'strokes',
          [same(a), same(b)],
        ),
      );
    });

    test('duplicateStrokes → AddStrokes(pageId, added)', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.duplicateStrokes,
        added: [b],
      ).toCommand();
      expect(
        cmd,
        isA<core.AddStrokes>().having((c) => c.pageId, 'pageId', 'p1').having(
          (c) => c.strokes,
          'strokes',
          [same(b)],
        ),
      );
    });

    for (final kind in [InkEditKind.eraseStrokes, InkEditKind.deleteStrokes]) {
      test('${kind.name} → RemoveStrokes(pageId, removedIds)', () {
        final cmd = InkEdit(
          pageId: 'p1',
          kind: kind,
          removedIds: {'b', 'a', 'c'},
        ).toCommand();
        expect(
          cmd,
          isA<core.RemoveStrokes>()
              .having((c) => c.pageId, 'pageId', 'p1')
              .having((c) => c.strokeIds, 'strokeIds', ['b', 'a', 'c']),
        );
      });
    }

    test(
      'splitStrokes with pieces → SplitStrokes(pageId, removedIds, added)',
      () {
        final piece = a.fragment(id: 'a-1', points: a.points.sublist(0, 4));
        final cmd = InkEdit(
          pageId: 'p1',
          kind: InkEditKind.splitStrokes,
          removedIds: {'a', 'b'},
          added: [piece],
        ).toCommand();
        expect(
          cmd,
          isA<core.SplitStrokes>()
              .having((c) => c.pageId, 'pageId', 'p1')
              .having((c) => c.removedIds, 'removedIds', ['a', 'b'])
              .having((c) => c.added, 'added', [same(piece)]),
        );
      },
    );

    test('splitStrokes without pieces → RemoveStrokes', () {
      final cmd = const InkEdit(
        pageId: 'p1',
        kind: InkEditKind.splitStrokes,
        removedIds: {'b', 'a'},
      ).toCommand();
      expect(
        cmd,
        isA<core.RemoveStrokes>()
            .having((c) => c.pageId, 'pageId', 'p1')
            .having((c) => c.strokeIds, 'strokeIds', ['b', 'a']),
      );
    });

    test('transformStrokes → TransformElements(scaleStrokeWidth: true)', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.transformStrokes,
        targetIds: {'b', 'a'},
        transform: m,
      ).toCommand();
      expect(
        cmd,
        isA<core.TransformElements>()
            .having((c) => c.pageId, 'pageId', 'p1')
            .having((c) => c.elementIds, 'elementIds', ['b', 'a'])
            .having((c) => c.transform, 'transform', m)
            .having((c) => c.scaleStrokeWidth, 'scaleStrokeWidth', isTrue),
      );
    });

    test('recolorStrokes → RestyleStrokes(patch: colorArgb only)', () {
      final cmd = const InkEdit(
        pageId: 'p1',
        kind: InkEditKind.recolorStrokes,
        targetIds: {'a'},
        colorArgb: 0xFF336699,
      ).toCommand();
      expect(
        cmd,
        isA<core.RestyleStrokes>()
            .having((c) => c.pageId, 'pageId', 'p1')
            .having((c) => c.strokeIds, 'strokeIds', ['a'])
            .having(
              (c) => c.patch,
              'patch',
              const core.StrokeStylePatch(colorArgb: 0xFF336699),
            ),
      );
    });

    test('toCommand is deterministic (same lists every call)', () {
      final edit = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.transformStrokes,
        targetIds: {'z', 'b', 'a', 'q'},
        transform: m,
      );
      final one = edit.toCommand() as core.TransformElements;
      final two = edit.toCommand() as core.TransformElements;
      expect(one.elementIds, ['z', 'b', 'a', 'q']);
      expect(two.elementIds, one.elementIds);
    });
  });

  group('isEmpty → StateError', () {
    test('no fields', () {
      for (final kind in InkEditKind.values) {
        final edit = InkEdit(pageId: 'p1', kind: kind);
        expect(edit.isEmpty, isTrue, reason: kind.name);
        expect(edit.toCommand, throwsStateError, reason: kind.name);
      }
    });

    test('the fields of another kind do not count', () {
      final cases = <InkEdit>[
        InkEdit(pageId: 'p1', kind: InkEditKind.addStroke, removedIds: {'a'}),
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.duplicateStrokes,
          targetIds: {'a'},
        ),
        InkEdit(pageId: 'p1', kind: InkEditKind.eraseStrokes, added: [a]),
        InkEdit(pageId: 'p1', kind: InkEditKind.deleteStrokes, added: [a]),
        // pieces alone are not a split: removedIds is required
        InkEdit(pageId: 'p1', kind: InkEditKind.splitStrokes, added: [a]),
        // a transform needs both targets and the matrix
        const InkEdit(
          pageId: 'p1',
          kind: InkEditKind.transformStrokes,
          targetIds: {'a'},
        ),
        InkEdit(pageId: 'p1', kind: InkEditKind.transformStrokes, transform: m),
        // a recolor needs both targets and the color
        const InkEdit(
          pageId: 'p1',
          kind: InkEditKind.recolorStrokes,
          targetIds: {'a'},
        ),
        const InkEdit(
          pageId: 'p1',
          kind: InkEditKind.recolorStrokes,
          colorArgb: 0xFF000000,
        ),
      ];
      for (final edit in cases) {
        expect(edit.isEmpty, isTrue, reason: '$edit');
        expect(edit.toCommand, throwsStateError, reason: '$edit');
      }
    });

    test('filled edits are not empty', () {
      expect(
        InkEdit(pageId: 'p1', kind: InkEditKind.addStroke, added: [a]).isEmpty,
        isFalse,
      );
      expect(
        const InkEdit(
          pageId: 'p1',
          kind: InkEditKind.splitStrokes,
          removedIds: {'a'},
        ).isEmpty,
        isFalse,
      );
    });
  });

  group('edits from the sessions', () {
    // z order: c (createdAt 1) < a (2) < b (3)
    final c1 = _s('c', 1, y: 20);
    final a2 = _s('a', 2, y: 50);
    final b3 = _s('b', 3, y: 80);
    late InkPageController controller;

    setUp(() {
      controller = createTestPageController()
        ..updateContent(SyntheticInk.pageContent(strokes: [b3, a2, c1]));
    });
    tearDown(() => controller.dispose());

    test('eraser: removedIds in z order, not in touch order', () {
      // bottom → top touches b, then a, then c
      final samples = SyntheticInk.line(
        const ui.Offset(60, 95),
        const ui.Offset(60, 5),
        samples: 40,
      );
      for (final mode in EraserMode.values) {
        final session = controller.beginErase(
          samples.first,
          spec: EraserSpec(mode: mode, radius: 3),
          viewScale: 1,
        );
        for (final s in samples.skip(1)) {
          session.addSample(s);
        }
        expect(session.touchedStrokeIds, ['b', 'a', 'c']);
        final edit = session.end(samples.last)!;
        expect(edit.pageId, 'p1');
        expect(edit.removedIds.toList(), ['c', 'a', 'b'], reason: mode.name);
        // stroke mode → RemoveStrokes; partial mode (T16) → SplitStrokes
        // with the pieces of each original, originals in z order
        final ids = switch (edit.toCommand()) {
          core.RemoveStrokes(:final strokeIds) => strokeIds,
          core.SplitStrokes(:final removedIds) => removedIds,
          final other => fail('unexpected $other'),
        };
        expect(ids, ['c', 'a', 'b']);
        controller.discardEdit(edit);
      }
    });

    test('selection: delete / transform / recolor ids in z order', () {
      final sel = controller.select({'b', 'c', 'a'});
      final del = sel.delete();
      expect(del.kind, InkEditKind.deleteStrokes);
      expect(del.removedIds.toList(), ['c', 'a', 'b']);
      controller.discardEdit(del);

      sel.setPreviewTransform(m);
      final move = sel.commitTransform()!;
      expect(move.targetIds.toList(), ['c', 'a', 'b']);
      expect(move.transform, m);
      expect((move.toCommand() as core.TransformElements).elementIds, [
        'c',
        'a',
        'b',
      ]);
      controller.discardEdit(move);

      final recolor = sel.recolor(0xFF00AA00);
      expect(recolor.targetIds.toList(), ['c', 'a', 'b']);
    });

    test('recolor forces alpha 0xFF', () {
      for (final argb in [0x00123456, 0x80123456, 0xFF123456]) {
        final edit = controller.select({'a'}).recolor(argb);
        expect(edit.colorArgb, 0xFF123456);
        expect(
          (edit.toCommand() as core.RestyleStrokes).patch,
          const core.StrokeStylePatch(colorArgb: 0xFF123456),
        );
        controller.discardEdit(edit);
      }
    });

    test('added strokes: version null, pageId, normalized style', () {
      final samples = SyntheticInk.line(
        const ui.Offset(30, 200),
        const ui.Offset(200, 220),
      );
      final pen = controller.beginStroke(
        samples.first,
        style: core.StrokeStyle.defaultsFor(core.PenTool.marker)
            .copyWith(colorArgb: 0x10ABCDEF, width: 80, opacity: 9),
        viewScale: 1,
      )..addSamples(samples.skip(1));
      final add = pen.end(samples.last)!;
      final dup = controller.select({'a', 'b'}).duplicate();
      for (final edit in [add, dup]) {
        expect(edit.isEmpty, isFalse);
        for (final s in edit.added) {
          expect(s.version, isNull);
          expect(s.pageId, edit.pageId);
          expect(s.style, s.style.normalized());
          expect(core.isValidEntityId(s.id), isTrue);
        }
      }
      expect(add.added.single.style.colorArgb, 0xFFABCDEF);
      expect(add.added.single.style.width, core.StrokeStyle.maxWidth);
    });

    test('sessions return null instead of an empty edit', () {
      final eraser = controller.beginErase(
        const InkSample(
          position: ui.Offset(500, 700),
          timeUs: 0,
          kind: InkPointerKind.stylus,
        ),
        spec: const EraserSpec(mode: EraserMode.stroke, radius: 2),
        viewScale: 1,
      );
      expect(eraser.end(), isNull);
      final sel = controller.select({'a'});
      expect(sel.commitTransform(), isNull, reason: 'identity preview');
      expect(controller.pendingIds, isEmpty);
    });
  });
}
