// T21 (03-ink 8, 4.10, 6.16, 6.24): the page-template vectors the PDF export
// draws (TemplateVectors.build without clip) — every one of the six kinds has
// items on every page size and paper, and the widths are the template's own
// (no 1-device-px screen minimum).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/background/template_defaults.dart';
import 'package:note_core/note_core.dart' as core;

const _sizes = <String, ui.Size>{
  'A4 portrait': ui.Size(595.28, 841.89),
  'A4 landscape': ui.Size(841.89, 595.28),
  'Letter': ui.Size(612, 792),
  'A5': ui.Size(419.53, 595.28),
};

const _papers = [core.PaperColors.white, core.PaperColors.black];

/// The widths a kind may use with line width [lw]: ruled / grid / staff lines
/// = lw, structure lines (cornell, planner) = 2 · lw, the lined margin line =
/// its own constant.
Set<double> _allowedWidths(core.PageTemplateKind kind, double lw) => {
  lw,
  if (kind == core.PageTemplateKind.cornell ||
      kind == core.PageTemplateKind.planner)
    TemplateDefaults.structureWidthFactor * lw,
  if (kind == core.PageTemplateKind.lined) TemplateDefaults.marginLineWidth,
};

void main() {
  test('the six kinds are the CORE kinds', () {
    expect(core.PageTemplateKind.values, hasLength(6));
  });

  for (final kind in core.PageTemplateKind.values) {
    group(kind.name, () {
      for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
        for (final paper in _papers) {
          test('$sizeName on 0x${paper.toRadixString(16)}: items, all inside '
              'the page, default widths', () {
            final items = TemplateVectors.build(
              core.PageTemplate.defaults(kind),
              pageSize: size,
              paperColorArgb: paper,
            );
            expect(items, isNotEmpty);
            final page = (ui.Offset.zero & size).inflate(1e-6);
            final lw = TemplateDefaults.lineWidthOf(kind);
            for (final item in items) {
              switch (item) {
                case TemplateLine(:final p0, :final p1, :final width):
                  expect(page.contains(p0) && page.contains(p1), isTrue);
                  expect(_allowedWidths(kind, lw), contains(width));
                case TemplateDot(:final center, :final radius):
                  expect(kind, core.PageTemplateKind.dotted);
                  expect(page.contains(center), isTrue);
                  expect(radius, lw / 2);
              }
            }
          });
        }
      }

      test('hairline user widths stay as given (no screen minimum)', () {
        for (final lw in [0.05, 0.1, 0.3, 2.5]) {
          final items = TemplateVectors.build(
            core.PageTemplate(kind: kind, lineWidth: lw),
            pageSize: _sizes['A4 portrait']!,
            paperColorArgb: core.PaperColors.white,
          );
          expect(items, isNotEmpty, reason: 'lineWidth $lw');
          final seen = <double>{};
          for (final item in items) {
            switch (item) {
              case TemplateLine(:final width):
                seen.add(width);
                expect(_allowedWidths(kind, lw), contains(width));
              case TemplateDot(:final radius):
                seen.add(radius * 2);
                expect(radius, lw / 2);
            }
          }
          // The kind's own line width is used (dotted: the dot diameter).
          expect(seen, contains(lw), reason: 'lineWidth $lw');
        }
      });

      test('the export (no clip) = the union of the painter clips', () {
        const size = ui.Size(595.28, 841.89);
        final template = core.PageTemplate.defaults(kind);
        final all = TemplateVectors.build(
          template,
          pageSize: size,
          paperColorArgb: core.PaperColors.white,
        );
        final page = TemplateVectors.build(
          template,
          pageSize: size,
          paperColorArgb: core.PaperColors.white,
          clip: ui.Offset.zero & size,
        );
        expect(page, all);
      });
    });
  }

  test('a template page: the background spec hands the PDF the template', () {
    const template = core.PageTemplate(
      kind: core.PageTemplateKind.music,
      lineWidth: 0.4,
    );
    final spec = InkBackgroundSpec.fromCore(
      const core.TemplateBackground(
        template: template,
        paperColorArgb: core.PaperColors.ivory,
      ),
    );
    expect(spec.kind, InkBackgroundKind.template);
    final items = TemplateVectors.build(
      spec.template!,
      pageSize: const ui.Size(595.28, 841.89),
      paperColorArgb: spec.paperColorArgb,
    );
    expect(items.whereType<TemplateLine>().map((l) => l.width).toSet(), {0.4});
  });
}
