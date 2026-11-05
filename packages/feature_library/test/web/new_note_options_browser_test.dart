// NewNoteOptions.fromJson on dart2js (05-library 8 L3, LIBRARY-2-8; contract
// 7.4.6 / 7.4.8): the shared web-format decode cases, plus the round trip
// through jsonEncode, where jsonEncode(210.0) writes '210'.
@TestOn('browser')
library;

import 'dart:convert';

import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../shared/new_note_options_cases.dart';

void main() {
  defineNewNoteOptionsDecodeTests();

  test('jsonDecode(jsonEncode(toJson())) round trip on the web', () {
    const samples = [
      NewNoteOptions(),
      NewNoteOptions(
        preset: null,
        customWidthMm: 210,
        customHeightMm: 297,
        template: null,
        paperColorArgb: PaperColors.gray,
      ),
      NewNoteOptions(
        preset: PageSizePreset.widescreen16x9,
        orientation: PageOrientationChoice.landscape,
        template: PageTemplateKind.cornell,
        paperColorArgb: PaperColors.black,
      ),
    ];
    for (final o in samples) {
      final text = jsonEncode(o.toJson());
      final decoded = jsonDecode(text) as Map<String, Object?>;
      expect(NewNoteOptions.fromJson(decoded), o, reason: text);
    }
    // The web writes whole doubles as integers.
    expect(
      jsonEncode(const NewNoteOptions().toJson()),
      contains('"customW":210'),
    );
  });
}
