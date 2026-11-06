// T24 (m5-7/03-ink 8.1, 4.6 table = contract 7.2.9 v2.1): InkEdit v2.1 —
// removedObjectIds, addedObjects / updatedObjects and the toCommand rows in the
// named-argument command shape; the empty side is left out and a single
// command is not wrapped; isEmpty v2; == sees the new fields.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../../support/pixels.dart';

core.Stroke _s(String id, int createdAt) {
  final pts = segment(const ui.Offset(20, 50), const ui.Offset(120, 50));
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
  final a = _s('a', 1);
  final piece = _s('a-1', 1);
  final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'sh', createdAt: 3);
  final text = PageObjectFixtures.textBox(pageId: 'p1', id: 'tx', createdAt: 4);

  group('eraseStrokes / deleteStrokes', () {
    for (final kind in [InkEditKind.eraseStrokes, InkEditKind.deleteStrokes]) {
      test('${kind.name}: strokes only → RemoveStrokes (v1.4)', () {
        final cmd = InkEdit(
          pageId: 'p1',
          kind: kind,
          removedIds: const {'a', 'b'},
        ).toCommand();
        expect(
          cmd,
          isA<core.RemoveStrokes>()
              .having((c) => c.pageId, 'pageId', 'p1')
              .having((c) => c.strokeIds, 'strokeIds', ['a', 'b']),
        );
      });

      test('${kind.name}: removedObjectIds → RemoveElements(removedIds)', () {
        final cmd = InkEdit(
          pageId: 'p1',
          kind: kind,
          removedIds: const {'a', 'sh'},
          removedObjectIds: const {'sh'},
        ).toCommand();
        expect(
          cmd,
          isA<core.RemoveElements>()
              .having((c) => c.pageId, 'pageId', 'p1')
              .having((c) => c.elementIds, 'elementIds', ['a', 'sh']),
        );
      });
    }

    test('C-3: a public-constructed eraseStrokes with a shape id removes the '
        'shape too', () async {
      final store = createFakeNoteStore();
      final note = await store.library.createNote(title: 'C-3');
      final session = await store.openSession(note.id);
      final pageId = session.pages.single.id;
      await session.openPage(pageId);
      final s = PageObjectFixtures.shape(pageId: pageId, id: 'shape-1');
      session.execute(core.AddObjects(pageId: pageId, objects: [s]));
      expect((await session.openPage(pageId)).objectById('shape-1'), isNotNull);
      final cmd = InkEdit(
        pageId: pageId,
        kind: InkEditKind.eraseStrokes,
        removedIds: const {'shape-1'},
        removedObjectIds: const {'shape-1'},
      ).toCommand();
      session.execute(cmd);
      expect((await session.openPage(pageId)).objectById('shape-1'), isNull);
      await session.close();
      await store.close();
    });
  });

  group('splitStrokes (CP-INK-2)', () {
    test('no objects → v1.4 SplitStrokes / RemoveStrokes', () {
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.splitStrokes,
          removedIds: const {'a'},
          added: [piece],
        ).toCommand(),
        isA<core.SplitStrokes>()
            .having((c) => c.removedIds, 'removedIds', ['a'])
            .having((c) => c.added, 'added', [same(piece)]),
      );
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.splitStrokes,
          removedIds: const {'a'},
        ).toCommand(),
        isA<core.RemoveStrokes>(),
      );
    });

    test('pieces + a shape → Composite[SplitStrokes, RemoveElements]', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.splitStrokes,
        removedIds: const {'a', 'sh'},
        removedObjectIds: const {'sh'},
        added: [piece],
      ).toCommand();
      expect(cmd, isA<core.CompositeCommand>());
      final parts = (cmd as core.CompositeCommand).commands;
      expect(parts, hasLength(2));
      expect(
        parts[0],
        isA<core.SplitStrokes>()
            .having((c) => c.removedIds, 'removedIds', ['a'])
            .having((c) => c.added, 'added', [same(piece)]),
      );
      expect(
        parts[1],
        isA<core.RemoveElements>().having((c) => c.elementIds, 'elementIds', [
          'sh',
        ]),
      );
    });

    test('a stroke erased whole + a shape → Composite[RemoveStrokes, '
        'RemoveElements]', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.splitStrokes,
        removedIds: const {'a', 'sh'},
        removedObjectIds: const {'sh'},
      ).toCommand();
      final parts = (cmd as core.CompositeCommand).commands;
      expect(parts[0], isA<core.RemoveStrokes>());
      expect(parts[1], isA<core.RemoveElements>());
    });

    test('only a shape → one RemoveElements (not wrapped)', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.splitStrokes,
        removedIds: const {'sh'},
        removedObjectIds: const {'sh'},
      ).toCommand();
      expect(
        cmd,
        isA<core.RemoveElements>().having((c) => c.elementIds, 'elementIds', [
          'sh',
        ]),
      );
    });
  });

  group('recolorStrokes', () {
    final recolored = shape.copyWith(
      style: shape.style.copyWith(strokeColorArgb: 0xFF00AA00),
    );

    test('strokes + objects → Composite[RestyleStrokes, UpdateObjects]', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.recolorStrokes,
        targetIds: const {'a', 'sh'},
        colorArgb: 0xFF00AA00,
        updatedObjects: [recolored],
      ).toCommand();
      final parts = (cmd as core.CompositeCommand).commands;
      expect(
        parts[0],
        isA<core.RestyleStrokes>()
            .having((c) => c.strokeIds, 'strokeIds', ['a'])
            .having((c) => c.patch.colorArgb, 'color', 0xFF00AA00),
      );
      expect(
        parts[1],
        isA<core.UpdateObjects>().having((c) => c.objects, 'objects', [
          same(recolored),
        ]),
      );
    });

    test('strokes only → RestyleStrokes; objects only → UpdateObjects', () {
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.recolorStrokes,
          targetIds: const {'a'},
          colorArgb: 0xFF00AA00,
        ).toCommand(),
        isA<core.RestyleStrokes>(),
      );
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.recolorStrokes,
          targetIds: const {'sh'},
          colorArgb: 0xFF00AA00,
          updatedObjects: [recolored],
        ).toCommand(),
        isA<core.UpdateObjects>(),
      );
    });

    test('nothing to recolor → isEmpty → StateError', () {
      const edit = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.recolorStrokes,
        colorArgb: 0xFF00AA00,
      );
      expect(edit.isEmpty, isTrue);
      expect(edit.toCommand, throwsStateError);
    });
  });

  group('duplicateStrokes / addShape', () {
    test('strokes + objects → Composite[AddStrokes, AddObjects]', () {
      final cmd = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.duplicateStrokes,
        added: [a],
        addedObjects: [text],
      ).toCommand();
      final parts = (cmd as core.CompositeCommand).commands;
      expect(
        parts[0],
        isA<core.AddStrokes>().having((c) => c.strokes, 'strokes', [same(a)]),
      );
      expect(
        parts[1],
        isA<core.AddObjects>().having((c) => c.objects, 'objects', [
          same(text),
        ]),
      );
    });

    test('objects only → one AddObjects', () {
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.duplicateStrokes,
          addedObjects: [text],
        ).toCommand(),
        isA<core.AddObjects>(),
      );
    });

    test('addShape → AddObjects(pageId, addedObjects)', () {
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.addShape,
          addedObjects: [shape],
        ).toCommand(),
        isA<core.AddObjects>().having((c) => c.pageId, 'pageId', 'p1').having(
          (c) => c.objects,
          'objects',
          [same(shape)],
        ),
      );
    });
  });

  group('rules', () {
    test('removedObjectIds ⊄ removedIds → ArgumentError', () {
      const edit = InkEdit(
        pageId: 'p1',
        kind: InkEditKind.eraseStrokes,
        removedIds: {'a'},
        removedObjectIds: {'sh'},
      );
      expect(edit.toCommand, throwsArgumentError);
    });

    test('isEmpty v2', () {
      expect(
        const InkEdit(pageId: 'p1', kind: InkEditKind.addShape).isEmpty,
        isTrue,
      );
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.addShape,
          addedObjects: [shape],
        ).isEmpty,
        isFalse,
      );
      expect(
        const InkEdit(pageId: 'p1', kind: InkEditKind.duplicateStrokes).isEmpty,
        isTrue,
      );
      expect(
        InkEdit(
          pageId: 'p1',
          kind: InkEditKind.duplicateStrokes,
          addedObjects: [shape],
        ).isEmpty,
        isFalse,
      );
      expect(
        () =>
            const InkEdit(pageId: 'p1', kind: InkEditKind.addShape).toCommand(),
        throwsStateError,
      );
    });

    test(
      '== and hashCode see removedObjectIds, addedObjects, updatedObjects',
      () {
        const base = InkEdit(
          pageId: 'p1',
          kind: InkEditKind.eraseStrokes,
          removedIds: {'a', 'sh'},
        );
        const withObjects = InkEdit(
          pageId: 'p1',
          kind: InkEditKind.eraseStrokes,
          removedIds: {'a', 'sh'},
          removedObjectIds: {'sh'},
        );
        expect(base == withObjects, isFalse);
        expect(
          withObjects,
          const InkEdit(
            pageId: 'p1',
            kind: InkEditKind.eraseStrokes,
            removedIds: {'sh', 'a'},
            removedObjectIds: {'sh'},
          ),
        );
        expect(
          withObjects.hashCode,
          const InkEdit(
            pageId: 'p1',
            kind: InkEditKind.eraseStrokes,
            removedIds: {'sh', 'a'},
            removedObjectIds: {'sh'},
          ).hashCode,
        );
        final x = InkEdit(
          pageId: 'p1',
          kind: InkEditKind.addShape,
          addedObjects: [shape],
        );
        expect(
          x,
          InkEdit(
            pageId: 'p1',
            kind: InkEditKind.addShape,
            addedObjects: [shape],
          ),
        );
        expect(
          x ==
              InkEdit(
                pageId: 'p1',
                kind: InkEditKind.addShape,
                addedObjects: [text],
              ),
          isFalse,
        );
      },
    );

    test('InkEditKind values (v2.0: + addShape)', () {
      expect(InkEditKind.values.last, InkEditKind.addShape);
      expect(InkEditKind.values, hasLength(8));
    });
  });
}
