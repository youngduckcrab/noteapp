// (v2.13-rec) Objects converted from strokes keep the recording time of the
// handwriting: buildTextBox, buildMathFromStrokes and buildMathFromPen link
// the object to the recording of its earliest recorded source stroke at that
// recording's earliest source offset (not the conversion time); no recorded
// source stroke → no link. createdAt stays the conversion time.
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

core.Stroke _g(String id, double x, int createdAt, {String? rec, int? at}) =>
    glyphStroke(
      id,
      x,
      200,
      20,
      createdAt: createdAt,
    ).copyWith(recordingId: rec, recordingOffsetMs: at);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ink_testing.useInkTestFonts);

  // written in the order a (3000 ms) → b (3800 ms) → c (4500 ms); the list is
  // not in that order
  final recorded = [
    _g('b', 140, 20, rec: 'r1', at: 3800),
    _g('c', 180, 30, rec: 'r1', at: 4500),
    _g('a', 100, 10, rec: 'r1', at: 3000),
  ];
  final plain = [_g('x', 100, 10), _g('y', 140, 20)];
  const bounds = Rect.fromLTWH(100, 200, 120, 20);

  test('buildMathFromPen: the formula takes the first stroke time', () {
    final m = buildMathFromPen(
      id: 'm',
      pageId: kPageId,
      nowMs: 99999,
      latex: 'x^{2}',
      engineId: 'e/1',
      strokes: recorded,
    )!;
    expect(m.recordingId, 'r1');
    expect(m.recordingOffsetMs, 3000);
    expect(m.createdAt, 99999);
    // its ink keeps every stroke's own time
    expect([for (final s in m.ink) s.recordingOffsetMs], [3000, 3800, 4500]);
  });

  test(
    'buildMathFromStrokes and buildTextBox: the first stroke time',
    () async {
      final m = buildMathFromStrokes(
        id: 'm',
        pageId: kPageId,
        nowMs: 99999,
        latex: 'x^{2}',
        engineId: 'e/1',
        inputStrokes: recorded,
        boundsPt: bounds,
      )!;
      expect((m.recordingId, m.recordingOffsetMs), ('r1', 3000));
      final box = await buildTextBox(
        id: 't',
        pageId: kPageId,
        nowMs: 99999,
        text: 'abc',
        inputStrokes: recorded,
        boundsPt: bounds,
        pageSize: core.PageSize.a4Portrait,
      );
      expect((box.recordingId, box.recordingOffsetMs), ('r1', 3000));
      expect(box.createdAt, 99999);
    },
  );

  test('no recorded source stroke → no link; mixed recordings → the earliest '
      'recorded stroke\'s recording', () async {
    final none = buildMathFromPen(
      id: 'm',
      pageId: kPageId,
      nowMs: 5,
      latex: 'x',
      engineId: 'e/1',
      strokes: plain,
    )!;
    expect(none.recordingId, isNull);
    expect(none.recordingOffsetMs, isNull);
    final box = await buildTextBox(
      id: 't',
      pageId: kPageId,
      nowMs: 5,
      text: 'xy',
      inputStrokes: [
        _g('late', 200, 50, rec: 'r2', at: 100),
        _g('early', 220, 40, rec: 'r1', at: 9000),
        _g('early2', 240, 60, rec: 'r1', at: 8000),
      ],
      boundsPt: bounds,
      pageSize: core.PageSize.a4Portrait,
    );
    expect((box.recordingId, box.recordingOffsetMs), ('r1', 8000));
  });

  test('a source stroke written before the recording (or while paused) → no '
      'link: that part was always shown, so the object is too', () async {
    // "x+" before recording, "1" at 4 s, converted with the math pen
    final mixed = [_g('x', 100, 10), _g('+', 140, 20), ...recorded];
    final m = buildMathFromPen(
      id: 'm',
      pageId: kPageId,
      nowMs: 99999,
      latex: 'x+1',
      engineId: 'e/1',
      strokes: mixed,
    )!;
    expect(m.recordingId, isNull);
    expect(m.recordingOffsetMs, isNull);
    final f = buildMathFromStrokes(
      id: 'm2',
      pageId: kPageId,
      nowMs: 99999,
      latex: 'x+1',
      engineId: 'e/1',
      inputStrokes: mixed,
      boundsPt: bounds,
    )!;
    expect(f.recordingId, isNull);
    final box = await buildTextBox(
      id: 't',
      pageId: kPageId,
      nowMs: 99999,
      text: 'x+1',
      inputStrokes: mixed,
      boundsPt: bounds,
      pageSize: core.PageSize.a4Portrait,
    );
    expect(box.recordingId, isNull);
  });
}
