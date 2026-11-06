// m5-7/04-editor 8.2 E2-20, 6.20: the shape sample ring buffer — the last 5
// pen sessions, newest first (a 6th pushes out the 1st); what came out
// ('stroke' / 'addShape:<kind>' from INK's addShape edit); LIBRARY's sample
// format ({kind, points: [[x, y], …] to 2 decimals, viewScale} — 05-library
// 6.17). The toggle (nothing is kept while '도형 표본 모으기' is off) is
// checked through the editor in widget/dev_menu_test.dart.
import 'dart:convert';

import 'package:feature_editor/src/tools/shape_samples.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/ink_edit_builders.dart';
import '../helpers/test_data.dart';

ShapeSample _sample(int i, {String result = 'stroke'}) => ShapeSample(
  points: [Offset(i.toDouble(), 0), Offset(i + 10.0, 5)],
  viewScale: 1.5,
  result: result,
  at: 1000 + i,
);

void main() {
  test('empty at first; the last 5, newest first — a 6th pushes out the '
      '1st; clear', () {
    final samples = ShapeSamples();
    addTearDown(samples.dispose);
    var notified = 0;
    samples.addListener(() => notified++);
    expect(samples.samples, isEmpty);
    for (var i = 1; i <= 5; i++) {
      samples.add(_sample(i));
    }
    expect(samples.samples.map((s) => s.at), [1005, 1004, 1003, 1002, 1001]);
    samples.add(_sample(6));
    expect(samples.samples, hasLength(ShapeSamples.capacity));
    expect(samples.samples.map((s) => s.at), [1006, 1005, 1004, 1003, 1002]);
    expect(notified, 6);
    expect(() => samples.samples.add(_sample(7)), throwsUnsupportedError);
    samples.clear();
    expect(samples.samples, isEmpty);
    samples.clear(); // nothing to clear: no notification
    expect(notified, 7);
  });

  test('resultOf: addShape → addShape:<kind>; a stroke, another edit or '
      'none → stroke', () {
    final ellipse = PageObjectFixtures.shape(
      pageId: 'p',
      id: 'shape-e',
      kind: core.ShapeKind.ellipse,
    );
    expect(resultOf(addShapeEdit('p', ellipse)), 'addShape:ellipse');
    expect(
      resultOf(
        addShapeEdit(
          'p',
          PageObjectFixtures.shape(pageId: 'p', kind: core.ShapeKind.star),
        ),
      ),
      'addShape:star',
    );
    expect(
      resultOf(
        ink.InkEdit(
          kind: ink.InkEditKind.addStroke,
          pageId: 'p',
          added: [strokeA],
        ),
      ),
      'stroke',
    );
    expect(resultOf(eraseStrokesEdit('p', strokeIds: {'s'})), 'stroke');
    expect(resultOf(null), 'stroke');
  });

  test('LIBRARY format: kind (expected or none), points [[x, y], …] to 2 '
      'decimals, viewScale — the same keys and types', () {
    const sample = ShapeSample(
      points: [Offset(10.123, 20.456), Offset(30.005, 40), Offset(-1.239, 0)],
      viewScale: 1.68,
      result: 'addShape:rectangle',
      at: 1,
    );
    final json = shapeSampleJson(sample, expected: core.ShapeKind.rectangle);
    expect(json.keys, ['kind', 'points', 'viewScale']);
    expect(json['kind'], 'rectangle');
    expect(json['viewScale'], 1.68);
    final points = json['points']! as List<Object?>;
    expect(points, [
      [10.12, 20.46],
      [30.01, 40.0],
      [-1.24, 0.0],
    ]);
    for (final p in points) {
      expect(p, isA<List<double>>());
      expect((p! as List).length, 2);
    }
    expect(shapeSampleJson(sample, expected: null)['kind'], 'none');

    // The copied text decodes back to the same map.
    final decoded = jsonDecode(
      shapeSampleText(sample, expected: core.ShapeKind.line),
    ) as Map<String, Object?>;
    expect(decoded['kind'], 'line');
    expect(decoded['points'], [
      [10.12, 20.46],
      [30.01, 40.0],
      [-1.24, 0.0],
    ]);
    expect(decoded['viewScale'], 1.68);
  });
}
