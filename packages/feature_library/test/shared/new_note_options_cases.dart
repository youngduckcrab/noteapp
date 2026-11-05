// test/shared/new_note_options_cases.dart — 05-library 8 L3 (LIBRARY-2-8,
// contract 7.4.6 / 7.4.8). NewNoteOptions.fromJson with web-format input:
// called from unit/new_note_options_test.dart (VM) AND
// web/new_note_options_browser_test.dart (Chrome, dart2js).
import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

/// Registers the shared decode tests inside the caller's main().
void defineNewNoteOptionsDecodeTests() {
  group('NewNoteOptions.fromJson web-format input', () {
    test('integer customW / customH become 210.0 / 297.0', () {
      final o = NewNoteOptions.fromJson(const {
        'size': 'custom',
        'customW': 210,
        'customH': 297,
      });
      expect(o.preset, isNull);
      expect(o.customWidthMm, isA<double>());
      expect(o.customWidthMm, 210.0);
      expect(o.customHeightMm, 297.0);
      expect(o.pageSize.width, closeTo(595.28, 0.01));
      expect(o.pageSize.height, closeTo(841.89, 0.01));
    });

    test('custom sizes outside the input range are clamped', () {
      final small = NewNoteOptions.fromJson(const {
        'size': 'custom',
        'customW': 10,
        'customH': 5000,
      });
      expect(small.customWidthMm, 35.3);
      expect(small.customHeightMm, 1058.3);
      expect(
        small.pageSize.width,
        greaterThanOrEqualTo(PageSizeLimits.userMinSidePt),
      );
      expect(
        small.pageSize.height,
        lessThanOrEqualTo(PageSizeLimits.userMaxSidePt),
      );
      final fractional = NewNoteOptions.fromJson(const {
        'size': 'custom',
        'customW': 35.0,
        'customH': 1100.5,
      });
      expect(fractional.customWidthMm, 35.3);
      expect(fractional.customHeightMm, 1058.3);
    });

    test('an integer paper color is kept', () {
      for (final argb in PaperColors.all) {
        expect(NewNoteOptions.fromJson({'paper': argb}).paperColorArgb, argb);
      }
      expect(
        NewNoteOptions.fromJson(const {'paper': 4294967295}).paperColorArgb,
        PaperColors.white,
      );
      expect(
        NewNoteOptions.fromJson(const {'paper': 4280295716}).paperColorArgb,
        PaperColors.black,
      );
    });

    test('a string where a number belongs gives the default', () {
      final o = NewNoteOptions.fromJson(const {
        'size': 'custom',
        'customW': '210',
        'customH': 'x',
        'paper': '4294967295',
      });
      expect(o.customWidthMm, 210.0);
      expect(o.customHeightMm, 297.0);
      expect(o.paperColorArgb, PaperColors.white);
    });

    test('a paper color outside PaperColors.all gives white', () {
      expect(
        NewNoteOptions.fromJson(const {'paper': 0xFF123456}).paperColorArgb,
        PaperColors.white,
      );
      expect(
        NewNoteOptions.fromJson(const {'paper': 1.5}).paperColorArgb,
        PaperColors.white,
      );
    });
  });
}
