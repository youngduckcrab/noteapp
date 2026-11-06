// groupIntoLines — m5-7/05-library 4.4.6, 6.5, 8.2 L2-05 (V9).
//  - the shared cases (shared/line_cases.dart — also on dart2js, L2-20): V9
//    over SyntheticHandwriting seeds 1–20 × 3–12 lines, lineAccuracy, small
//    hand-made lines, input order;
//  - the output rules of 4.4.6 (empty input, strokes without points);
//  - the hand-made edge cases in test/fixtures/lines/*.json (not part of the
//    V9 average): each file gives the strokes, the expected lines and how
//    far the result may be off (maxLineDiff, minAccuracy — 6.5 limits);
//  - 1,000 strokes timed (recorded, not asserted — 6.24 target ≤ 10 ms).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../shared/line_cases.dart';

final Directory _fixtures = Directory('test/fixtures/lines');

/// One edge case file (6.5 '경계 사례').
final class _LineCase {
  _LineCase(Map<String, Object?> json)
    : name = json['name']! as String,
      description = json['description']! as String,
      gapFactor = (json['gapFactor']! as num).toDouble(),
      maxLineDiff = json['maxLineDiff']! as int,
      minAccuracy = (json['minAccuracy']! as num).toDouble(),
      lines = [
        for (final line in json['lines']! as List<Object?>)
          [for (final id in line! as List<Object?>) id! as String],
      ],
      traces = [
        for (final s in json['strokes']! as List<Object?>)
          _trace(s! as Map<String, Object?>),
      ];

  final String name, description;
  final double gapFactor, minAccuracy;
  final int maxLineDiff;
  final List<List<String>> lines;
  final List<HandwritingTrace> traces;

  static HandwritingTrace _trace(Map<String, Object?> s) {
    List<double> numbers(String key) => [
      for (final v in s[key]! as List<Object?>) (v! as num).toDouble(),
    ];
    return HandwritingTrace(
      xs: Float32List.fromList(numbers('x')),
      ys: Float32List.fromList(numbers('y')),
      ts: Float64List.fromList(numbers('t')),
      strokeId: s['id']! as String,
    );
  }
}

List<_LineCase> _loadCases() {
  final files =
      _fixtures
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      _LineCase(jsonDecode(f.readAsStringSync()) as Map<String, Object?>),
  ];
}

core.Stroke _fakeStroke(String id) => core.Stroke(
  id: id,
  pageId: 'p1',
  style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
  points: core.StrokePoints.fromList(const [core.StrokePoint(0, 0)]),
  createdAt: 0,
);

void main() {
  defineLineCaseTests();

  group('output rules (4.4.6)', () {
    test('empty input → empty list; strokes without points are dropped', () {
      expect(groupIntoLines(const []), isEmpty);
      final empty = HandwritingTrace(
        xs: Float32List(0),
        ys: Float32List(0),
        ts: Float64List(0),
        strokeId: 'empty',
      );
      expect(groupIntoLines([empty]), isEmpty);
      final lines = groupIntoLines([empty, ...glyph('a', 40, 40, 20)]);
      expect(idsOf(lines), [
        ['aa', 'ab'],
      ]);
    });
  });

  group('edge cases (test/fixtures/lines)', () {
    final cases = _loadCases();

    test('the fixture folder holds the 6.5 cases', () {
      expect(
        [for (final c in cases) c.name],
        [
          'close_lines',
          'descender_near_next_line',
          'descender_touches_next_line',
          'dots_only',
          'empty',
          'late_marks',
          'opposite_slant',
          'separated_jamo',
          'single_stroke',
          'slant_4deg',
          'two_columns',
        ],
      );
    });

    for (final c in cases) {
      test('${c.name}: ${c.description}', () {
        final output = groupIntoLines(c.traces, gapFactor: c.gapFactor);
        final ids = idsOf(output);
        final lineOf = {
          for (final (i, line) in c.lines.indexed)
            for (final id in line) id: i,
        };
        expect(
          lineOf.length,
          c.traces.length,
          reason: 'fixture: every stroke has a line',
        );
        if (c.maxLineDiff == 0 && c.minAccuracy == 1) {
          expect(ids, c.lines);
          return;
        }
        expect(
          (output.length - c.lines.length).abs(),
          lessThanOrEqualTo(c.maxLineDiff),
          reason: '$ids',
        );
        final page = [for (final t in c.traces) _fakeStroke(t.strokeId!)];
        final (:correct, :total) = lineAccuracy(
          page,
          output,
          trueLine: (id) => lineOf[id]!,
        );
        expect(
          correct / total,
          greaterThanOrEqualTo(c.minAccuracy),
          reason: '$ids',
        );
        // Every stroke is in exactly one line, each line by time.
        expect(
          [for (final l in ids) ...l]..sort(),
          [for (final t in c.traces) t.strokeId]..sort(),
        );
      });
    }
  });

  test('separated_jamo needs gapFactor 1.5: the default 1.2 splits it at '
      'the word gaps (why callers may pass 1.5 — 6.5)', () {
    final jamo = _loadCases().singleWhere((c) => c.name == 'separated_jamo');
    expect(groupIntoLines(jamo.traces), hasLength(3));
    expect(groupIntoLines(jamo.traces, gapFactor: 1.5), hasLength(1));
  });

  test('1,000 strokes: time recorded (6.24 target ≤ 10 ms)', () {
    final traces = [
      for (final seed in [3, 4, 5, 6, 7, 8])
        for (final s in SyntheticHandwriting.lines(
          pageId: 'p1',
          lineCount: 30,
          seed: seed,
        ))
          HandwritingTrace.fromStroke(s),
    ].take(1000).toList();
    expect(traces, hasLength(1000));
    final times = <int>[];
    for (var i = 0; i < 15; i++) {
      final watch = Stopwatch()..start();
      groupIntoLines(traces);
      watch.stop();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    // ignore: avoid_print — the 6.24 record
    print(
      'groupIntoLines 1,000 strokes: median ${times[7]} µs, '
      'min ${times.first} µs, max ${times.last} µs',
    );
  });
}
