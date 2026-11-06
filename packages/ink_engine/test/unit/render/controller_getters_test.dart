// T24 (m5-7/03-ink 8.1, 4.10): the (v2.1) read-only getters return what was set —
// unmodifiable, absent ids and duplicates included — and StrokeSession.shapeAssist
// is what beginStroke received; plus the playback focus state rules and
// setPreviewObjects' page check.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/playback.dart';
import 'package:ink_engine/src/render/sessions.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

void main() {
  late InkPageController c;
  setUp(() {
    c = createTestPageController();
    c.updateContent(SyntheticInk.pageContent());
  });
  tearDown(() => c.dispose());

  test('hiddenObjectIds: the set as given (absent ids kept), unmodifiable', () {
    expect(c.hiddenObjectIds, isEmpty);
    c.setHiddenObjectIds({'gone', 'x'});
    expect(c.hiddenObjectIds, {'gone', 'x'});
    expect(() => c.hiddenObjectIds.add('y'), throwsUnsupportedError);
    final before = c.hiddenObjectIds;
    c.setHiddenObjectIds({'x', 'gone'}); // same set → nothing happens
    expect(identical(c.hiddenObjectIds, before), isTrue);
    c.setHiddenObjectIds(const {});
    expect(c.hiddenObjectIds, isEmpty);
  });

  test(
    'previewObjects: the last list as given (duplicates kept), unmodifiable',
    () {
      final a = PageObjectFixtures.shape(pageId: 'p1', id: 'a');
      final a2 = PageObjectFixtures.shape(
        pageId: 'p1',
        id: 'a',
        rect: const core.PageRect(0, 0, 10, 10),
      );
      c.setPreviewObjects([a, a2]);
      expect(c.previewObjects, [same(a), same(a2)]);
      expect(() => c.previewObjects.add(a), throwsUnsupportedError);
      c.setPreviewObjects(const []);
      expect(c.previewObjects, isEmpty);
    },
  );

  test('setPreviewObjects with an object of another page → ArgumentError', () {
    final other = PageObjectFixtures.shape(pageId: 'p2', id: 'o');
    expect(() => c.setPreviewObjects([other]), throwsArgumentError);
    expect(c.previewObjects, isEmpty);
  });

  test('playbackFocus: the value as given; the drawing side normalizes', () {
    expect(c.playbackFocus, isNull);
    const odd = InkPlaybackFocus(
      recordingId: 'r1',
      positionMs: -5,
      recentWindowMs: 90000,
    );
    c.setPlaybackFocus(odd);
    expect(c.playbackFocus, same(odd));
    final drawn = normalizedPlaybackFocus(odd);
    expect(drawn.positionMs, 0);
    expect(drawn.recentWindowMs, 60000);
    expect(drawn.style, InkPlaybackStyle.dimUnwritten);
    const normal = InkPlaybackFocus(recordingId: 'r1', positionMs: 10);
    expect(identical(normalizedPlaybackFocus(normal), normal), isTrue);
    c.setPlaybackFocus(null);
    expect(c.playbackFocus, isNull);
  });

  test('InkPlaybackFocus value semantics and defaults', () {
    const a = InkPlaybackFocus(recordingId: 'r', positionMs: 5);
    expect(a.style, InkPlaybackStyle.dimUnwritten);
    expect(a.recentWindowMs, 2000);
    expect(a, const InkPlaybackFocus(recordingId: 'r', positionMs: 5));
    expect(
      a == const InkPlaybackFocus(recordingId: 'r', positionMs: 6),
      isFalse,
    );
    expect(
      a.hashCode,
      const InkPlaybackFocus(recordingId: 'r', positionMs: 5).hashCode,
    );
  });

  test('StrokeSession.shapeAssist = what beginStroke received', () {
    final style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
    final first = SyntheticInk.line(Offset.zero, const Offset(10, 0)).first;
    final off = c.beginStroke(first, style: style, viewScale: 1);
    expect(off.shapeAssist, ShapeAssist.off);
    expect(off.shapePreview.value, isNull);
    off.cancel();
    final on = c.beginStroke(
      first,
      style: style,
      viewScale: 1,
      shapeAssist: ShapeAssist.holdToSnap,
    );
    expect(on.shapeAssist, ShapeAssist.holdToSnap);
    expect(on.shapePreview.value, isNull);
    on.cancel();
    // ignored for the highlighter — but the getter still reports what was given
    final hl = c.beginStroke(
      first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.highlighter),
      viewScale: 1,
      shapeAssist: ShapeAssist.holdToSnap,
    );
    expect(hl.shapeAssist, ShapeAssist.holdToSnap);
    expect(strokeSessionFitterOf(hl), isNull);
    hl.cancel();
  });

  test('getters survive updateContent', () {
    c.setHiddenObjectIds({'x'});
    const f = InkPlaybackFocus(recordingId: 'r1', positionMs: 1);
    c.setPlaybackFocus(f);
    c.updateContent(SyntheticInk.pageContent(revision: 2));
    expect(c.hiddenObjectIds, {'x'});
    expect(c.playbackFocus, same(f));
  });
}
