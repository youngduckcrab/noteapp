// The math fixture line (m5-7/05-library 8.2 L2-22, 6.14.7; the format of
// m5-7/07-sync 6.9.1 — functions/tool/fixtures/math/*.json): one line of
// JSON whose keys are 6.9.1's without `png`, in its order; strokes with the
// callable request's rules (6.11.3, CP-L8 — 1 decimal, t integer ms from the
// first point of the first stroke = mathStrokesOf); expected as given; id
// 'user-<yyyyMMdd-HHmmss>', tags [], source 'user-<platform>-<yyyy-MM-dd>';
// deterministic (the same input, the same string).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/math/math_fixture_export.dart';
import 'package:ink_recognition/src/math/math_payload.dart';

/// A trace through [points] (x, y, epoch ms).
HandwritingTrace _trace(List<(double, double, double)> points) =>
    HandwritingTrace(
      xs: Float32List.fromList([for (final p in points) p.$1]),
      ys: Float32List.fromList([for (final p in points) p.$2]),
      ts: Float64List.fromList([for (final p in points) p.$3]),
    );

const double _t0 = 1730800000000; // 13-digit epoch ms

final DateTime _now = DateTime(2026, 11, 6, 10, 4, 5);

Map<String, Object?> _decode(String line) =>
    jsonDecode(line) as Map<String, Object?>;

List<List<num>> _lists(Map<String, Object?> json, String axis) => [
  for (final l in (json['strokes']! as Map<String, Object?>)[axis]! as List)
    [for (final v in l as List) v as num],
];

void main() {
  final frac = [
    _trace([(312.44, 88.0, _t0), (313.06, 88.61, _t0 + 8.4)]),
  ];

  test('the 6.9.1 example: one line, its keys in its order without png', () {
    final line = buildMathFixtureJson(
      frac,
      r'\frac{a+b}{c}',
      now: _now,
      platform: 'android',
    );
    expect(
      line,
      r'{"id":"user-20261106-100405","tags":[],"expected":"\\frac{a+b}{c}",'
      r'"strokes":{"x":[[312.4,313.1]],"y":[[88.0,88.6]],"t":[[0,8]]},'
      r'"source":"user-android-2026-11-06"}',
    );
    expect(line, isNot(contains('\n')));
    final json = _decode(line);
    // 07-sync 6.9.1: {id, tags, expected, strokes, png?, source} — no png
    expect(json.keys.toList(), ['id', 'tags', 'expected', 'strokes', 'source']);
    expect((json['strokes']! as Map).keys.toList(), ['x', 'y', 't']);
    expect(json['tags'], isEmpty);
  });

  test('page pt with 1 decimal; t integer ms from the first point of the '
      'first stroke (CP-L8); empty traces left out', () {
    final random = math.Random(3);
    double r() => 100 + random.nextDouble() * 400;
    final traces = [
      _trace([for (var i = 0; i < 20; i++) (r(), r(), _t0 + 500 + i * 7.6)]),
      _trace(const []),
      _trace([for (var i = 0; i < 15; i++) (r(), r(), _t0 + 2400 + i * 8.3)]),
    ];
    final json = _decode(
      buildMathFixtureJson(traces, 'x', now: _now, platform: 'web'),
    );
    final xs = _lists(json, 'x');
    final ys = _lists(json, 'y');
    final ts = _lists(json, 't');
    expect([for (final l in xs) l.length], [20, 15]); // the empty one went
    expect([for (final l in ys) l.length], [20, 15]);
    expect([for (final l in ts) l.length], [20, 15]);
    for (final v in [...xs.expand((l) => l), ...ys.expand((l) => l)]) {
      expect((v * 10 - (v * 10).round()).abs(), lessThan(1e-6), reason: '$v');
    }
    for (final v in ts.expand((l) => l)) {
      expect(v, isA<int>());
    }
    expect(ts.first.first, 0);
    expect(ts.first[1], 8); // 7.6 → 8
    expect(ts.last.first, 1900); // 2400 − 500
    expect(xs.first.first, closeTo(traces.first.xs.first, 0.05));
    expect(ys.last.last, closeTo(traces.last.ys.last, 0.05));
  });

  test('the strokes are the callable request\'s (mathStrokesOf — the same '
      'body the engines get, 6.11.3)', () {
    final traces = [
      _trace([
        (10.04, 20.05, _t0),
        (11.0, 21.0, _t0 + 8),
        (12.0, 23.0, _t0 + 16),
      ]),
      _trace([(40.0, 20.0, _t0 + 300), (44.4, 26.66, _t0 + 308)]),
    ];
    final json = _decode(
      buildMathFixtureJson(traces, 'x', now: _now, platform: 'ios'),
    );
    final data = buildMathData(
      MathInput(traces: traces),
      engine: 'auto',
      locale: 'ko',
    );
    expect(json['strokes'], jsonDecode(jsonEncode(data['strokes'])));
    expect(json['strokes'], jsonDecode(jsonEncode(mathStrokesOf(traces))));
  });

  test('expected as given (backslashes, braces, Korean, spaces)', () {
    for (final latex in [
      r'\int_0^1 x^2\,dx = \frac{1}{3}',
      r'\text{넓이} = \pi r^2',
      r'  a_{i}  ',
      r'"quoted"',
    ]) {
      final json = _decode(
        buildMathFixtureJson(frac, latex, now: _now, platform: 'web'),
      );
      expect(json['expected'], latex);
    }
  });

  test('id user-<yyyyMMdd-HHmmss> and source user-<platform>-<yyyy-MM-dd> '
      'from now\'s fields (zero padded)', () {
    final early = DateTime(2027, 1, 2, 3, 4, 5);
    final json = _decode(
      buildMathFixtureJson(frac, 'x', now: early, platform: 'ios'),
    );
    expect(json['id'], 'user-20270102-030405');
    expect(json['source'], 'user-ios-2027-01-02');
    expect(
      mathFixtureId(DateTime(2026, 12, 31, 23, 59, 59)),
      'user-20261231-235959',
    );
    // the fields as given — a UTC time is not moved to local
    expect(
      mathFixtureId(DateTime.utc(2026, 11, 6, 10)),
      'user-20261106-100000',
    );
    for (final platform in ['android', 'ios', 'web']) {
      expect(
        _decode(
          buildMathFixtureJson(frac, 'x', now: _now, platform: platform),
        )['source'],
        'user-$platform-2026-11-06',
      );
    }
  });

  test('deterministic: the same input gives the same string', () {
    final traces = [
      _trace([
        for (var i = 0; i < 50; i++) (i * 1.37, i * 0.73, _t0 + i * 8.0),
      ]),
    ];
    final a = buildMathFixtureJson(
      traces,
      r'\sqrt{2}',
      now: _now,
      platform: 'android',
    );
    final b = buildMathFixtureJson(
      [
        for (final t in traces)
          HandwritingTrace(
            xs: Float32List.fromList(t.xs),
            ys: Float32List.fromList(t.ys),
            ts: Float64List.fromList(t.ts),
          ),
      ],
      r'\sqrt{2}',
      now: DateTime(2026, 11, 6, 10, 4, 5),
      platform: 'android',
    );
    expect(a, b);
  });

  test('no point at all → empty lists (the keys stay)', () {
    final json = _decode(
      buildMathFixtureJson([_trace(const [])], 'x', now: _now, platform: 'web'),
    );
    expect(json['strokes'], {
      'x': <Object?>[],
      'y': <Object?>[],
      't': <Object?>[],
    });
    expect(json.keys.toList(), ['id', 'tags', 'expected', 'strokes', 'source']);
  });

  test('too large even thinned → the request\'s RecognizerEngineError '
      '(too-large)', () {
    final random = math.Random(7);
    final traces = [
      for (var s = 0; s < 600; s++)
        _trace([
          for (var i = 0; i < 120; i++)
            (
              10 + i * 2.0,
              50 + s * 0.5 + (i.isEven ? 10 : -10) + random.nextDouble() * 0.01,
              _t0 + s * 1000 + i * 8,
            ),
        ]),
    ];
    expect(
      () => buildMathFixtureJson(traces, 'x', now: _now, platform: 'web'),
      throwsA(
        isA<RecognizerEngineError>().having((e) => e.code, 'code', 'too-large'),
      ),
    );
  });

  test(
    'mathFixturePlatform: android · ios · the lower-case name elsewhere',
    () {
      expect(mathFixturePlatform(), 'android'); // flutter_test's default
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(mathFixturePlatform(), 'ios');
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        expect(mathFixturePlatform(), 'macos');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
