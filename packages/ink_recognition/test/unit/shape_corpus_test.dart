// m5-7/05-library 6.17.5: the hand-drawn corpus (shared/hand_drawn_corpus.dart,
// seeds 1–3, 40 strokes per variant) through GeometricShapeFitter at
// viewScale 1 — the confusion matrix (per class and per variant) in the test
// log, a recall floor per class and per variant (handwriting and scribbles
// must stay ink). A commit that changes ShapeFitTuning defaults runs this
// file with the V9 cases (LIBRARY-F2).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';

import '../shared/hand_drawn_corpus.dart';
import '../shared/shape_cases.dart' show verdictOf;

const List<String> _verdicts = [
  'line',
  'circle',
  'ellipse',
  'triangle',
  'rectangle',
  'polygon',
  'none',
];

/// The least share judged right per class.
/// Measured on seeds 1–3 (6.17.5): line / circle / quad / negative 100 %,
/// ellipse 99.8 %, triangle 99.6 %, polygon 99.6 %, rectangle 98.8 % (before
/// the 6.17.5 changes: triangle 67.0 %, ellipse 65.2 %, circle 66.7 %,
/// handwriting and scribbles kept 96.4 %).
const Map<CorpusClass, double> kCorpusMinRecall = {
  CorpusClass.line: 0.98,
  CorpusClass.circle: 0.97,
  CorpusClass.ellipse: 0.96,
  CorpusClass.triangle: 0.96,
  CorpusClass.rectangle: 0.95,
  CorpusClass.quad: 0.92,
  CorpusClass.polygon: 0.92,
  CorpusClass.negative: 0.995,
};

/// The least share judged right for every single variant (a regression
/// hidden in one way of drawing).
const double kCorpusMinVariantRecall = 0.9;

/// (class or variant) → verdict → count.
typedef Matrix = Map<String, Map<String, int>>;

String _table(Matrix m) {
  final rows = m.keys.toList();
  final w = rows.fold(8, (a, r) => r.length > a ? r.length : a);
  final b = StringBuffer()
    ..writeln(
      '${''.padRight(w)} ${[for (final v in _verdicts) v.padLeft(9)].join()}'
      '   recall',
    );
  for (final r in rows) {
    final row = m[r]!;
    final total = row.values.fold(0, (a, c) => a + c);
    b.write(r.padRight(w));
    b.write(' ');
    for (final v in _verdicts) {
      b.write('${row[v] ?? 0}'.padLeft(9));
    }
    final expected = r.contains('/')
        ? kCorpusExpected[CorpusClass.values.byName(r.split('/').first)]!
        : kCorpusExpected[CorpusClass.values.byName(r)]!;
    final recall = (row[expected] ?? 0) / total;
    b.writeln('   ${(100 * recall).toStringAsFixed(1)} %');
  }
  return b.toString();
}

double _recall(Map<String, int> row, String expected) =>
    (row[expected] ?? 0) / row.values.fold(0, (a, b) => a + b);

void main() {
  test('hand-drawn corpus: recall per class (6.17.5)', () {
    const fitter = GeometricShapeFitter();
    final byClass = <String, Map<String, int>>{};
    final byVariant = <String, Map<String, int>>{};
    for (final seed in [1, 2, 3]) {
      for (final s in HandDrawnCorpus(seed).build()) {
        final v = verdictOf(fitter.fit(s.points, viewScale: 1));
        (byClass[s.truth.name] ??= {}).update(
          v,
          (c) => c + 1,
          ifAbsent: () => 1,
        );
        (byVariant[s.variant] ??= {}).update(
          v,
          (c) => c + 1,
          ifAbsent: () => 1,
        );
      }
    }
    // ignore: avoid_print
    print('${_table(byClass)}\n${_table(byVariant)}');
    for (final c in CorpusClass.values) {
      final row = byClass[c.name]!;
      expect(
        _recall(row, kCorpusExpected[c]!),
        greaterThanOrEqualTo(kCorpusMinRecall[c]!),
        reason: '${c.name} $row',
      );
    }
    for (final MapEntry(key: v, value: row) in byVariant.entries) {
      final c = CorpusClass.values.byName(v.split('/').first);
      expect(
        _recall(row, kCorpusExpected[c]!),
        greaterThanOrEqualTo(kCorpusMinVariantRecall),
        reason: '$v $row',
      );
    }
  });
}
