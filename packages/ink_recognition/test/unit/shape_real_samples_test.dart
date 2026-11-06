// L2-06 (m5-7/05-library 6.17.3, 12.2 Q7): real-device shape samples. EDITOR's
// developer toggle '도형 표본 모으기' copies `{kind, points: [[x, y], …],
// viewScale}` (kind = the expected ShapeKind.name or 'none'); the user saves
// them as test/fixtures/real/<device>-<date>-<n>.json. Every sample must be
// judged as its kind — a commit that changes the ShapeFitTuning defaults
// runs this file with the synthetic V9 cases (LIBRARY-F2). No folder or no
// sample yet → skipped (reads files: VM only).
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';

final Directory _folder = Directory('test/fixtures/real');

List<File> _samples() => _folder.existsSync()
    ? (_folder
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
    : const [];

void main() {
  final samples = _samples();

  test(
    'every real sample is judged as its kind',
    () {
      const fitter = GeometricShapeFitter();
      for (final file in samples) {
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        final kind = json['kind']! as String;
        final points = [
          for (final p in json['points']! as List<Object?>)
            if (p case [final num x, final num y])
              Offset(x.toDouble(), y.toDouble()),
        ];
        final viewScale = (json['viewScale'] as num?)?.toDouble() ?? 1;
        final fit = fitter.fit(points, viewScale: viewScale);
        expect(fit?.kind.name ?? 'none', kind, reason: file.path);
      }
    },
    skip: samples.isEmpty ? 'no real samples in test/fixtures/real yet' : false,
  );
}
