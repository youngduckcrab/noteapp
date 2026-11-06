// The callable request body (m5-7/05-library 8.2 L2-16, 6.11.3; contract
// 7.2.13 v2.1 CP-L8): {"data": {v: 1, engine, locale, strokes?, pngBase64?}};
// x, y with 1 decimal, t integer ms from the first sample of the first
// stroke; no strokes key without points; the strokes JSON within 512 KB
// (Ramer–Douglas–Peucker 0.25 → 2 pt), still above → 'too-large'; a PNG
// whose base64 is over 2 MB is left out (E10); always v: 1 (E4); 200 strokes
// × 100 points — time recorded (6.24 target ≤ 20 ms).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/math/math_payload.dart';

/// A trace through [points] (x, y, epoch ms).
HandwritingTrace _trace(List<(double, double, double)> points) =>
    HandwritingTrace(
      xs: Float32List.fromList([for (final p in points) p.$1]),
      ys: Float32List.fromList([for (final p in points) p.$2]),
      ts: Float64List.fromList([for (final p in points) p.$3]),
    );

const double _t0 = 1730800000000; // 13-digit epoch ms

Map<String, Object?> _data(MathInput input) =>
    buildMathData(input, engine: 'auto', locale: 'ko');

/// [count] strokes of [points] points each: a straight line with noise of
/// [noise] pt (or a zigzag of ±[zigzag] pt).
List<HandwritingTrace> _many(
  int count,
  int points, {
  double noise = 0,
  double zigzag = 0,
}) {
  final random = math.Random(7);
  return [
    for (var s = 0; s < count; s++)
      _trace([
        for (var i = 0; i < points; i++)
          (
            100.0 + i * 3 + s * 0.01,
            200.0 +
                s * 2 +
                (zigzag > 0 ? (i.isEven ? zigzag : -zigzag) : 0) +
                (random.nextDouble() - 0.5) * 2 * noise,
            _t0 + s * 1000 + i * 8,
          ),
      ]),
  ];
}

void main() {
  test('the data object: v 1, engine, locale, strokes with 1 decimal and t '
      'from the first sample of the first stroke', () {
    final input = MathInput(
      traces: [
        _trace([(312.44, 88.0, _t0 + 5), (313.16, 88.64, _t0 + 13)]),
        _trace([(320.07, 90.0, _t0 + 400.6)]),
      ],
    );
    final data = _data(input);
    expect(data['v'], 1);
    expect(data['engine'], 'auto');
    expect(data['locale'], 'ko');
    expect(data.containsKey('pngBase64'), isFalse);
    final strokes = data['strokes']! as Map<String, List<List<num>>>;
    expect(strokes['x'], [
      [312.4, 313.2],
      [320.1],
    ]);
    expect(strokes['y'], [
      [88.0, 88.6],
      [90.0],
    ]);
    expect(strokes['t'], [
      [0, 8],
      [396],
    ]);
    for (final list in strokes['t']!) {
      for (final t in list) {
        expect(t, isA<int>());
      }
    }

    final json = jsonDecode(
      encodeMathRequest(input, engine: 'fake', locale: 'en'),
    ) as Map<String, Object?>;
    expect(json.keys, ['data']);
    final sent = json['data']! as Map<String, Object?>;
    expect(sent['v'], 1);
    expect(sent['engine'], 'fake');
    expect(sent['locale'], 'en');
    expect((sent['strokes']! as Map)['t'], [
      [0, 8],
      [396],
    ]);
    // The body is the data object as JSON (the strokes JSON is reused).
    expect(
      encodeMathRequest(input, engine: 'fake', locale: 'en'),
      jsonEncode({'data': buildMathData(input, engine: 'fake', locale: 'en')}),
    );
  });

  test('no points → no strokes key (PNG only); traces without points are '
      'left out', () {
    expect(_data(const MathInput(traces: [])).containsKey('strokes'), isFalse);
    expect(
      _data(MathInput(traces: [_trace(const [])])).containsKey('strokes'),
      isFalse,
    );
    final png = Uint8List.fromList(List.filled(67, 1));
    final data = _data(MathInput(traces: const [], png: png));
    expect(data.containsKey('strokes'), isFalse);
    expect(data['pngBase64'], base64Encode(png));

    final mixed = _data(
      MathInput(
        traces: [
          _trace(const []),
          _trace([(1, 2, _t0 + 50)]),
        ],
      ),
    );
    expect((mixed['strokes']! as Map)['t'], [
      [0],
    ]);
  });

  test('always v: 1 (E4) — nothing else of the note goes in (G-3)', () {
    final data = _data(
      MathInput(
        traces: [
          _trace([(1, 1, _t0)]),
        ],
        png: Uint8List(3),
        pngPxPerPt: 2,
      ),
    );
    expect(data.keys.toSet(), {
      'v',
      'engine',
      'locale',
      'strokes',
      'pngBase64',
    });
    expect(data['v'], 1);
  });

  test('a PNG whose base64 is over 2 MB is left out (E10)', () {
    // 1,572,864 bytes → exactly 2,097,152 base64 characters.
    final atLimit = Uint8List(1572864);
    expect(base64Encode(atLimit).length, kMathPngBase64MaxChars);
    expect(
      _data(MathInput(traces: const [], png: atLimit)).containsKey('pngBase64'),
      isTrue,
    );
    final over = Uint8List(1572864 + 1);
    expect(
      _data(MathInput(traces: const [], png: over)).containsKey('pngBase64'),
      isFalse,
    );
  });

  test('over 512 KB → thinned (RDP) to within the limit; ends and times '
      'stay with their points', () {
    final traces = _many(300, 200, noise: 0.1);
    final raw = jsonEncode({
      'x': [
        for (final t in traces) [for (final x in t.xs) x],
      ],
    });
    expect(raw.length, greaterThan(kMathStrokesMaxBytes)); // x alone is over
    final strokes = mathStrokesOf(traces)!;
    final size = jsonEncode(strokes).length;
    expect(size, lessThanOrEqualTo(kMathStrokesMaxBytes));
    expect(strokes['x'], hasLength(300));
    for (var s = 0; s < 300; s++) {
      final xs = strokes['x']![s];
      final ts = strokes['t']![s];
      expect(xs.length, lessThan(200));
      expect(xs.length, ts.length);
      expect(xs.first, closeTo(traces[s].xs.first, 0.05));
      expect(xs.last, closeTo(traces[s].xs.last, 0.05));
      expect(ts.first, s * 1000);
      expect(ts.last, s * 1000 + 199 * 8);
    }
  });

  test('still over 512 KB after 2 pt → RecognizerEngineError(too-large)', () {
    final traces = _many(600, 120, zigzag: 10);
    expect(
      () => mathStrokesOf(traces),
      throwsA(
        isA<RecognizerEngineError>().having((e) => e.code, 'code', 'too-large'),
      ),
    );
  });

  test(
    'rdpKeep: a straight line keeps its ends, a corner stays, ε decides',
    () {
      final line = rdpKeep([0, 1, 2, 3, 4], [0, 0.1, -0.1, 0.05, 0], 0.25);
      expect(line, [true, false, false, false, true]);
      final corner = rdpKeep([0, 5, 10], [0, 5, 0], 0.25);
      expect(corner, [true, true, true]);
      expect(rdpKeep([0, 1, 2], [0, 0.4, 0], 0.5), [true, false, true]);
      expect(rdpKeep([0, 1, 2], [0, 0.6, 0], 0.5), [true, true, true]);
      expect(rdpKeep(const [], const [], 1), isEmpty);
      expect(rdpKeep([3], [3], 1), [true]);
    },
  );

  test('200 strokes × 100 points: time recorded (6.24 target ≤ 20 ms)', () {
    final input = MathInput(traces: _many(200, 100, noise: 0.5));
    final times = <int>[];
    for (var i = 0; i < 9; i++) {
      final watch = Stopwatch()..start();
      encodeMathRequest(input, engine: 'auto', locale: 'ko');
      watch.stop();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    // ignore: avoid_print — the 6.24 record
    print(
      'math body 200 strokes × 100 points: median ${times[4]} µs, '
      'min ${times.first} µs, max ${times.last} µs',
    );
  });
}
