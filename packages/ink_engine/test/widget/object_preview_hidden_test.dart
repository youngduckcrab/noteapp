// m5-7/03-ink 8.2 T38 (6.17, 4.3): hidden objects and preview objects, final.
// - setHiddenObjectIds: a hidden object is not drawn (shape, text box, image) and
//   hit tests still find it; shown again → the same pixels. Only the chunks of
//   the toggled objects are recorded again and only their layers repaint; the
//   same set again (or ids not on the page) does nothing; an object arriving
//   later with a hidden id starts hidden.
// - setPreviewObjects: a preview with a committed id replaces it, another id is
//   added in its L-1 layer, the preview of a hidden id is drawn (preview >
//   hidden). 60 updates of one preview: the base chunk is recorded once (the
//   replaced-id set changes once) and only the live part repaints (inkActive for
//   a shape, annotation for a text box). Another page's object → ArgumentError
//   and nothing changes; an empty list → the committed drawing again; the
//   getters are the given values (unmodifiable, duplicates and absent ids kept).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show
        inkAnnotationCacheOf,
        inkChunkCacheOf,
        inkPageRenderOf,
        inkUnderlayCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../support/pixels.dart';

const _pageId = 'p1';
const _red = 0xFFDD0000;
const _green = 0xFF00AA00;

final _shape = core.ShapeObject(
  id: 'sh',
  pageId: _pageId,
  shapeKind: core.ShapeKind.rectangle,
  geometry: core.ShapeGeometry.rectangle(const core.PageRect(20, 20, 100, 80)),
  style: const core.ShapeStyle(strokeColorArgb: _red, strokeWidth: 8),
  createdAt: 2,
);

core.TextBoxObject _text(core.PageRect r, {String id = 'tx'}) =>
    core.TextBoxObject(
      id: id,
      pageId: _pageId,
      frame: core.ElementFrame(r),
      text: '',
      style: const core.TextBoxStyle(backgroundArgb: _green),
      createdAt: 3,
    );

// inside chunk (0, 0) like the other two (256 pt chunks)
final _box = _text(const core.PageRect(140, 20, 240, 80));
final _image = PageObjectFixtures.image(
  pageId: _pageId,
  assetId: 'a1',
  id: 'im',
  rect: const core.PageRect(20, 140, 120, 240),
  createdAt: 1,
);

InkPageContent _content(List<core.PageObject> objects, {int revision = 1}) =>
    InkPageContent.fromCore(
      page: SyntheticInk.page(pageId: _pageId),
      strokes: const [],
      objects: objects,
      revision: revision,
    );

InkPageController _controller([List<core.PageObject>? objects]) {
  final c = createTestPageController()
    ..updateContent(_content(objects ?? [_shape, _box, _image]));
  addTearDown(c.dispose);
  return c;
}

/// Every layer of [c] over white paper at 1 px per pt (records what is dirty).
Future<Pixels> _pixels(InkPageController c) => renderPixels(300, 300, (canvas) {
  paintPaper(canvas, 0xFFFFFFFF);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
});

void _paintAll(InkPageController c) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

bool _paper(List<int> p) => samePixel(p, const [255, 255, 255, 255]);

int _diff(Pixels a, Pixels b) {
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (!samePixel(a.at(x, y), b.at(x, y))) n++;
    }
  }
  return n;
}

/// Counts the repaint notifications of every layer of [c].
Map<InkRenderLayer, int> _repaints(InkPageController c) {
  final counts = {for (final l in InkRenderLayer.values) l: 0};
  for (final layer in InkRenderLayer.values) {
    void count() => counts[layer] = counts[layer]! + 1;
    c.layerRepaint(layer).addListener(count);
    addTearDown(() => c.layerRepaint(layer).removeListener(count));
  }
  return counts;
}

/// The layers notified since [counts] was last cleared, then clears it.
Set<InkRenderLayer> _fired(Map<InkRenderLayer, int> counts) {
  final out = {
    for (final e in counts.entries)
      if (e.value > 0) e.key,
  };
  counts.updateAll((_, _) => 0);
  return out;
}

void main() {
  group('setHiddenObjectIds', () {
    test('a hidden object is not drawn and still hit; shown again → the same '
        'pixels', () async {
      final c = _controller();
      final base = await _pixels(c);
      expect(_paper(base.at(20, 50)), isFalse, reason: 'shape edge');
      expect(_paper(base.at(200, 50)), isFalse, reason: 'text background');
      expect(_paper(base.at(70, 190)), isFalse, reason: 'image placeholder');
      for (final (id, x, y) in const [
        ('sh', 20, 50),
        ('tx', 200, 50),
        ('im', 70, 190),
      ]) {
        c.setHiddenObjectIds({id});
        final px = await _pixels(c);
        expect(_paper(px.at(x, y)), isTrue, reason: '$id hidden');
        // the others are still there
        for (final (other, ox, oy) in const [
          ('sh', 20, 50),
          ('tx', 200, 50),
          ('im', 70, 190),
        ]) {
          if (other == id) continue;
          expect(_paper(px.at(ox, oy)), isFalse, reason: '$other drawn');
        }
        expect(
          c.hitTestObject(ui.Offset(x.toDouble() + 2, y.toDouble()))?.id,
          id,
          reason: 'hit tests see hidden objects (4.10)',
        );
        c.setHiddenObjectIds(const {});
        expect(_diff(await _pixels(c), base), 0, reason: '$id shown again');
      }
    });

    test('only the toggled objects\' chunks are recorded again and only their '
        'layers repaint; the same set or absent ids do nothing', () async {
      final c = _controller();
      _paintAll(c);
      final ink = inkChunkCacheOf(c);
      final underlay = inkUnderlayCacheOf(c);
      final annotation = inkAnnotationCacheOf(c);
      (int, int, int) records() =>
          (ink.recordCount, underlay.recordCount, annotation.recordCount);
      final start = records();
      final repaints = _repaints(c);

      c.setHiddenObjectIds({'tx'});
      expect(_fired(repaints), {InkRenderLayer.annotation});
      _paintAll(c);
      expect(records(), (start.$1, start.$2, start.$3 + 1));

      c.setHiddenObjectIds({'tx'}); // the same set, another instance
      expect(_fired(repaints), isEmpty);
      c.setHiddenObjectIds({
        'tx',
        'absent',
      }); // not on the page: no drawing change
      expect(_fired(repaints), isEmpty);
      expect(c.hiddenObjectIds, {'tx', 'absent'}, reason: 'kept as given');
      _paintAll(c);
      expect(records(), (start.$1, start.$2, start.$3 + 1));

      // the shape hidden, the text box shown: the ink chunk and the annotation chunk
      c.setHiddenObjectIds({'sh', 'absent'});
      expect(_fired(repaints), {
        InkRenderLayer.inkBase,
        InkRenderLayer.annotation,
      });
      _paintAll(c);
      expect(records(), (start.$1 + 1, start.$2, start.$3 + 2));
      c.setHiddenObjectIds({'im'});
      expect(_fired(repaints), {
        InkRenderLayer.inkBase,
        InkRenderLayer.underlay,
      });
      _paintAll(c);
      expect(records(), (start.$1 + 2, start.$2 + 1, start.$3 + 2));
    });

    test('an object arriving later with a hidden id starts hidden', () async {
      final c = _controller([_shape]);
      c.setHiddenObjectIds({'tx'});
      c.updateContent(_content([_shape, _box], revision: 2));
      final px = await _pixels(c);
      expect(_paper(px.at(200, 50)), isTrue);
      expect(c.hitTestObject(const ui.Offset(200, 50))?.id, 'tx');
      c.setHiddenObjectIds(const {});
      expect(_paper((await _pixels(c)).at(200, 50)), isFalse);
    });
  });

  group('setPreviewObjects', () {
    test('a committed id is replaced, another id is added, a hidden id\'s '
        'preview is drawn (preview > hidden); hit tests never see previews', () async {
      final c = _controller();
      final base = await _pixels(c);
      final content = c.content;

      // the shape moved down by 120 pt: drawn there, not at its committed place
      final moved = _shape.transformed(core.Affine2.translation(0, 120));
      c.setPreviewObjects([moved]);
      var px = await _pixels(c);
      expect(_paper(px.at(20, 50)), isTrue, reason: 'committed one replaced');
      expect(_paper(px.at(20, 170)), isFalse, reason: 'the preview');
      expect(c.hitTestObject(const ui.Offset(22, 170))?.id, 'im');
      expect(c.hitTestObject(const ui.Offset(22, 50))?.id, 'sh');

      // another id: drawn in its layer (annotation over the image), nothing replaced
      final extra = _text(const core.PageRect(60, 160, 200, 200), id: 'new');
      c.setPreviewObjects([moved, extra]);
      px = await _pixels(c);
      expect(_near(px.at(100, 180), _green), isTrue, reason: 'text > image');
      expect(_paper(px.at(200, 50)), isFalse, reason: 'tx still drawn');
      expect(c.hitTestObject(const ui.Offset(180, 170))?.id, isNull);

      // a hidden id's preview is drawn (EDITOR's sheet draft over its hidden box)
      c
        ..setPreviewObjects(const [])
        ..setHiddenObjectIds({'tx'});
      final draft = _box.copyWith(
        frame: const core.ElementFrame(core.PageRect(140, 20, 240, 120)),
      );
      c.setPreviewObjects([draft]);
      px = await _pixels(c);
      expect(_near(px.at(200, 100), _green), isTrue, reason: 'the draft');
      expect(_near(px.at(200, 50), _green), isTrue);
      c.setPreviewObjects(const []);
      px = await _pixels(c);
      expect(_paper(px.at(200, 50)), isTrue, reason: 'hidden again');
      c.setHiddenObjectIds(const {});
      expect(_diff(await _pixels(c), base), 0);
      expect(identical(c.content, content), isTrue, reason: 'never stored');
    });

    test('60 updates of one preview: the base chunk is recorded once and only '
        'the live part repaints', () async {
      final c = _controller();
      final base = await _pixels(c);
      final ink = inkChunkCacheOf(c);
      final annotation = inkAnnotationCacheOf(c);
      final inkStart = ink.recordCount, annStart = annotation.recordCount;
      final repaints = _repaints(c);

      var inkBase = 0, inkActive = 0;
      for (var i = 1; i <= 60; i++) {
        c.setPreviewObjects([
          _shape.transformed(core.Affine2.translation(i.toDouble(), 100)),
        ]);
        inkBase += repaints[InkRenderLayer.inkBase]!;
        inkActive += repaints[InkRenderLayer.inkActive]!;
        expect(
          _fired(repaints)
              .difference({InkRenderLayer.inkBase, InkRenderLayer.inkActive}),
          isEmpty,
          reason: 'update $i',
        );
        _paintAll(c);
      }
      expect(inkBase, 1, reason: 'the replaced-id set changed once');
      expect(inkActive, 60);
      expect(ink.recordCount, inkStart + 1);
      final last = await _pixels(c);
      expect(_paper(last.at(80, 150)), isFalse, reason: 'the last preview');

      // a text box preview: the annotation layer repaints, its chunk records once
      for (var i = 1; i <= 60; i++) {
        c.setPreviewObjects([
          _box.copyWith(
            frame: core.ElementFrame(
              core.PageRect(140, 20.0 + i, 240, 80.0 + i),
            ),
          ),
        ]);
        _paintAll(c);
      }
      expect(annotation.recordCount, annStart + 1);
      expect(ink.recordCount, inkStart + 2, reason: 'the shape is back');
      c.setPreviewObjects(const []);
      expect(_diff(await _pixels(c), base), 0, reason: 'empty → as committed');
      expect(annotation.recordCount, annStart + 2);
    });

    test('another page\'s object → ArgumentError, nothing changes; the getters '
        'are the given values', () {
      final c = _controller();
      final repaints = _repaints(c);
      final mine = _shape.transformed(core.Affine2.translation(5, 5));
      final list = [mine, mine];
      c.setPreviewObjects(list);
      expect(c.previewObjects, list, reason: 'duplicates kept');
      expect(() => c.previewObjects.add(_box), throwsUnsupportedError);
      _fired(repaints);

      final foreign = PageObjectFixtures.shape(pageId: 'p2', id: 'other');
      expect(
        () => c.setPreviewObjects([mine, foreign]),
        throwsA(isA<ArgumentError>()),
      );
      expect(c.previewObjects, list, reason: 'unchanged');
      expect(_fired(repaints), isEmpty);

      c.setHiddenObjectIds({'x', 'sh'});
      expect(c.hiddenObjectIds, {'x', 'sh'});
      expect(() => c.hiddenObjectIds.add('y'), throwsUnsupportedError);
      c.setPreviewObjects(const []);
      expect(c.previewObjects, isEmpty);
      expect(listEquals(c.previewObjects, const []), isTrue);
    });
  });
}

bool _near(List<int> px, int argb, {int tol = 4}) => samePixel(px, [
  (argb ~/ 0x10000) % 256,
  (argb ~/ 0x100) % 256,
  argb % 256,
  255,
], tol: tol);
