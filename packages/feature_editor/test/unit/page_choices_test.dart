// E-17: the add-page sheet's choices (04-editor 6.11.4) — built only from
// CORE values: backgroundFor, the labels, PageSizePreset.match, value
// equality of TemplateChoice (the preview cells' ValueKey((choice, color,
// size))) and AddPageRequest.positionFor.
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/ui/pages/page_choices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  group('TemplateChoice', () {
    test('value equality (also inside record keys)', () {
      expect(const BlankChoice(), const BlankChoice());
      expect(const BlankChoice().hashCode, const BlankChoice().hashCode);
      // ignore: prefer_const_constructors — two separate instances.
      final a = KindChoice(core.PageTemplateKind.grid);
      // ignore: prefer_const_constructors
      final b = KindChoice(core.PageTemplateKind.grid);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const KindChoice(core.PageTemplateKind.lined)));
      expect(a, isNot(const BlankChoice()));

      const size = core.PageSize.a4Portrait;
      expect(
        ValueKey((a, core.PaperColors.white, size)),
        ValueKey((b, core.PaperColors.white, size)),
      );
      expect(
        ValueKey((a, core.PaperColors.white, size)),
        isNot(ValueKey((a, core.PaperColors.ivory, size))),
      );
      expect(
        ValueKey((a, core.PaperColors.white, size)),
        isNot(ValueKey((a, core.PaperColors.white, size.landscape))),
      );
    });

    test('all = blank + the six CORE kinds in order', () {
      expect(TemplateChoice.all, hasLength(7));
      expect(TemplateChoice.all.first, const BlankChoice());
      expect(TemplateChoice.all.skip(1), [
        for (final k in core.PageTemplateKind.values) KindChoice(k),
      ]);
    });

    test('of(background): template → its kind, everything else → blank', () {
      expect(
        TemplateChoice.of(
          core.TemplateBackground(
            template: const core.PageTemplate(
              kind: core.PageTemplateKind.music,
              spacing: 12,
            ),
          ),
        ),
        const KindChoice(core.PageTemplateKind.music),
      );
      expect(
        TemplateChoice.of(const core.BlankBackground()),
        const BlankChoice(),
      );
      expect(
        TemplateChoice.of(
          const core.PdfBackground(assetId: 'a', pdfPageIndex: 0),
        ),
        const BlankChoice(),
      );
    });
  });

  test('backgroundFor: blank / template defaults with the paper colour', () {
    expect(
      backgroundFor(const BlankChoice(), core.PaperColors.ivory),
      const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
    );
    for (final kind in core.PageTemplateKind.values) {
      final bg = backgroundFor(KindChoice(kind), core.PaperColors.black);
      expect(
        bg,
        core.TemplateBackground(
          template: core.PageTemplate.defaults(kind),
          paperColorArgb: core.PaperColors.black,
        ),
      );
      final template = (bg as core.TemplateBackground).template;
      expect(template.spacing, isNull);
      expect(template.lineColorArgb, isNull, reason: 'INK picks by luminance');
      expect(template.lineWidth, isNull);
    }
  });

  test('labels', () {
    expect(pageSizeLabel(core.PageSizePreset.a4), 'A4');
    expect(pageSizeLabel(core.PageSizePreset.letter), 'Letter');
    expect(pageSizeLabel(core.PageSizePreset.widescreen16x9), '16:9');
    expect(pageSizeLabel(null), '사용자 지정');
    expect(
      [for (final c in core.PaperColors.all) paperColorLabel(c)],
      ['흰색', '미색', '회색', '검정'],
    );
    expect(
      [for (final c in TemplateChoice.all) templateLabel(c)],
      ['빈 페이지', '줄', '모눈', '점', '코넬', '악보', '플래너'],
    );
  });

  test('size row: PageSizePreset.match, either orientation, else custom', () {
    expect(
      core.PageSizePreset.match(core.PageSize.a4Portrait),
      core.PageSizePreset.a4,
    );
    expect(
      core.PageSizePreset.match(core.PageSize.a4Portrait.landscape),
      core.PageSizePreset.a4,
    );
    expect(
      core.PageSizePreset.match(core.PageSize.widescreen16x9),
      core.PageSizePreset.widescreen16x9,
    );
    expect(core.PageSizePreset.match(const core.PageSize(500, 500)), isNull);
  });

  test('paperColorChoiceOf: listed colours stay, others → white', () {
    for (final c in core.PaperColors.all) {
      expect(paperColorChoiceOf(c), c);
    }
    expect(paperColorChoiceOf(0xFF123456), core.PaperColors.white);
  });

  test('AddPageRequest.positionFor', () {
    const bg = core.BlankBackground();
    const size = core.PageSize.a4Portrait;
    AddPageRequest req(AddPagePlacement p, [String? anchor]) => AddPageRequest(
      placement: p,
      size: size,
      background: bg,
      anchorPageId: anchor,
    );
    expect(
      req(AddPagePlacement.before).positionFor('cur'),
      const core.PageBefore('cur'),
    );
    expect(
      req(AddPagePlacement.after).positionFor('cur'),
      const core.PageAfter('cur'),
    );
    expect(
      req(AddPagePlacement.end).positionFor('cur'),
      const core.PageAtEnd(),
    );
    expect(
      req(AddPagePlacement.before, 'x').positionFor('cur'),
      const core.PageBefore('x'),
    );
    expect(
      req(AddPagePlacement.after, 'x').positionFor('cur'),
      const core.PageAfter('x'),
    );
    expect(req(AddPagePlacement.after, 'x'), req(AddPagePlacement.after, 'x'));
  });
}
