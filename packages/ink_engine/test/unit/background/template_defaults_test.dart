// T13 (03-ink 8, 6.16): the template defaults table — template_defaults.dart
// is the single source of the default template numbers and must equal 6.16.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/background/template_defaults.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  test('spacing per kind (6.16 종류별 표)', () {
    final expected = {
      core.PageTemplateKind.lined: 24.0,
      core.PageTemplateKind.grid: 14.1732,
      core.PageTemplateKind.dotted: 14.1732,
      core.PageTemplateKind.cornell: 24.0,
      core.PageTemplateKind.music: 7.0,
      core.PageTemplateKind.planner: 20.0,
    };
    for (final kind in core.PageTemplateKind.values) {
      expect(TemplateDefaults.spacingOf(kind), expected[kind], reason: '$kind');
    }
    expect(14.1732, closeTo(5 * 72 / 25.4, 1e-4)); // 5 mm
  });

  test(
    'widths: line 0.5 (music 0.6, dot diameter 1.5), structure 2×, margin 0.75',
    () {
      for (final kind in core.PageTemplateKind.values) {
        expect(TemplateDefaults.lineWidthOf(kind), switch (kind) {
          core.PageTemplateKind.music => 0.6,
          core.PageTemplateKind.dotted => 1.5,
          _ => 0.5,
        });
      }
      expect(TemplateDefaults.structureWidthFactor, 2);
      expect(TemplateDefaults.marginLineWidth, 0.75);
    },
  );

  test('colors by paper luminance', () {
    expect(TemplateDefaults.lightLine, 0xFFB7C4D6);
    expect(TemplateDefaults.lightDot, 0xFF9AA5B4);
    expect(TemplateDefaults.lightStructure, 0xFF8FA3BF);
    expect(TemplateDefaults.lightMargin, 0x99E57373);
    expect(TemplateDefaults.darkLine, 0x4DFFFFFF);
    expect(TemplateDefaults.darkDot, 0x66FFFFFF);
    expect(TemplateDefaults.darkStructure, 0x80FFFFFF);
    expect(TemplateDefaults.darkMargin, 0x99EF9A9A);
  });

  test('extras defaults', () {
    expect(TemplateDefaults.linedMarginTop, 72);
    expect(TemplateDefaults.linedMarginLeft, 72);
    expect(TemplateDefaults.linedShowMarginLine, isTrue);
    expect(TemplateDefaults.cornellHeaderHeight, 72);
    expect(TemplateDefaults.cornellCueColumnWidth(595.2756), 178.58268);
    expect(TemplateDefaults.cornellCueColumnWidth(841.8898), 180);
    expect(TemplateDefaults.cornellSummaryHeight(841.8898), 144);
    expect(
      TemplateDefaults.cornellSummaryHeight(595.2756),
      closeTo(119.05512, 1e-9),
    );
    expect(TemplateDefaults.musicMarginTop, 54);
    expect(TemplateDefaults.musicMarginLeft, 36);
    expect(TemplateDefaults.musicStaffGap, 36);
    expect(TemplateDefaults.musicStaffLines, 5);
    expect(TemplateDefaults.plannerLayout, 'weekly');
    expect(TemplateDefaults.plannerMarginTop, 36);
    expect(TemplateDefaults.plannerMarginLeft, 36);
    expect(TemplateDefaults.plannerHeaderHeight, 56);
    expect(TemplateDefaults.plannerTitleOffset, 20);
    expect(TemplateDefaults.plannerCellBottomGap, 4);
  });

  group('ResolvedTemplate', () {
    test(
      'null / non-positive / non-finite spacing and lineWidth → defaults',
      () {
        for (final bad in [null, 0.0, -3.0, double.nan, double.infinity]) {
          final r = ResolvedTemplate(
            core.PageTemplate(
              kind: core.PageTemplateKind.grid,
              spacing: bad,
              lineWidth: bad,
            ),
            paperColorArgb: core.PaperColors.white,
          );
          expect(r.spacing, 14.1732);
          expect(r.lineWidth, 0.5);
        }
        final r = ResolvedTemplate(
          const core.PageTemplate(
            kind: core.PageTemplateKind.grid,
            spacing: 10,
            lineWidth: 0.25,
          ),
          paperColorArgb: core.PaperColors.white,
        );
        expect((r.spacing, r.lineWidth, r.structureWidth), (10, 0.25, 0.5));
      },
    );

    test('extras: missing or wrongly typed key → that key only defaults', () {
      final r = ResolvedTemplate(
        const core.PageTemplate(
          kind: core.PageTemplateKind.lined,
          extras: {
            core.TemplateExtrasKeys.marginTop: 'x',
            core.TemplateExtrasKeys.marginLeft: 100,
            core.TemplateExtrasKeys.showMarginLine: 'no',
            'unknown': 1,
          },
        ),
        paperColorArgb: core.PaperColors.white,
      );
      expect(r.number(core.TemplateExtrasKeys.marginTop, 72), 72);
      expect(r.number(core.TemplateExtrasKeys.marginLeft, 72), 100);
      expect(r.flag(core.TemplateExtrasKeys.showMarginLine, true), isTrue);
      expect(r.number(core.TemplateExtrasKeys.staffGap, 36), 36);
      expect(r.text(core.TemplateExtrasKeys.plannerLayout, 'weekly'), 'weekly');
    });

    test(
      'colors: automatic by paper; lineColorArgb overrides all but margin',
      () {
        for (final paper in core.PaperColors.all) {
          final dark = core.PaperColors.isDark(paper);
          final r = ResolvedTemplate(
            core.PageTemplate.defaults(core.PageTemplateKind.lined),
            paperColorArgb: paper,
          );
          expect(r.lineColor, dark ? 0x4DFFFFFF : 0xFFB7C4D6);
          expect(r.dotColor, dark ? 0x66FFFFFF : 0xFF9AA5B4);
          expect(r.structureColor, dark ? 0x80FFFFFF : 0xFF8FA3BF);
          expect(r.staffColor, r.structureColor);
          expect(r.marginColor, dark ? 0x99EF9A9A : 0x99E57373);
          final o = ResolvedTemplate(
            const core.PageTemplate(
              kind: core.PageTemplateKind.lined,
              lineColorArgb: 0xFF123456,
            ),
            paperColorArgb: paper,
          );
          expect([
            o.lineColor,
            o.dotColor,
            o.structureColor,
            o.staffColor,
          ], everyElement(0xFF123456));
          expect(o.marginColor, r.marginColor);
        }
        expect(core.PaperColors.isDark(core.PaperColors.black), isTrue);
      },
    );
  });
}
