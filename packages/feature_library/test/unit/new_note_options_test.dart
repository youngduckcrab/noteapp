// NewNoteOptions / NewNoteSpec (05-library 6.12, 8 L3). Page sizes and paper
// colors are CORE's (contract 7.2.5).
import 'dart:convert';

import 'package:feature_library/src/model/new_note_spec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../shared/new_note_options_cases.dart';

void _expectSize(PageSize size, double w, double h, {double tol = 1e-9}) {
  expect(size.width, closeTo(w, tol));
  expect(size.height, closeTo(h, tol));
}

void main() {
  const portrait = PageOrientationChoice.portrait;
  const landscape = PageOrientationChoice.landscape;

  group('pageSize', () {
    test('A4 portrait / landscape', () {
      _expectSize(const NewNoteOptions().pageSize, 595.2756, 841.8898);
      _expectSize(
        const NewNoteOptions(orientation: landscape).pageSize,
        841.8898,
        595.2756,
      );
    });

    test('Letter portrait / landscape', () {
      const letter = NewNoteOptions(preset: PageSizePreset.letter);
      _expectSize(letter.pageSize, 612, 792);
      _expectSize(letter.copyWith(orientation: landscape).pageSize, 792, 612);
    });

    test('16:9 portrait / landscape', () {
      const wide = NewNoteOptions(
        preset: PageSizePreset.widescreen16x9,
        orientation: portrait,
      );
      _expectSize(wide.pageSize, 540, 960);
      _expectSize(wide.copyWith(orientation: landscape).pageSize, 960, 540);
    });

    test(
      'PageSizePreset.match round trip for every preset and orientation',
      () {
        for (final preset in PageSizePreset.values) {
          for (final o in PageOrientationChoice.values) {
            final options = NewNoteOptions(preset: preset, orientation: o);
            expect(PageSizePreset.match(options.pageSize), preset);
            expect(
              options.pageSize.isLandscape,
              o == landscape,
              reason: '$preset $o',
            );
          }
        }
      },
    );

    test('custom 210 x 297 mm → 595.28 x 841.89 pt, orientation ignored', () {
      const custom = NewNoteOptions(
        preset: null,
        customWidthMm: 210,
        customHeightMm: 297,
        orientation: landscape,
      );
      expect(custom.isCustom, isTrue);
      _expectSize(custom.pageSize, 595.28, 841.89, tol: 0.01);
    });
  });

  group('background', () {
    test('a template with the paper color, parameters from INK defaults', () {
      const o = NewNoteOptions(
        template: PageTemplateKind.grid,
        paperColorArgb: PaperColors.ivory,
      );
      expect(
        o.background,
        TemplateBackground(
          template: PageTemplate.defaults(PageTemplateKind.grid),
          paperColorArgb: PaperColors.ivory,
        ),
      );
    });

    test('no template → blank page with the paper color', () {
      const o = NewNoteOptions(
        template: null,
        paperColorArgb: PaperColors.black,
      );
      expect(
        o.background,
        const BlankBackground(paperColorArgb: PaperColors.black),
      );
    });

    test('NewNoteSpec.toPageDraft uses size and background', () {
      const spec = NewNoteSpec(
        title: '수학',
        options: NewNoteOptions(preset: PageSizePreset.letter),
        cover: ColorCover(0xFF2F4A7A),
      );
      final draft = spec.toPageDraft();
      expect(draft.size, PageSize.letterPortrait);
      expect(draft.background, spec.options.background);
      expect(draft.strokes, isEmpty);
    });
  });

  group('copyWith', () {
    test('custom: true clears the preset, clearTemplate the template', () {
      final o = const NewNoteOptions().copyWith(
        custom: true,
        clearTemplate: true,
      );
      expect(o.preset, isNull);
      expect(o.template, isNull);
      expect(
        o.copyWith(preset: PageSizePreset.letter).preset,
        PageSizePreset.letter,
      );
      expect(
        o.copyWith(template: PageTemplateKind.music).template,
        PageTemplateKind.music,
      );
    });

    test('fields not given are kept', () {
      const o = NewNoteOptions(
        preset: PageSizePreset.letter,
        template: PageTemplateKind.dotted,
        paperColorArgb: PaperColors.gray,
      );
      expect(o.copyWith(), o);
      expect(o.copyWith(customWidthMm: 100).customWidthMm, 100);
      expect(o.copyWith(customWidthMm: 100).template, PageTemplateKind.dotted);
    });
  });

  group('JSON', () {
    test('toJson format (6.12)', () {
      expect(const NewNoteOptions().toJson(), {
        'size': 'a4',
        'orientation': 'portrait',
        'customW': 210.0,
        'customH': 297.0,
        'template': 'lined',
        'paper': 4294967295,
      });
      expect(
        const NewNoteOptions(preset: null, template: null).toJson(),
        containsPair('size', 'custom'),
      );
    });

    test('round trip, also through a JSON string', () {
      final samples = [
        const NewNoteOptions(),
        const NewNoteOptions(
          preset: PageSizePreset.widescreen16x9,
          orientation: PageOrientationChoice.landscape,
          template: PageTemplateKind.planner,
          paperColorArgb: PaperColors.black,
        ),
        const NewNoteOptions(
          preset: null,
          customWidthMm: 123.4,
          customHeightMm: 1058.3,
          template: null,
          paperColorArgb: PaperColors.ivory,
        ),
        for (final kind in PageTemplateKind.values)
          NewNoteOptions(template: kind),
      ];
      for (final o in samples) {
        expect(NewNoteOptions.fromJson(o.toJson()), o);
        final decoded =
            jsonDecode(jsonEncode(o.toJson())) as Map<String, Object?>;
        expect(NewNoteOptions.fromJson(decoded), o);
      }
    });

    test('an empty map gives the defaults', () {
      expect(NewNoteOptions.fromJson(const {}), const NewNoteOptions());
    });

    test('unknown size, orientation, template and paper → defaults', () {
      final o = NewNoteOptions.fromJson(const {
        'size': 'a3',
        'orientation': 'diagonal',
        'template': 'hexagon',
        'paper': 'white',
      });
      expect(o, const NewNoteOptions());
    });

    test('template: null means blank page, a missing template the default', () {
      expect(
        NewNoteOptions.fromJson(const {'template': null}).template,
        isNull,
      );
      expect(
        NewNoteOptions.fromJson(const {'size': 'a4'}).template,
        PageTemplateKind.lined,
      );
    });

    test('wrong value types never throw', () {
      final o = NewNoteOptions.fromJson(const {
        'size': 3,
        'orientation': true,
        'customW': <Object?>[],
        'template': 7,
        'paper': null,
      });
      expect(o, const NewNoteOptions());
    });
  });

  defineNewNoteOptionsDecodeTests();
}
