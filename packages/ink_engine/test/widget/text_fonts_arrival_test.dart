// m5-7/03-ink 8.2 T34 (6.10.3, 6.24, 4.10): a text box drawn before NoteSans is
// there.
// - It is drawn at once with the system font, the implicit load starts, and
//   once NoteSans is loaded only the annotation chunks that drew a text box are
//   recorded again (InkDrawKeys.fonts): the ink, underlay and other annotation
//   chunks keep their pictures, the layer repaints, and the new pixels equal a
//   page drawn with NoteSans from the start (and differ from the system font).
// - A failed load warns `fontLoadFailed` once and keeps the system font; no new
//   load during the 30 s pause (4.10); the first paint after it loads again and
//   redraws.
// - A load started by someone else (EDITOR's measure, a direct ensureLoaded)
//   redraws the page too.
// Its own file: the first test needs a process where NoteSans was never
// registered with the engine (objects_render_test loads it in setUpAll).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/base_cache.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show
        inkAnnotationCacheOf,
        inkChunkCacheOf,
        inkPageRenderOf,
        inkUnderlayCacheOf;
import 'package:ink_engine/src/text/fonts.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../support/pixels.dart';

const _pageId = 'p1';

Future<Uint8List> _bundled({required bool bold}) async {
  final data = await rootBundle.load(
    'packages/ink_engine/assets/fonts/NoteSans-${bold ? 'Bold' : 'Regular'}.ttf',
  );
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

core.TextBoxObject _box(String id, core.PageRect r, String text) =>
    core.TextBoxObject(
      id: id,
      pageId: _pageId,
      frame: core.ElementFrame(r),
      text: text,
      style: const core.TextBoxStyle(fontSizePt: 24),
      createdAt: 3,
    );

// A4 at 256 pt chunks = 3 × 4 (col, row): text in (0, 0) and (2, 1), the formula
// (annotation, no fonts key) in (1, 3), the image (underlay) and the stroke (ink).
final _objects = <core.PageObject>[
  _box('t1', const core.PageRect(20, 20, 220, 120), '안녕 필기 Note'),
  _box('t2', const core.PageRect(530, 270, 590, 330), '가나'),
  PageObjectFixtures.math(
    pageId: _pageId,
    id: 'mx',
    rect: const core.PageRect(300, 780, 400, 820),
    createdAt: 4,
  ),
  PageObjectFixtures.image(
    pageId: _pageId,
    assetId: 'a1',
    id: 'im',
    rect: const core.PageRect(20, 300, 100, 380),
    createdAt: 1,
  ),
];
final _stroke = strokeThrough(
  segment(const ui.Offset(300, 300), const ui.Offset(400, 320)),
  core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
  id: 's1',
);

InkPageController _controller() => createTestPageController()
  ..updateContent(
    InkPageContent.fromCore(
      page: SyntheticInk.page(pageId: _pageId),
      strokes: [_stroke],
      objects: _objects,
      revision: 1,
    ),
  );

void _paintAll(InkPageController c) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

/// The text box t1's region (20..220 × 20..120) at 1 px per pt over white paper.
Future<Pixels> _textPixels(InkPageController c) =>
    renderPixels(240, 140, (canvas) {
      paintPaper(canvas, 0xFFFFFFFF);
      final render = inkPageRenderOf(c);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

int _diff(Pixels a, Pixels b) {
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (!samePixel(a.at(x, y), b.at(x, y), tol: 2)) n++;
    }
  }
  return n;
}

int _ink(Pixels p) {
  var n = 0;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      if (!samePixel(p.at(x, y), const [255, 255, 255, 255])) n++;
    }
  }
  return n;
}

/// The chunk generations of [cache], one per chunk.
List<int> _generations(InkChunkCache cache) => [
  for (var i = 0; i < cache.chunkCount; i++) cache.generationOf(i),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var nowUs = 0;
  setUpAll(() => InkFontsDebug.nowUs = () => nowUs);

  test('drawn with the system font, then only the annotation chunks with a '
      'text box again once NoteSans is loaded', () async {
    expect(InkFontsDebug.isLoaded, isFalse);
    final gate = Completer<void>();
    var reads = 0;
    debugSetInkFontSource(({required bool bold}) async {
      reads++;
      await gate.future;
      return _bundled(bold: bold);
    });
    addTearDown(() => debugSetInkFontSource(null));
    final c = _controller();
    addTearDown(c.dispose);
    final ink = inkChunkCacheOf(c);
    final underlay = inkUnderlayCacheOf(c);
    final annotation = inkAnnotationCacheOf(c);

    final system = await _textPixels(c);
    _paintAll(c);
    expect(_ink(system), greaterThan(300), reason: 'drawn at once');
    expect(InkFontsDebug.isLoading, isTrue, reason: 'implicit load (7.4.5)');
    expect(reads, 2, reason: 'regular and bold, once');
    expect(annotation.drawKeysAt(0, 0), contains(InkDrawKeys.fonts));
    expect(annotation.drawKeysAt(2, 1), contains(InkDrawKeys.fonts));
    expect(annotation.drawKeysAt(1, 3), isNot(contains(InkDrawKeys.fonts)));
    final before = (
      ink.recordCount,
      underlay.recordCount,
      annotation.recordCount,
    );
    final inkGen = _generations(ink), underGen = _generations(underlay);
    final annGen = _generations(annotation);

    var repaints = 0;
    void count() => repaints++;
    c.layerRepaint(InkRenderLayer.annotation).addListener(count);
    addTearDown(
      () => c.layerRepaint(InkRenderLayer.annotation).removeListener(count),
    );
    gate.complete();
    await InkFontsDebug.loadImplicitly();
    await pumpEventQueue();
    expect(InkFontsDebug.isLoaded, isTrue);
    expect(repaints, greaterThan(0), reason: 'the layer is told to repaint');
    expect(annotation.dirtyCount, 2, reason: 'the two text chunks only');

    final loaded = await _textPixels(c);
    _paintAll(c);
    expect(
      (ink.recordCount, underlay.recordCount, annotation.recordCount),
      (before.$1, before.$2, before.$3 + 2),
    );
    expect(_generations(ink), inkGen);
    expect(_generations(underlay), underGen);
    final now = _generations(annotation);
    for (var i = 0; i < now.length; i++) {
      final text = i == 0 * 3 + 0 || i == 1 * 3 + 2;
      expect(now[i] != annGen[i], text, reason: 'chunk $i');
    }
    expect(annotation.drawKeysAt(0, 0), isNot(contains(InkDrawKeys.fonts)));
    expect(
      _diff(system, loaded),
      greaterThan(50),
      reason: 'NoteSans differs from the system font',
    );
    // = a page drawn with NoteSans from the start
    final fresh = _controller();
    addTearDown(fresh.dispose);
    expect(_diff(loaded, await _textPixels(fresh)), 0);
    expect(reads, 2, reason: 'no second load');
  });

  test('a failed load warns fontLoadFailed; no new load in the 30 s pause; the '
      'first paint after it loads and redraws', () async {
    var failing = true, reads = 0;
    debugSetInkFontSource(({required bool bold}) async {
      reads++;
      if (failing) throw StateError('offline');
      return _bundled(bold: bold);
    });
    addTearDown(() => debugSetInkFontSource(null));
    nowUs = 1000000;
    final c = _controller();
    addTearDown(c.dispose);
    c.diagnostics.enabled = true;
    addTearDown(() => c.diagnostics.enabled = false);
    final annotation = inkAnnotationCacheOf(c);

    _paintAll(c);
    await pumpEventQueue();
    expect(InkFontsDebug.isLoaded, isFalse);
    expect(c.diagnostics.snapshot.warnings, 1, reason: 'fontLoadFailed');
    expect(reads, greaterThan(0));
    final records = annotation.recordCount;
    expect(_ink(await _textPixels(c)), greaterThan(300), reason: 'system font');

    // inside the pause: painting does not load again, no second warning
    final readsAfterFailure = reads;
    nowUs += (InkTuning.fontRetryAfterMs - 1000) * 1000;
    _paintAll(c);
    await pumpEventQueue();
    expect(InkFontsDebug.isLoading, isFalse);
    expect(reads, readsAfterFailure);
    expect(c.diagnostics.snapshot.warnings, 1);

    // after the pause: the next paint loads, the text chunks are recorded again
    failing = false;
    nowUs += 2000 * 1000;
    _paintAll(c);
    expect(InkFontsDebug.isLoading, isTrue);
    await InkFontsDebug.loadImplicitly();
    await pumpEventQueue();
    expect(InkFontsDebug.isLoaded, isTrue);
    expect(annotation.dirtyCount, 2);
    _paintAll(c);
    expect(annotation.recordCount, records + 2);
    expect(c.diagnostics.snapshot.warnings, 1);
  });

  test('a load started by someone else (a direct ensureLoaded) redraws the '
      'page too', () async {
    var failing = true;
    debugSetInkFontSource(({required bool bold}) async {
      if (failing) throw StateError('offline');
      return _bundled(bold: bold);
    });
    addTearDown(() => debugSetInkFontSource(null));
    final c = _controller();
    addTearDown(c.dispose);
    final annotation = inkAnnotationCacheOf(c);
    _paintAll(c);
    await pumpEventQueue();
    expect(InkFontsDebug.isLoaded, isFalse);
    final records = annotation.recordCount;

    // a disposed controller is not told (its listener is gone)
    final gone = _controller();
    _paintAll(gone);
    gone.dispose();

    failing = false;
    await InkFonts.ensureLoaded(); // a direct call tries again at once
    expect(annotation.dirtyCount, 2);
    _paintAll(c);
    expect(annotation.recordCount, records + 2);
    expect(annotation.drawKeysAt(2, 1), isNot(contains(InkDrawKeys.fonts)));
  });
}
