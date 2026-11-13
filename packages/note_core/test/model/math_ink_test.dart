// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 5) MathObject.ink: the
// handwriting a formula was converted from. JSON round trip, old JSON without the key, null,
// broken entries (formula kept), transform / copy rules, ==, estimatedBytes, the local limits
// and changed fields (a LaTeX edit keeps the ink). Web-safe.
import 'dart:convert';
import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/edit/command_resolver.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

MathObject get _sample => kSampleObjects['math_ink']! as MathObject;

Stroke _stroke(String id, {int n = 3, double x = 0, String pageId = 'p'}) =>
    Stroke(
      id: id,
      pageId: pageId,
      style: StrokeStyle.defaultsFor(PenTool.ballpoint),
      points: StrokePoints.fromList([
        for (var i = 0; i < n; i++)
          StrokePoint(x + i.toDouble(), i * 0.5, widthQ: 0.25, t: i * 4.0),
      ]),
      createdAt: 100,
    );

MathObject _math({List<Stroke> ink = const []}) => MathObject(
  id: 'm',
  pageId: 'p',
  frame: const ElementFrame(PageRect(0, 0, 40, 20)),
  latex: 'x',
  style: const MathStyle(),
  ink: ink,
  createdAt: 1,
);

void main() {
  group('JSON', () {
    test('round trip keeps every ink stroke exactly', () {
      final json =
          jsonDecode(jsonEncode(_sample.toJson())) as Map<String, Object?>;
      final back = PageObject.fromJson(json) as MathObject;
      expect(back, _sample);
      expect(back.ink, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(back.ink[i], _sample.ink[i]);
        expect(back.ink[i].points.contentEquals(_sample.ink[i].points), isTrue);
      }
    });

    test('empty ink is written as null; the key is always there', () {
      final json = _math().toJson();
      expect(json.containsKey('ink'), isTrue);
      expect(json['ink'], isNull);
      expect((PageObject.fromJson(json) as MathObject).ink, isEmpty);
    });

    test('JSON of an older app (no ink key) reads as an empty list', () {
      final old = Map.of(_sample.toJson())..remove('ink');
      final o = PageObject.fromJson(old);
      expect(o, isA<MathObject>());
      expect((o as MathObject).ink, isEmpty);
      expect(o.latex, _sample.latex);
    });

    test('a broken ink entry → empty ink, the formula survives', () {
      final base = _sample.toJson();
      final strokeJson = (base['ink']! as List).first as Map<String, Object?>;
      final cases = <String, Object?>{
        'not a list': 'oops',
        'entry not a map': [1, 2],
        'missing key': [Map.of(strokeJson)..remove('points')],
        'bad base64': [
          {...strokeJson, 'points': '***'},
        ],
        'bad style': [
          {...strokeJson, 'style': 7},
        ],
      };
      for (final MapEntry(key: name, value: ink) in cases.entries) {
        final o = PageObject.fromJson({...base, 'ink': ink});
        expect(o, isA<MathObject>(), reason: name);
        expect((o as MathObject).ink, isEmpty, reason: name);
        expect(o.latex, _sample.latex, reason: name);
        expect(o.id, _sample.id, reason: name);
      }
    });

    test('an older reader keeps the formula (unknown keys of a known type are '
        'ignored)', () {
      // The rule this relies on: MathObject._fromJson reads named keys only.
      final json = {..._sample.toJson(), 'futureKey': 1};
      expect((PageObject.fromJson(json) as MathObject).ink, hasLength(2));
    });
  });

  group('copy and transform rules', () {
    test('transformed moves / scales / rotates the ink with the frame', () {
      final m = Affine2.scaling(
        2,
        2,
      ).then(Affine2.rotation(math.pi / 2)).then(Affine2.translation(10, 5));
      final t = _sample.transformed(m) as MathObject;
      expect(t.ink, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(t.ink[i], _sample.ink[i].transformed(m));
      }
      final noWidth = _sample.transformed(m, scaleWidth: false) as MathObject;
      expect(noWidth.ink.first.style.width, _sample.ink.first.style.width);
      expect(t.ink.first.style.width, closeTo(3.0, 1e-9));
    });

    test('copyTo moves the ink to the new page; copyWithMeta / copyWith keep '
        'it', () {
      final c =
          _sample.copyTo(id: 'n', pageId: 'p2', createdAt: 9) as MathObject;
      expect(c.ink.map((s) => s.pageId), ['p2', 'p2']);
      expect(c.ink.map((s) => s.version), [null, null]);
      expect(c.ink.map((s) => s.id), _sample.ink.map((s) => s.id));
      final meta = _sample.copyWithMeta(updatedAt: 99) as MathObject;
      expect(meta.ink, _sample.ink);
      expect(_sample.copyWith(latex: 'y').ink, _sample.ink);
      expect(_sample.copyWith(ink: const []).ink, isEmpty);
    });

    test('== and hashCode cover ink; ink is unmodifiable', () {
      final a = _math(ink: [_stroke('a')]);
      final b = _math(ink: [_stroke('a')]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == _math(), isFalse);
      expect(a == _math(ink: [_stroke('b')]), isFalse);
      expect(() => a.ink.add(_stroke('c')), throwsUnsupportedError);
    });

    test('estimatedBytes adds the ink strokes', () {
      final s = _stroke('a', n: 10);
      expect(_math().estimatedBytes, 160 + 2);
      expect(_math(ink: [s, s]).estimatedBytes, 160 + 2 + 2 * s.estimatedBytes);
    });
  });

  group('limits (checkObjectLimits)', () {
    test('400 strokes / 40,000 points pass; one more fails', () {
      final many = [
        for (var i = 0; i < PageObjectLimits.maxMathInkStrokes; i++)
          _stroke('s$i', n: 2),
      ];
      checkObjectLimits(_math(ink: many));
      expect(
        () => checkObjectLimits(_math(ink: [...many, _stroke('x', n: 2)])),
        throwsArgumentError,
      );
      final big = _stroke('b', n: PageObjectLimits.maxMathInkPoints ~/ 2);
      checkObjectLimits(_math(ink: [big, big]));
      expect(
        () => checkObjectLimits(_math(ink: [big, big, _stroke('c', n: 1)])),
        throwsArgumentError,
      );
    });
  });

  group('changed fields', () {
    test('a LaTeX edit changes latex only; an ink change is the ink key', () {
      final a = _math(ink: [_stroke('a')]);
      expect(changedObjectKeys(a, a.copyWith(latex: 'y')), {'latex'});
      expect(changedObjectKeys(a, a.copyWith(ink: const [])), {'ink'});
      expect(changedObjectKeys(a, a.transformed(Affine2.translation(1, 0))), {
        'frame',
        'ink',
      });
    });
  });
}
