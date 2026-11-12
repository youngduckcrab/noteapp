@TestOn('browser')
library;

// m5-7/03-ink 8.2 T40 (6.19) on the web (Chrome = CanvasKit, JS numbers): the
// playback index and the layer 4′ emphasis paint without the VM-only typed lists
// (dart2js/DDC have no Int64List — 1차 7.4.3 web-safe numbers). Regression for the
// infra r2-integration report: every paint during playback threw
// 'Int64List not supported on the web' from PlaybackTrack.build.
// - PlaybackTrack.build / upperBound / writing on offsets past 2^31 ms (exact).
// - dimUnwritten paints in the browser: the unwritten stroke is veiled toward the
//   paper, the written one is unchanged; highlightRecent paints too.
// - An InkPageView with a playback focus pumps frames (seeks included) with no
//   FlutterError.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf, playbackIndexOf;
import 'package:ink_engine/src/render/playback_index.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _pageId = 'p1';
const _blue = 0xFF0000FF;
const _white = 0xFFFFFFFF;

core.Stroke _rec(String id, ui.Offset a, ui.Offset b, {required int offset}) {
  final style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
      .copyWith(colorArgb: _blue, width: 8);
  return strokeThrough(
    segment(a, b),
    style,
    id: id,
  ).copyWith(createdAt: 1, recordingId: 'r', recordingOffsetMs: offset);
}

InkPageContent _content(List<core.Stroke> strokes) => InkPageContent.fromCore(
  page: SyntheticInk.page(
    pageId: _pageId,
    background: const core.BlankBackground(paperColorArgb: _white),
  ),
  strokes: strokes,
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

InkPlaybackFocus _focus(int p, {InkPlaybackStyle? style}) => InkPlaybackFocus(
  recordingId: 'r',
  positionMs: p,
  style: style ?? InkPlaybackStyle.dimUnwritten,
  recentWindowMs: 2000,
);

void main() {
  test('PlaybackTrack on JS numbers: offsets past 2^31 ms stay exact', () {
    const big = 3000000000; // > 2^31 − 1 (≈ 34.7 days)
    final strokes = [
      _rec('c', const ui.Offset(10, 10), const ui.Offset(50, 10), offset: big),
      _rec('a', const ui.Offset(10, 20), const ui.Offset(50, 20), offset: 0),
      _rec('b', const ui.Offset(10, 30), const ui.Offset(50, 30), offset: 500),
    ];
    final track = PlaybackTrack.build('r', _content(strokes).strokes.toList());
    expect([for (final e in track.entries) e.stroke.id], ['a', 'b', 'c']);
    expect(track.entries.last.offsetMs, big);
    expect(track.boundary(big - 1), 2);
    expect(track.boundary(big), 3);
    expect(track.upperBound(499), 1);
    // segment 40 pt, points 2 pt apart, t 10 ms apart → tLast 200 ms
    expect(track.writing(big + 1), [2]);
  });

  test('dimUnwritten and highlightRecent paint in the browser', () async {
    final c = createTestPageController()
      ..updateContent(
        _content([
          _rec(
            'u',
            const ui.Offset(20, 40),
            const ui.Offset(280, 40),
            offset: 5000,
          ),
          _rec(
            'w',
            const ui.Offset(20, 120),
            const ui.Offset(280, 120),
            offset: 0,
          ),
        ]),
      );
    addTearDown(c.dispose);
    final off = await _pixelsOf(c);
    c.setPlaybackFocus(_focus(4000));
    final on = await _pixelsOf(c);
    expect(playbackIndexOf(c), isNotNull);
    final ink = off.at(150, 40);
    final veiled = on.at(150, 40);
    expect(
      samePixel(ink, [0, 0, 255, 255], tol: 3),
      isTrue,
      reason: 'ink $ink',
    );
    // paper × 0.75 over the ink: red and green rise toward the white paper
    expect(veiled[0], greaterThan(150), reason: 'veiled $veiled');
    expect(veiled[1], greaterThan(150), reason: 'veiled $veiled');
    expect(
      samePixel(on.at(150, 120), off.at(150, 120), tol: 1),
      isTrue,
      reason: 'the written stroke is unchanged',
    );
    c.setPlaybackFocus(_focus(5100, style: InkPlaybackStyle.highlightRecent));
    final recent = await _pixelsOf(c);
    expect(recent.width, 300);
  });

  testWidgets('InkPageView with a playback focus: frames and seeks, no error', (
    tester,
  ) async {
    final c = createTestPageController()
      ..updateContent(
        _content([
          for (var i = 0; i < 20; i++)
            _rec(
              's$i',
              ui.Offset(20, 20.0 + i * 12),
              ui.Offset(280, 20.0 + i * 12),
              offset: i * 300,
            ),
        ]),
      );
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    for (final p in [0, 16, 32, 1500, 6000, 200, 3000000000]) {
      c.setPlaybackFocus(_focus(p));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'position $p');
    }
    c.setPlaybackFocus(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
