// (v2.13-rec) Page objects in the playback emphasis: an object linked to the
// focused recording (PageObject.recordingId / recordingOffsetMs) is dimmed like
// an unwritten stroke (its own pixels veiled with the paper color at
// 1 − playbackDimOpacity) while positionMs < its offset and drawn as usual from
// its offset on; objects of other recordings or without one, and every object
// under highlightRecent, are unchanged. Shapes and images: the veil at layer 4′;
// text boxes and formulas: at the end of the annotation layer, which repaints
// only when the set of dimmed annotation objects changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';

const _pageId = 'p1';
const _blue = 0xFF0000FF;
const _white = 0xFFFFFFFF;

core.ShapeObject _shape(
  String id, {
  String? recording = 'r',
  int offset = 1000,
  core.PageRect rect = const core.PageRect(40, 40, 140, 140),
}) {
  final s = core.ShapeObject(
    id: id,
    pageId: _pageId,
    shapeKind: core.ShapeKind.rectangle,
    geometry: core.ShapeGeometry.rectangle(rect),
    style: const core.ShapeStyle(strokeColorArgb: _blue, strokeWidth: 8),
    createdAt: 5,
  );
  return recording == null
      ? s
      : s.withRecording(recordingId: recording, recordingOffsetMs: offset)
            as core.ShapeObject;
}

core.TextBoxObject _text(String id, {String? recording = 'r'}) {
  final t = core.TextBoxObject(
    id: id,
    pageId: _pageId,
    frame: const core.ElementFrame(core.PageRect(160, 40, 290, 90)),
    text: '■■■■',
    style: const core.TextBoxStyle(fontSizePt: 32, colorArgb: 0xFF000000),
    createdAt: 6,
  );
  return recording == null
      ? t
      : t.withRecording(recordingId: recording, recordingOffsetMs: 1000)
            as core.TextBoxObject;
}

InkPageContent _content(List<core.PageObject> objects) =>
    InkPageContent.fromCore(
      page: SyntheticInk.page(
        pageId: _pageId,
        background: const core.BlankBackground(paperColorArgb: _white),
      ),
      strokes: const [],
      objects: objects,
      revision: 1,
    );

Future<Pixels> _pixelsOf(InkPageController c) =>
    renderPixels(300, 200, (canvas) {
      paintPaper(canvas, _white);
      final render = inkPageRenderOf(c);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

InkPlaybackFocus _focus(
  int p, {
  InkPlaybackStyle style = InkPlaybackStyle.dimUnwritten,
  String recording = 'r',
}) => InkPlaybackFocus(recordingId: recording, positionMs: p, style: style);

/// The darkest (lowest channel sum) pixel inside [r].
List<int> _darkest(Pixels p, core.PageRect r) {
  List<int>? best;
  var sum = 1 << 30;
  for (var y = r.top.ceil(); y < r.bottom.floor(); y++) {
    for (var x = r.left.ceil(); x < r.right.floor(); x++) {
      final c = p.at(x, y);
      final s = c[0] + c[1] + c[2];
      if (s < sum) {
        sum = s;
        best = c;
      }
    }
  }
  return best!;
}

/// The pixel a veil over [ink] gives on white: 255 × α + ink × (1 − α), α = 0.75.
List<int> _veiled(List<int> ink) {
  const a = 191 / 255;
  return [
    for (var k = 0; k < 3; k++) (255 * a + ink[k] * (1 - a)).round(),
    255,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(InkFonts.ensureLoaded);

  const edge = (40, 90); // on the left edge of the shape
  const textArea = core.PageRect(160, 40, 290, 90);

  test('a linked shape is dimmed before its offset and normal at and '
      'after it', () async {
    final c = createTestPageController()
      ..updateContent(_content([_shape('s1')]));
    addTearDown(c.dispose);
    final off = await _pixelsOf(c);
    final ink = off.at(edge.$1, edge.$2);
    expect(ink[2], greaterThan(200), reason: 'the blue edge is drawn');
    expect(ink[0], lessThan(60));

    c.setPlaybackFocus(_focus(500));
    final before = await _pixelsOf(c);
    expect(
      samePixel(before.at(edge.$1, edge.$2), _veiled(ink), tol: 3),
      isTrue,
      reason: 'got ${before.at(edge.$1, edge.$2)}, want ${_veiled(ink)}',
    );

    for (final p in [1000, 1500]) {
      c.setPlaybackFocus(_focus(p));
      final after = await _pixelsOf(c);
      expect(
        samePixel(after.at(edge.$1, edge.$2), ink, tol: 1),
        isTrue,
        reason: 'at $p ms',
      );
    }
  });

  test('shapes of another recording or without one, and every shape '
      'under highlightRecent, are unchanged', () async {
    for (final (shape, focus) in [
      (_shape('s1', recording: null), _focus(500)),
      (_shape('s1', recording: 'other'), _focus(500)),
      (_shape('s1'), _focus(500, style: InkPlaybackStyle.highlightRecent)),
    ]) {
      final c = createTestPageController()..updateContent(_content([shape]));
      final off = await _pixelsOf(c);
      c.setPlaybackFocus(focus);
      final on = await _pixelsOf(c);
      expect(
        samePixel(on.at(edge.$1, edge.$2), off.at(edge.$1, edge.$2), tol: 1),
        isTrue,
        reason: '$shape $focus',
      );
      c.dispose();
    }
  });

  test('a linked text box is dimmed before its offset (annotation '
      'layer), normal after; an unlinked one is unchanged', () async {
    final c = createTestPageController()
      ..updateContent(_content([_text('t1')]));
    addTearDown(c.dispose);
    final off = await _pixelsOf(c);
    final glyph = _darkest(off, textArea);
    expect(glyph[0], lessThan(40), reason: 'the glyphs are drawn');

    var annotationRepaints = 0;
    c
        .layerRepaint(InkRenderLayer.annotation)
        .addListener(() => annotationRepaints++);
    c.setPlaybackFocus(_focus(500));
    expect(annotationRepaints, 1, reason: 'the dimmed set changed');
    final before = await _pixelsOf(c);
    // every pixel of a glyph's full coverage is the veil over it; no pixel
    // in the frame gets darker
    var full = 0;
    for (var y = 40; y < 90; y++) {
      for (var x = 160; x < 290; x++) {
        final o = off.at(x, y), b = before.at(x, y);
        expect(b[0], greaterThanOrEqualTo(o[0] - 1), reason: '($x, $y)');
        if (o[0] > 2) continue;
        full++;
        expect(
          samePixel(b, _veiled(o), tol: 3),
          isTrue,
          reason: '($x, $y): got $b, want ${_veiled(o)}',
        );
      }
    }
    expect(full, greaterThan(20), reason: 'the glyphs have solid pixels');
    c.setPlaybackFocus(_focus(600));
    expect(annotationRepaints, 1, reason: 'the same set: no repaint');

    c.setPlaybackFocus(_focus(1200));
    expect(annotationRepaints, 2);
    final after = await _pixelsOf(c);
    expect(samePixel(_darkest(after, textArea), glyph, tol: 1), isTrue);

    c.setPlaybackFocus(null);
    expect(annotationRepaints, 2, reason: 'nothing was dimmed');

    final plain = createTestPageController()
      ..updateContent(_content([_text('t2', recording: null)]));
    addTearDown(plain.dispose);
    final plainOff = await _pixelsOf(plain);
    plain.setPlaybackFocus(_focus(500));
    final plainOn = await _pixelsOf(plain);
    expect(
      samePixel(_darkest(plainOn, textArea), _darkest(plainOff, textArea)),
      isTrue,
    );
  });
}
