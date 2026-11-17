// JSON golden files (CORE 6.3): byte comparison of JsonEncoder.withIndent('  ') output.
// VM only — the web prints 1.0 as 1 (7.4.6). Regenerate with
// UPDATE_JSON_GOLDENS=1 flutter test test/goldens (separate commit, 7.4.8).
@Tags(['golden'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

void main() {
  final update = Platform.environment['UPDATE_JSON_GOLDENS'] == '1';
  const encoder = JsonEncoder.withIndent('  ');

  final docs = <String, Object?>{
    for (final e in kSampleEntities.entries) e.key: e.value.toJson(),
    'field_versions': kSampleFieldVersions.toJson(),
  };

  // (v2.0, m5-7/02-core 6.3) 11 v1.4 files + 9 new (8 page objects, handwriting);
  // (math pen) + math_ink; (v2.17-md) + markdown.
  test('22 golden files', () {
    expect(docs.length, 22);
  });

  for (final e in docs.entries) {
    test('${e.key}.json', () {
      final file = File('test/goldens/json/${e.key}.json');
      final text = '${encoder.convert(e.value)}\n';
      if (update) file.writeAsStringSync(text);
      expect(file.readAsStringSync(), text);
      if (e.key != 'field_versions') {
        final kind = kSampleEntities[e.key]!.kind;
        final decoded = EntityJson.decode(
          kind,
          jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
        );
        expect(encoder.convert(decoded.toJson()), encoder.convert(e.value));
      }
    });
  }
}
