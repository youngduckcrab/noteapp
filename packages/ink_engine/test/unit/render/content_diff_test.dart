// T10 (03-ink 8, 6.12 R2–R4): the content diff by id + identity and what it
// does to the ink chunk pictures — a suffix addition is appended (no
// re-record), a middle insertion / deletion / changed object marks the chunks
// it touches dirty, the same revision is a no-op, more than 16 appended
// pictures are consolidated.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/base_cache.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf, inkHighlighterCacheOf, inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

/// A short stroke at ([x], [y]) with exactly [createdAt] (z order).
core.Stroke _s(
  String id,
  int createdAt, {
  double x = 40,
  double y = 40,
  core.PenTool tool = core.PenTool.ballpoint,
}) => strokeThrough(
  segment(ui.Offset(x, y), ui.Offset(x + 30, y + 5)),
  core.StrokeStyle.defaultsFor(tool),
  id: id,
).copyWith(createdAt: createdAt);

InkPageContent _content(List<core.Stroke> strokes, {int revision = 1}) =>
    SyntheticInk.pageContent(strokes: strokes, revision: revision);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InkContentDiff.between', () {
    final a = _s('a', 1);
    final b = _s('b', 2);
    final c = _s('c', 3);
    final base = _content([a, b], revision: 1);

    test('first content / another page size → reset', () {
      expect(InkContentDiff.between(null, base).isReset, isTrue);
      final bigger = InkPageContent.fromCore(
        page: SyntheticInk.page().copyWith(size: const core.PageSize(600, 900)),
        strokes: [a, b],
        revision: 2,
      );
      expect(InkContentDiff.between(base, bigger).isReset, isTrue);
    });

    test('same revision and objects → no-op', () {
      final again = _content([b, a], revision: 1);
      final d = InkContentDiff.between(base, again);
      expect(d.isNoop, isTrue);
      expect(d.touched, isEmpty);
    });

    test('new ids on top → appended (z order)', () {
      final d2 = _s('d', 4);
      final d = InkContentDiff.between(base, _content([a, b, c, d2]));
      expect(d.isNoop, isFalse);
      expect(d.appended.map((s) => s.id), ['c', 'd']);
      expect(d.inserted, isEmpty);
      expect(d.removed, isEmpty);
      expect(d.changed, isEmpty);
    });

    test('a new id below kept strokes → inserted; one above → appended', () {
      final low = _s('low', 0);
      final d = InkContentDiff.between(base, _content([low, a, b, c]));
      expect(d.inserted.map((s) => s.id), ['low']);
      expect(d.appended.map((s) => s.id), ['c']);
    });

    test('deleted ids → removed (old objects)', () {
      final d = InkContentDiff.between(base, _content([b]));
      expect(d.removed.single, same(InkStroke.of(a)));
      expect(d.appended, isEmpty);
    });

    test('same id, another object → changed (old, new)', () {
      final moved = a.transformed(core.Affine2.translation(10, 0));
      final d = InkContentDiff.between(base, _content([moved, b]));
      expect(d.changed.single.$1, same(InkStroke.of(a)));
      expect(d.changed.single.$2, same(InkStroke.of(moved)));
      expect(d.appended, isEmpty);
    });

    test('another revision with the same objects → nothing touched', () {
      final d = InkContentDiff.between(base, _content([a, b], revision: 7));
      expect(d.isNoop, isFalse);
      expect(d.touched, isEmpty);
      expect(d.backgroundChanged, isFalse);
    });

    test('paper change is reported (highlighter blend)', () {
      final dark = SyntheticInk.pageContent(
        strokes: [a, b],
        background: const core.BlankBackground(
          paperColorArgb: core.PaperColors.black,
        ),
      );
      expect(InkContentDiff.between(base, dark).backgroundChanged, isTrue);
    });
  });

  group('chunk pictures (R3/R4)', () {
    late InkPageController controller;
    late InkChunkCache chunks;

    /// Paints the two base layers like InkPageView (pictures recorded lazily).
    void paintBase() {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final render = inkPageRenderOf(controller);
      render.paint(canvas, InkRenderLayer.highlighterBase, 1);
      render.paint(canvas, InkRenderLayer.inkBase, 1);
      recorder.endRecording().dispose();
    }

    // A4 at 256 pt chunks = 3 × 4; a at chunk (0,0), b at (1,1)
    final a = _s('a', 1, x: 40, y: 40);
    final b = _s('b', 2, x: 300, y: 300);

    setUp(() {
      controller = createTestPageController()..updateContent(_content([a, b]));
      chunks = inkChunkCacheOf(controller);
      paintBase();
    });
    tearDown(() => controller.dispose());

    test('the grid follows chunkSizePt; every chunk recorded once', () {
      expect((chunks.columns, chunks.rows), (3, 4));
      expect(chunks.recordCount, 12);
      expect(chunks.dirtyCount, 0);
      expect(controller.renderStats.chunkPictures, 12);
      paintBase();
      expect(chunks.recordCount, 12, reason: 'cached');
    });

    test('suffix addition → appended picture, no re-record', () {
      final c = _s('c', 3, x: 60, y: 60);
      controller.updateContent(_content([a, b, c], revision: 2));
      expect(chunks.appendedCountAt(0, 0), 1);
      expect(chunks.dirtyCount, 0);
      expect(controller.renderStats.chunkPictures, 13);
      paintBase();
      expect(chunks.recordCount, 12);
    });

    test('a stroke over a chunk border is appended to both chunks', () {
      final c = _s('c', 3, x: 240, y: 40); // 240 → 270 crosses x = 256
      controller.updateContent(_content([a, b, c], revision: 2));
      expect(chunks.appendedCountAt(0, 0), 1);
      expect(chunks.appendedCountAt(1, 0), 1);
      expect(chunks.appendedCountAt(2, 0), 0);
    });

    test('middle insertion → that chunk dirty, re-recorded once', () {
      final low = _s('low', 0, x: 320, y: 320);
      controller.updateContent(_content([low, a, b], revision: 2));
      expect(chunks.isDirtyAt(1, 1), isTrue);
      expect(chunks.dirtyCount, 1);
      expect(chunks.appendedCountAt(1, 1), 0);
      paintBase();
      expect(chunks.recordCount, 13);
      expect(chunks.dirtyCount, 0);
    });

    test('deletion → the chunk of the deleted stroke dirty', () {
      controller.updateContent(_content([b], revision: 2));
      expect(chunks.isDirtyAt(0, 0), isTrue);
      expect(chunks.dirtyCount, 1);
    });

    test('changed object → dirty where it was and where it is', () {
      final moved = a.transformed(core.Affine2.translation(500, 0));
      controller.updateContent(_content([moved, b], revision: 2));
      expect(chunks.isDirtyAt(0, 0), isTrue);
      expect(chunks.isDirtyAt(2, 0), isTrue);
      expect(chunks.dirtyCount, 2);
    });

    test('same revision → no-op', () {
      controller.updateContent(_content([a, b]));
      expect(chunks.dirtyCount, 0);
      paintBase();
      expect(chunks.recordCount, 12);
    });

    test('more than 16 appended pictures → the chunk is consolidated', () {
      final strokes = [a, b];
      for (var i = 0; i < 17; i++) {
        strokes.add(_s('n$i', 10 + i, x: 20.0 + i, y: 100));
        controller.updateContent(_content(strokes, revision: 2 + i));
      }
      expect(chunks.isDirtyAt(0, 0), isTrue, reason: '17th append');
      paintBase();
      expect(chunks.appendedCountAt(0, 0), 0);
      expect(chunks.recordCount, 13);
      strokes.add(_s('last', 99, x: 30, y: 120));
      controller.updateContent(_content(strokes, revision: 99));
      expect(chunks.appendedCountAt(0, 0), 1);
    });

    test('hiding a stroke (pending erase) re-records its chunk only', () {
      final eraser = controller.beginErase(
        const InkSample(
          position: ui.Offset(55, 42),
          timeUs: 0,
          kind: InkPointerKind.stylus,
        ),
        spec: const EraserSpec(mode: EraserMode.stroke, radius: 3),
        viewScale: 1,
      );
      final edit = eraser.end()!;
      paintBase();
      expect(chunks.recordCount, 13);
      controller.discardEdit(edit);
      paintBase();
      expect(chunks.recordCount, 14, reason: 'shown again');
    });

    test(
      'pencil: chunks recorded before the grain is ready are redone',
      () async {
        final p = _s('p', 3, x: 60, y: 300, tool: core.PenTool.pencil);
        controller.updateContent(_content([a, b, p], revision: 2));
        expect(chunks.appendedCountAt(0, 1), 1);
        paintBase();
        final before = chunks.recordCount;
        expect(controller.pencilGrain.value, isNull, reason: 'not ready yet');
        await controller.pencilGrain.ready;
        await Future<void>.delayed(Duration.zero);
        expect(chunks.dirtyCount, chunks.chunkCount);
        paintBase();
        expect(chunks.recordCount, before + chunks.chunkCount);
        expect(chunks.appendedCountAt(0, 1), 0, reason: 'now in the chunk');
      },
    );

    test('highlighters are one page picture, not chunks', () {
      final hl = _s('hl', 3, x: 40, y: 200, tool: core.PenTool.highlighter);
      final hlCache = inkHighlighterCacheOf(controller);
      final before = hlCache.recordCount;
      controller.updateContent(_content([a, b, hl], revision: 2));
      expect(chunks.appendedCountAt(0, 0), 0);
      expect(chunks.dirtyCount, 0);
      paintBase();
      expect(hlCache.recordCount, before + 1);
      paintBase();
      expect(hlCache.recordCount, before + 1, reason: 'cached');
    });
  });
}
