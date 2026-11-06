// m5-7/03-ink T31 (4.3, 6.7-6): the memorization tape state of a controller —
// toggleTape flips one tape, setAllTapesRevealed applies to the tapes present
// now (later tapes start covered), a tape that leaves the content leaves the
// state, ids that are not tapes are ignored; the state is never stored (the
// content is not touched) and lives as long as the controller.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkCoverCacheOf, inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

core.Stroke _stroke(String id, double y, core.PenTool tool, int createdAt) =>
    strokeThrough(
      segment(Offset(20, y), Offset(180, y)),
      core.StrokeStyle.defaultsFor(tool),
      id: id,
    ).copyWith(createdAt: createdAt);

InkPageContent _content(List<core.Stroke> strokes, {int revision = 1}) =>
    InkPageContent.fromCore(
      page: SyntheticInk.page(pageId: 'p1'),
      strokes: strokes,
      revision: revision,
    );

void _paintCover(InkPageController c) {
  final r = PictureRecorder();
  inkPageRenderOf(c).paint(Canvas(r), InkRenderLayer.cover, 1);
  r.endRecording().dispose();
}

void main() {
  final t1 = _stroke('t1', 40, core.PenTool.tape, 1);
  final t2 = _stroke('t2', 80, core.PenTool.tape, 2);
  final ink = _stroke('ink', 120, core.PenTool.ballpoint, 3);

  test('tapes are cover-layer strokes; everything starts covered', () {
    final c = createTestPageController()..updateContent(_content([t1, ink]));
    addTearDown(c.dispose);
    expect(InkStroke.of(t1).layer, InkLayer.cover);
    expect(InkStroke.of(ink).layer, InkLayer.ink);
    expect(c.isTapeRevealed('t1'), isFalse);
  });

  test('toggleTape flips one tape; the content is not touched', () {
    final content = _content([t1, t2, ink]);
    final c = createTestPageController()..updateContent(content);
    addTearDown(c.dispose);
    var notified = 0;
    c.layerRepaint(InkRenderLayer.cover).addListener(() => notified++);
    c.toggleTape('t1');
    expect(c.isTapeRevealed('t1'), isTrue);
    expect(c.isTapeRevealed('t2'), isFalse);
    expect(notified, 1);
    c.toggleTape('t1');
    expect(c.isTapeRevealed('t1'), isFalse);
    expect(notified, 2);
    expect(identical(c.content, content), isTrue, reason: 'never stored');
  });

  test('ids that are not tapes of this page are ignored', () {
    final c = createTestPageController()..updateContent(_content([t1, ink]));
    addTearDown(c.dispose);
    _paintCover(c);
    final records = inkCoverCacheOf(c).recordCount;
    var notified = 0;
    c.layerRepaint(InkRenderLayer.cover).addListener(() => notified++);
    for (final id in ['ink', 'nope', '']) {
      c.toggleTape(id);
      expect(c.isTapeRevealed(id), isFalse, reason: id);
    }
    expect(notified, 0);
    expect(inkCoverCacheOf(c).isDirty, isFalse);
    _paintCover(c);
    expect(inkCoverCacheOf(c).recordCount, records);
  });

  test('setAllTapesRevealed applies to the tapes present now; later tapes '
      'start covered', () {
    final c = createTestPageController()..updateContent(_content([t1, ink]));
    addTearDown(c.dispose);
    c.setAllTapesRevealed(true);
    expect(c.isTapeRevealed('t1'), isTrue);
    expect(c.isTapeRevealed('ink'), isFalse);
    c.updateContent(_content([t1, t2, ink], revision: 2));
    expect(c.isTapeRevealed('t1'), isTrue, reason: 'kept across updates');
    expect(c.isTapeRevealed('t2'), isFalse, reason: 'arrived later');
    c.setAllTapesRevealed(true);
    expect(c.isTapeRevealed('t2'), isTrue);
    c.setAllTapesRevealed(false);
    expect(c.isTapeRevealed('t1'), isFalse);
    expect(c.isTapeRevealed('t2'), isFalse);
  });

  test('a deleted tape leaves the state (it comes back covered)', () {
    final c = createTestPageController()..updateContent(_content([t1, t2]));
    addTearDown(c.dispose);
    c
      ..toggleTape('t1')
      ..toggleTape('t2');
    c.updateContent(_content([t2], revision: 2));
    expect(c.isTapeRevealed('t1'), isFalse);
    expect(c.isTapeRevealed('t2'), isTrue);
    // undo brings it back: covered (the state is not stored — U10)
    c.updateContent(_content([t1, t2], revision: 3));
    expect(c.isTapeRevealed('t1'), isFalse);
    expect(c.isTapeRevealed('t2'), isTrue);
  });

  test('a new controller (autoDispose) starts covered', () {
    final a = createTestPageController()..updateContent(_content([t1]));
    a.toggleTape('t1');
    expect(a.isTapeRevealed('t1'), isTrue);
    a.dispose();
    final b = createTestPageController()..updateContent(_content([t1]));
    addTearDown(b.dispose);
    expect(b.isTapeRevealed('t1'), isFalse);
  });

  test('toggles and the revealed set re-record the cover picture only', () {
    final c = createTestPageController()..updateContent(_content([t1, t2]));
    addTearDown(c.dispose);
    _paintCover(c);
    final cover = inkCoverCacheOf(c);
    expect(cover.recordCount, 1);
    expect(cover.strokeCount, 2);
    _paintCover(c);
    expect(cover.recordCount, 1, reason: 'nothing changed');
    c.toggleTape('t1');
    _paintCover(c);
    expect(cover.recordCount, 2);
    c.setAllTapesRevealed(true);
    _paintCover(c);
    expect(cover.recordCount, 3);
  });
}
